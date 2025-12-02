//+------------------------------------------------------------------+
//|                                            SMC_Pro_Visualizer.mq5 |
//|                                     Copyright 2025, Gemini AI.   |
//+------------------------------------------------------------------+
#property copyright "Gemini AI"
#property link      "https://www.mql5.com"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| User Inputs (PascalCase)                                         |
//+------------------------------------------------------------------+
input string   InpGroup1           = "=== Risk Settings ===";
input double   InpLotSize          = 0.1;       // Fixed Lot Size
input double   InpStopLossPips     = 10.0;      // Stop Loss (Pips)
input double   InpTakeProfitPips   = 30.0;      // Take Profit (Pips)
input int      InpMagicNumber      = 999888;    // Magic Number

input string   InpGroup2           = "=== Time Settings (Server Time) ===";
input int      InpAsiaStartHour    = 20;        // Asia Start Hour
input int      InpAsiaEndHour      = 2;         // Asia End Hour
input int      InpTradeStartHour   = 3;         // London Open
input int      InpTradeEndHour     = 17;        // NY Close

input string   InpGroup3           = "=== Structure & Visual Settings ===";
input int      InpSwingStrength    = 3;         // Swing Detection (Bars on Left/Right)
input bool     InpShowVisuals      = true;      // Show Swing Points on Chart?
input color    InpColorHigh        = clrRed;    // Swing High Color
input color    InpColorLow         = clrBlue;   // Swing Low Color
input double   InpFVGThreshold     = 0.00005;   // Min FVG Size (Points)

//+------------------------------------------------------------------+
//| Global Variables (PascalCase)                                    |
//+------------------------------------------------------------------+
CTrade         Trade;
double         AsiaHigh            = 0;
double         AsiaLow             = 0;
bool           IsAsiaRangeSet      = false;
bool           SweptHigh           = false; // Has price taken Asia High?
bool           SweptLow            = false; // Has price taken Asia Low?
bool           ChoChConfirmed      = false; // Has structure broken after sweep?
datetime       LastBarTime         = 0;

