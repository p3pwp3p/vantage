//+------------------------------------------------------------------+
//|                                     PreMarket_Breakout_v2.mq5    |
//|                                     Fix: VWAP Logic & EMA Buffer |
//+------------------------------------------------------------------+
#property copyright "Gemini AI"
#property link "https://www.mql5.com"
#property version "2.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters (PascalCase)
input string PreMarketStartTime = "04:00";  // 프리마켓 시작 시간 (Server Time)
input string PreMarketEndTime = "09:30";    // 프리마켓 종료 시간 (장 시작)
input double LotSize = 1.0;                 // 거래 랏(Lot)
input int Slippage = 3;                     // 슬리피지
input int MagicNumber = 123456;             // 매직 넘버

//--- Strategy Settings
input int EMAPeriod = 8;             // EMA 기간
input int ExitBufferPoints = 50;     // 청산 여유 버퍼 (포인트 단위, 50=5pips)
input color EMAColor = clrYellow;    // EMA 선 색상
input color VWAPColor = clrMagenta;  // VWAP 선 색상

//--- Global Variables
CTrade trade;
int emaHandle;
double emaBuffer[];

// VWAP Calculation Variables
double dailySumPV = 0;   // 누적 (가격 * 거래량)
double dailySumVol = 0;  // 누적 거래량
int lastDayOfYear = -1;
double currentVwapValue = 0;

// Pre-Market Variables
double pmHigh = 0;
double pmLow = 0;
bool isBreakoutBullish = false;
bool isBreakoutBearish = false;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(Slippage);

    // EMA Indicator Setup
    emaHandle = iMA(_Symbol, _Period, EMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
    if (emaHandle == INVALID_HANDLE) return (INIT_FAILED);

    ChartIndicatorAdd(0, 0, emaHandle);  // Add EMA to Chart
    ArraySetAsSeries(emaBuffer, true);

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    ObjectsDeleteAll(0, "PM_Box");
    ObjectsDeleteAll(0, "VWAP_Line");
    ChartIndicatorDelete(0, 0, "EMA(" + string(EMAPeriod) + ")");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // 1. Calculate Real-time VWAP
    calculateRealTimeVWAP();

    // 2. Logic on New Bar (Once per candle close)
    bool newBar = isNewBar();

    // If New Bar, update accumulated VWAP data (Fix for logic)
    if (newBar) {
        updateVWAPHistory();
    }

    // 3. Get EMA Data
    if (CopyBuffer(emaHandle, 0, 0, 2, emaBuffer) < 2) return;
    double currentEMA = emaBuffer[0];                 // Current running EMA
    double closePrice = iClose(_Symbol, _Period, 0);  // Current running Price

    // 4. Draw/Manage Pre-Market Box
    managePreMarketLevels();

    // We usually check entry/exit on confirmed close (New Bar),
    // but for trailing, we can check tick or close.
    // Here we check on Ticks for faster exit, OR strictly on Close.
    // Let's stick to Close for stability as requested.
    if (!newBar) return;

    // Using index 1 (Confirmed Close) for logic
    double closedPrice = iClose(_Symbol, _Period, 1);
    double confirmedEMA = emaBuffer[1];

    checkExitConditions(closedPrice, confirmedEMA);
    checkEntryConditions(closedPrice);
}

//+------------------------------------------------------------------+
//| Helper: Detect New Bar                                           |
//+------------------------------------------------------------------+
bool isNewBar() {
    datetime currentTime = iTime(_Symbol, _Period, 0);
    if (currentTime != lastBarTime) {
        lastBarTime = currentTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Helper: Update VWAP History (On Bar Close)                       |
//+------------------------------------------------------------------+
void updateVWAPHistory() {
    // Add the COMPLETED bar (index 1) to the daily sum
    // Reset if new day
    datetime dt = iTime(_Symbol, _Period, 1);  // Time of closed bar
    MqlDateTime st;
    TimeToStruct(dt, st);

    if (lastDayOfYear != st.day_of_year) {
        dailySumPV = 0;
        dailySumVol = 0;
        lastDayOfYear = st.day_of_year;
        ObjectsDeleteAll(0, "VWAP_Line");
    }

    // Standard VWAP: Typical Price (H+L+C)/3 is often used, but we use Close
    // for simplicity or user request. Let's use Typical Price for better
    // accuracy.
    double high = iHigh(_Symbol, _Period, 1);
    double low = iLow(_Symbol, _Period, 1);
    double close = iClose(_Symbol, _Period, 1);
    double typicalPrice = (high + low + close) / 3.0;
    long vol = iVolume(_Symbol, _Period, 1);

    if (vol > 0) {
        dailySumPV += (typicalPrice * (double)vol);
        dailySumVol += (double)vol;
    }
}

//+------------------------------------------------------------------+
//| Helper: Calculate & Draw Live VWAP                               |
//+------------------------------------------------------------------+
void calculateRealTimeVWAP() {
    // Base is dailySum (History) + Current Bar (Live)
    double curHigh = iHigh(_Symbol, _Period, 0);
    double curLow = iLow(_Symbol, _Period, 0);
    double curClose = iClose(_Symbol, _Period, 0);
    double curTypical = (curHigh + curLow + curClose) / 3.0;
    long curVol = iVolume(_Symbol, _Period, 0);

    double totalPV = dailySumPV + (curTypical * (double)curVol);
    double totalVol = dailySumVol + (double)curVol;

    if (totalVol > 0) {
        currentVwapValue = totalPV / totalVol;
    }

    // Draw Visualization (Line)
    datetime currentTime = TimeCurrent();
    MqlDateTime st;
    TimeToStruct(currentTime, st);
    string lineName =
        "VWAP_Line_" + IntegerToString(st.hour) + "_" + IntegerToString(st.min);

    // To make it look like a continuous line, we actually need to draw
    // segments. Simplified: Move a single trendline end point (efficient) or
    // draw dots. Here: Updating a long trendline for the day is complex in MT5
    // objects. We will draw short segments per bar.

    // FIX: Let's draw a horizontal line segment for current moment to visualize
    string objName = "VWAP_Current";
    if (ObjectFind(0, objName) < 0) {
        ObjectCreate(0, objName, OBJ_TREND, 0, currentTime, currentVwapValue,
                     currentTime, currentVwapValue);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, VWAPColor);
        ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT,
                         true);  // Ray to see clearly
    } else {
        // Move start to recently closed bar time, end to current
        ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, currentVwapValue);
        ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, currentVwapValue);
        ObjectSetInteger(
            0, objName, OBJPROP_TIME, 0,
            currentTime - PeriodSeconds() * 10);  // Show recent context
        ObjectSetInteger(0, objName, OBJPROP_TIME, 1,
                         currentTime + PeriodSeconds());
    }
}

