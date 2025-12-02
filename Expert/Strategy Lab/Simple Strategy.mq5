//+------------------------------------------------------------------+
//|                                           SMC_Fixed_Visuals.mq5 |
//|                                     Copyright 2025, Gemini AI.   |
//+------------------------------------------------------------------+
#property copyright "Gemini AI"
#property link "https://www.mql5.com"
#property version "3.00"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input string InpGroup1 = "=== 1. Risk Settings ===";
input double InpLotSize = 0.1;
input double InpStopLossPips = 10.0;
input double InpTakeProfitPips = 30.0;
input int InpMagicNumber = 777777;

input string InpGroup2 = "=== 2. Time Settings (Check Broker Time!) ===";
input int InpAsiaStartHour = 20;  // Asia Range Start
input int InpAsiaEndHour = 1;     // Asia Range End
input int InpTradeStartHour = 2;  // Trading Allowed From (London Open)
input int InpTradeEndHour = 18;   // Trading Allowed Until (NY Close)

input string InpGroup3 = "=== 3. Visual & Strategy ===";
input bool InpShowArrows = true;         // Draw Swing Points?
input double InpFVGThreshold = 0.00005;  // Gap Sensitivity

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade Trade;
int HandleFractals;
double AsiaHigh = 0, AsiaLow = 0;
bool SweptHigh = false, SweptLow = false;
bool ChoChConfirmed = false;
double LastSwingHigh = 0, LastSwingLow = 0;
datetime LastBarTime = 0;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit() {
    Trade.SetExpertMagicNumber(InpMagicNumber);

    Print(">>> SMC EA V3 Initialized. Check Dashboard on Chart.");
    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    ObjectsDeleteAll(0, "SMC_");
    Comment("");
    IndicatorRelease(HandleFractals);
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick() {
    // --- 1. Dashboard Update (Debug Info) ---
    UpdateDashboard();

    // --- 2. New Bar Logic Only ---
    if (!isNewBar()) return;

    // --- 3. Update Structure (Swing Points) ---
    UpdateSwingPoints();

    // --- 4. Manage Asia Session ---
    ManageSession();

    // --- 5. Trading Logic ---
    if (!IsTradingTime()) return;
    if (PositionsTotal() > 0) return;  // Only 1 trade at a time

    // A. Check Sweep
    CheckLiquiditySweep();

    // B. Check ChoCh (Break of Structure)
    CheckChoCh();

    // C. Enter on FVG
    if (ChoChConfirmed) {
        if (SweptHigh)  // Bearish Bias
        {
            if (DetectBearishFVG()) {
                double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                double sl = LastSwingHigh > bid
                                ? LastSwingHigh
                                : bid + InpStopLossPips * _Point * 10;
                double tp = bid - InpTakeProfitPips * _Point * 10;

                Trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "SMC Sell");
                ResetStrategy();
            }
        } else if (SweptLow)  // Bullish Bias
        {
            if (DetectBullishFVG()) {
                double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                double sl = LastSwingLow < ask && LastSwingLow > 0
                                ? LastSwingLow
                                : ask - InpStopLossPips * _Point * 10;
                double tp = ask + InpTakeProfitPips * _Point * 10;

                Trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "SMC Buy");
                ResetStrategy();
            }
        }
    }
}

//+------------------------------------------------------------------+
//| FUNCTIONS                                                        |
//+------------------------------------------------------------------+
bool isNewBar() {
    datetime t = iTime(_Symbol, _Period, 0);
    if (LastBarTime != t) {
        LastBarTime = t;
        return true;
    }
    return false;
}

void UpdateSwingPoints() {
    // 기준: 좌우 2개 캔들보다 높거나 낮으면 스윙 포인트로 인정 (총 5개 캔들
    // 비교) 현재 캔들(0)은 움직이므로, 확정된 캔들인 3번 캔들을 기준으로
    // 검사합니다.
    int i = 3;

    double h = iHigh(_Symbol, _Period, i);
    double h1 = iHigh(_Symbol, _Period, i - 1);   // Right 1
    double h2 = iHigh(_Symbol, _Period, i - 2);   // Right 2 (Completed)
    double hL1 = iHigh(_Symbol, _Period, i + 1);  // Left 1
    double hL2 = iHigh(_Symbol, _Period, i + 2);  // Left 2

    double l = iLow(_Symbol, _Period, i);
    double l1 = iLow(_Symbol, _Period, i - 1);
    double l2 = iLow(_Symbol, _Period, i - 2);
    double lL1 = iLow(_Symbol, _Period, i + 1);
    double lL2 = iLow(_Symbol, _Period, i + 2);

    // 1. Swing High 감지 (가운데가 가장 높음)
    if (h > h1 && h > h2 && h > hL1 && h > hL2) {
        LastSwingHigh = h;
        if (InpShowArrows) DrawArrow(iTime(_Symbol, _Period, i), h, true);
    }

    // 2. Swing Low 감지 (가운데가 가장 낮음)
    if (l < l1 && l < l2 && l < lL1 && l < lL2) {
        LastSwingLow = l;
        if (InpShowArrows) DrawArrow(iTime(_Symbol, _Period, i), l, false);
    }
}