// Structure Memory
double         LastSwingHighPrice  = 0;
double         LastSwingLowPrice   = 0;

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Trade.SetExpertMagicNumber(InpMagicNumber);
   Print("SMC Pro EA Initialized. Waiting for session...");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Remove all visual objects created by EA
   ObjectsDeleteAll(0, "SMC_");
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Process Logic Only on New Bar (Efficiency)
   if(!isNewBar()) return;

   // 2. Identify Swing Points & Draw Visuals
   updateSwingPoints();

   // 3. Manage Asia Session Range
   manageSession();

   // 4. Time Filter & Setup Check
   if(!isTradingTime() || !IsAsiaRangeSet) return;
   if(PositionsTotal() > 0) return; // One trade at a time

   // 5. Strategy Pipeline
   
   // Step A: Check Liquidity Sweep (Asia High/Low)
   checkLiquiditySweep();
   
   // Step B: Check ChoCh (Change of Character)
   // We need a structure break AFTER the sweep to confirm reversal
   checkStructureBreak();

   // Step C: FVG Entry
   if(ChoChConfirmed)
   {
      if(SweptHigh) // Bearish Scenario
      {
         if(detectBearishFVG())
         {
            openSell();
            resetStrategy();
         }
      }
      else if(SweptLow) // Bullish Scenario
      {
         if(detectBullishFVG())
         {
            openBuy();
            resetStrategy();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Custom Functions (camelCase)                                     |
//+------------------------------------------------------------------+

//--- Check for new bar
bool isNewBar()
{
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(LastBarTime != currentBarTime)
   {
      LastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//--- Identify and Draw Swing Points
void updateSwingPoints()
{
   // We look at bar [InpSwingStrength] to see if it's a fractal
   int pivotIndex = InpSwingStrength;
   
   bool isHigh = true;
   bool isLow = true;
   
   // Check neighbors
   for(int i = 1; i <= InpSwingStrength; i++)
   {
      if(iHigh(_Symbol, _Period, pivotIndex) <= iHigh(_Symbol, _Period, pivotIndex - i)) isHigh = false;
      if(iHigh(_Symbol, _Period, pivotIndex) <= iHigh(_Symbol, _Period, pivotIndex + i)) isHigh = false;
      
      if(iLow(_Symbol, _Period, pivotIndex) >= iLow(_Symbol, _Period, pivotIndex - i)) isLow = false;
      if(iLow(_Symbol, _Period, pivotIndex) >= iLow(_Symbol, _Period, pivotIndex + i)) isLow = false;
   }

   // Update Global Swing Variables & Draw
   if(isHigh)
   {
      LastSwingHighPrice = iHigh(_Symbol, _Period, pivotIndex);
      if(InpShowVisuals) createVisualObject(pivotIndex, LastSwingHighPrice, true);
   }
   
   if(isLow)
   {
      LastSwingLowPrice = iLow(_Symbol, _Period, pivotIndex);
      if(InpShowVisuals) createVisualObject(pivotIndex, LastSwingLowPrice, false);
   }
}

//--- Helper: Draw Dot/Arrow on Chart
void createVisualObject(int barIndex, double price, bool isHigh)
{
   datetime time = iTime(_Symbol, _Period, barIndex);
   string objName = "SMC_" + TimeToString(time) + (isHigh ? "_H" : "_L");
   
   if(ObjectFind(0, objName) >= 0) return; // Already exists

   if(isHigh)
      ObjectCreate(0, objName, OBJ_ARROW_TOP, 0, time, price);
   else
      ObjectCreate(0, objName, OBJ_ARROW_BOTTOM, 0, time, price);
      
   ObjectSetInteger(0, objName, OBJPROP_COLOR, (isHigh ? InpColorHigh : InpColorLow));
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
}

//--- Manage Asia Session
void manageSession()
{
   MqlDateTime dt;
   TimeCurrent(dt);

   // Daily Reset
   if(dt.hour == InpAsiaStartHour && dt.min == 0)
   {
      AsiaHigh = 0; AsiaLow = 0;
      IsAsiaRangeSet = false;
      resetStrategy();
      // Optional: Delete old objects daily
      // ObjectsDeleteAll(0, "SMC_"); 
   }

   bool isAsiaTime = false;
   if(InpAsiaStartHour > InpAsiaEndHour)
      isAsiaTime = (dt.hour >= InpAsiaStartHour || dt.hour < InpAsiaEndHour);
   else
      isAsiaTime = (dt.hour >= InpAsiaStartHour && dt.hour < InpAsiaEndHour);

   if(isAsiaTime)
   {
      double h = iHigh(_Symbol, _Period, 1);
      double l = iLow(_Symbol, _Period, 1);
      if(AsiaHigh == 0 || h > AsiaHigh) AsiaHigh = h;
      if(AsiaLow == 0 || l < AsiaLow) AsiaLow = l;
   }
   else if(AsiaHigh != 0)
   {
      IsAsiaRangeSet = true;
   }
}

bool isTradingTime()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   return (dt.hour >= InpTradeStartHour && dt.hour < InpTradeEndHour);
}

//--- Step A: Check Liquidity Sweep
void checkLiquiditySweep()
{
   if(SweptHigh || SweptLow) return; // Already swept

   double currentHigh = iHigh(_Symbol, _Period, 1);
   double currentLow = iLow(_Symbol, _Period, 1);

   // Sweep High -> Look for Shorts
   if(currentHigh > AsiaHigh)
   {
      SweptHigh = true;
      Print("Logic: Asia High Swept. Waiting for Structure Break (ChoCh).");
   }
   // Sweep Low -> Look for Longs
   else if(currentLow < AsiaLow)
   {
      SweptLow = true;
      Print("Logic: Asia Low Swept. Waiting for Structure Break (ChoCh).");
   }
}

//--- Step B: Check Structure Break (ChoCh)
void checkStructureBreak()
{
   if(ChoChConfirmed) return;

   // If Swept High (Bearish Bias), we need price to break below the Last Swing Low
   if(SweptHigh)
   {
      double closePrice = iClose(_Symbol, _Period, 1);
      // Ensure the Swing Low is RECENT (inside the trading session ideally)
      if(LastSwingLowPrice > 0 && closePrice < LastSwingLowPrice)
      {
         ChoChConfirmed = true;
         Print("Logic: ChoCh Confirmed (Bearish). Waiting for FVG.");
      }
   }
   // If Swept Low (Bullish Bias), we need price to break above the Last Swing High
   else if(SweptLow)
   {
      double closePrice = iClose(_Symbol, _Period, 1);
      if(LastSwingHighPrice > 0 && closePrice > LastSwingHighPrice)
      {
         ChoChConfirmed = true;
         Print("Logic: ChoCh Confirmed (Bullish). Waiting for FVG.");
      }
   }
}

//--- Step C: Detect FVG (Same as before but refined)
bool detectBearishFVG()
{
   // Pattern: [Candle 3 (High)] ... Gap ... [Candle 1 (Low)]
   double candle1High = iHigh(_Symbol, _Period, 1);
   double candle3Low = iLow(_Symbol, _Period, 3);
   
   if(candle1High < candle3Low)
   {
      double gap = candle3Low - candle1High;
      if(gap >= InpFVGThreshold) return true;
   }
   return false;
}

bool detectBullishFVG()
{
   // Pattern: [Candle 3 (Low)] ... Gap ... [Candle 1 (High)]
   double candle1Low = iLow(_Symbol, _Period, 1);
   double candle3High = iHigh(_Symbol, _Period, 3);

   if(candle1Low > candle3High)
   {
      double gap = candle1Low - candle3High;
      if(gap >= InpFVGThreshold) return true;
   }
   return false;
}

//--- Execution
void openSell()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = bid + (InpStopLossPips * _Point * 10);
   double tp = bid - (InpTakeProfitPips * _Point * 10);
   
   // Advanced SL: Place SL above the recent Swing High if valid
   if(LastSwingHighPrice > bid) sl = LastSwingHighPrice + (20 * _Point); 

   Trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "SMC Sell Pro");
}

void openBuy()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = ask - (InpStopLossPips * _Point * 10);
   double tp = ask + (InpTakeProfitPips * _Point * 10);

   // Advanced SL
   if(LastSwingLowPrice < ask && LastSwingLowPrice > 0) sl = LastSwingLowPrice - (20 * _Point);

   Trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "SMC Buy Pro");
}

void resetStrategy()
{
   SweptHigh = false;
   SweptLow = false;
   ChoChConfirmed = false;
}