//+------------------------------------------------------------------+
//| Core Logic: Manage Pre-Market Box                                |
//+------------------------------------------------------------------+
void managePreMarketLevels() {
    datetime dt = TimeCurrent();
    MqlDateTime st;
    TimeToStruct(dt, st);
    string timeStr = StringFormat("%02d:%02d", st.hour, st.min);

    if (timeStr < PreMarketStartTime) {
        pmHigh = 0;
        pmLow = 0;
        isBreakoutBullish = false;
        isBreakoutBearish = false;
        return;
    }

    if (timeStr >= PreMarketStartTime && timeStr <= PreMarketEndTime) {
        double h = iHigh(_Symbol, _Period, 1);  // Check closed bar
        double l = iLow(_Symbol, _Period, 1);

        if (pmHigh == 0 || h > pmHigh) pmHigh = h;
        if (pmLow == 0 || l < pmLow) pmLow = l;
        if (pmLow == 0) pmLow = l;

        // Draw Box
        string objName = "PM_Box_" + IntegerToString(st.day_of_year);
        if (ObjectFind(0, objName) < 0) {
            ObjectCreate(0, objName, OBJ_RECTANGLE, 0, dt, pmHigh, dt, pmLow);
            ObjectSetInteger(0, objName, OBJPROP_COLOR, clrGray);
            ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DOT);
            ObjectSetInteger(0, objName, OBJPROP_FILL, false);
        } else {
            ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, pmHigh);
            ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, pmLow);
            ObjectSetInteger(0, objName, OBJPROP_TIME, 1, dt);
        }
    }
}

//+------------------------------------------------------------------+
//| Core Logic: Check Entry (Breakout -> Limit)                      |
//+------------------------------------------------------------------+
void checkEntryConditions(double closePrice) {
    MqlDateTime st;
    TimeToStruct(TimeCurrent(), st);
    string now = StringFormat("%02d:%02d", st.hour, st.min);
    if (now <= PreMarketEndTime) return;

    if (PositionsTotal() > 0 || OrdersTotal() > 0) return;

    // Buy Setup
    if (closePrice > pmHigh && !isBreakoutBullish) {
        // VWAP Filter
        if (closePrice > currentVwapValue) {
            isBreakoutBullish = true;
            trade.BuyLimit(LotSize, pmHigh, _Symbol, 0, 0, ORDER_TIME_DAY, 0,
                           "Retest Buy");
        }
    }

    // Sell Setup
    if (closePrice < pmLow && !isBreakoutBearish) {
        // VWAP Filter
        if (closePrice < currentVwapValue) {
            isBreakoutBearish = true;
            trade.SellLimit(LotSize, pmLow, _Symbol, 0, 0, ORDER_TIME_DAY, 0,
                            "Retest Sell");
        }
    }
}

//+------------------------------------------------------------------+
//| Core Logic: Check Exit (Buffer + EMA)                            |
//+------------------------------------------------------------------+
void checkExitConditions(double closePrice, double emaVal) {
    double buffer = ExitBufferPoints * _Point;  // Convert Points to Price

    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket)) {
            long type = PositionGetInteger(POSITION_TYPE);

            if (type == POSITION_TYPE_BUY) {
                // Stop Loss: Close falls back inside Pre-Market Range
                if (closePrice < pmHigh) trade.PositionClose(ticket);

                // Trailing Stop: Close is BELOW (EMA - Buffer)
                // Example: EMA is 100, Buffer is 2. Close < 98 -> Exit.
                // If Close is 99 (rubbing EMA), we hold.
                else if (closePrice < (emaVal - buffer))
                    trade.PositionClose(ticket);
            } else if (type == POSITION_TYPE_SELL) {
                // Stop Loss
                if (closePrice > pmLow) trade.PositionClose(ticket);

                // Trailing Stop: Close is ABOVE (EMA + Buffer)
                else if (closePrice > (emaVal + buffer))
                    trade.PositionClose(ticket);
            }
        }
    }
}