void ManageSession() {
    MqlDateTime dt;
    TimeCurrent(dt);

    // Reset Strategy Daily at Asia Start
    if (dt.hour == InpAsiaStartHour && dt.min == 0) {
        AsiaHigh = 0;
        AsiaLow = 0;
        ResetStrategy();
        ObjectsDeleteAll(0, "SMC_Arrow");  // Keep dashboard, delete arrows
    }

    bool isAsia = false;
    if (InpAsiaStartHour > InpAsiaEndHour)
        isAsia = (dt.hour >= InpAsiaStartHour || dt.hour < InpAsiaEndHour);
    else
        isAsia = (dt.hour >= InpAsiaStartHour && dt.hour < InpAsiaEndHour);

    if (isAsia) {
        double h = iHigh(_Symbol, _Period, 1);
        double l = iLow(_Symbol, _Period, 1);
        if (AsiaHigh == 0 || h > AsiaHigh) AsiaHigh = h;
        if (AsiaLow == 0 || l < AsiaLow) AsiaLow = l;
    }
}

bool IsTradingTime() {
    MqlDateTime dt;
    TimeCurrent(dt);
    return (dt.hour >= InpTradeStartHour && dt.hour < InpTradeEndHour);
}

void CheckLiquiditySweep() {
    if (SweptHigh || SweptLow) return;  // Already swept

    double h = iHigh(_Symbol, _Period, 1);
    double l = iLow(_Symbol, _Period, 1);

    // Only check if Asia Range is valid
    if (AsiaHigh == 0 || AsiaLow == 0) return;

    if (h > AsiaHigh) {
        SweptHigh = true;
    }
    if (l < AsiaLow) {
        SweptLow = true;
    }
}

void CheckChoCh() {
    if (ChoChConfirmed) return;

    double close = iClose(_Symbol, _Period, 1);

    if (SweptHigh)  // We want price to break BELOW Last Swing Low
    {
        if (LastSwingLow > 0 && close < LastSwingLow) ChoChConfirmed = true;
    } else if (SweptLow)  // We want price to break ABOVE Last Swing High
    {
        if (LastSwingHigh > 0 && close > LastSwingHigh) ChoChConfirmed = true;
    }
}

bool DetectBearishFVG() {
    // Candle 1 High < Candle 3 Low
    double c1High = iHigh(_Symbol, _Period, 1);
    double c3Low = iLow(_Symbol, _Period, 3);
    if (c3Low - c1High > InpFVGThreshold) return true;
    return false;
}

bool DetectBullishFVG() {
    // Candle 1 Low > Candle 3 High
    double c1Low = iLow(_Symbol, _Period, 1);
    double c3High = iHigh(_Symbol, _Period, 3);
    if (c1Low - c3High > InpFVGThreshold) return true;
    return false;
}

void ResetStrategy() {
    SweptHigh = false;
    SweptLow = false;
    ChoChConfirmed = false;
}

void DrawArrow(datetime time, double price, bool isHigh) {
    string name = "SMC_Arrow_" + TimeToString(time);
    if (ObjectFind(0, name) >= 0) return;

    ENUM_OBJECT type = isHigh ? OBJ_ARROW_DOWN : OBJ_ARROW_UP;
    color col = isHigh ? clrRed : clrBlue;

    ObjectCreate(0, name, type, 0, time, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}

void UpdateDashboard() {
    string text = "=== SMC EA V3 Dashboard ===\n";
    text += "Server Time: " + TimeToString(TimeCurrent(), TIME_MINUTES) + "\n";
    text += "Asia Range: " + DoubleToString(AsiaLow, _Digits) + " ~ " +
            DoubleToString(AsiaHigh, _Digits) + "\n";
    text += "--------------------------\n";
    text += "Last Swing High: " + DoubleToString(LastSwingHigh, _Digits) + "\n";
    text += "Last Swing Low:  " + DoubleToString(LastSwingLow, _Digits) + "\n";
    text += "--------------------------\n";
    text += "1. Liquidity Sweep: " +
            (SweptHigh ? "HIGH Taken (Bearish)"
                       : (SweptLow ? "LOW Taken (Bullish)" : "Waiting...")) +
            "\n";
    text +=
        "2. ChoCh Status:    " + (ChoChConfirmed ? "CONFIRMED" : "Waiting...") +
        "\n";

    Comment(text);
}