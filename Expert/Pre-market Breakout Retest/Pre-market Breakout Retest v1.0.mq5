//+------------------------------------------------------------------+
//|                          Pre-market Breakout Retest (Final).mq5  |
//|                                     Fix: Indicator Path Error    |
//+------------------------------------------------------------------+
#property copyright "Gemini AI"
#property link "https://www.mql5.com"
#property version "4.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input string PreMarketStartTime = "04:00";
input string PreMarketEndTime = "09:30";
input double LotSize = 1.0;
input int Slippage = 3;
input int MagicNumber = 123456;
input int ExitBufferPoints = 50;

//--- Indicator Settings
input int InpEmaPeriod = 8;
input color InpEmaColor = clrWhite;
input color InpVwapColor = clrMagenta;

//--- Indicator Paths (수정됨: Indicators 폴더 기준)
// 파일 이동 후 경로: MQL5/Indicators/p3pwp3p/p3pwp3p VWAP.ex5
string IndicatorPath_VWAP = "p3pwp3p\\p3pwp3p VWAP";
string IndicatorPath_EMA = "p3pwp3p\\p3pwp3p EMA";

//--- Global Variables
CTrade trade;
int handleVWAP = INVALID_HANDLE;
int handleEMA = INVALID_HANDLE;
double vwapValues[];
double emaValues[];

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

    // 1. VWAP 로딩
    handleVWAP = iCustom(_Symbol, _Period, IndicatorPath_VWAP, InpVwapColor);
    if (handleVWAP == INVALID_HANDLE) {
        Print("CRITICAL ERROR: Failed to load VWAP.");
        Print("Please move .ex5 file to: MQL5\\Indicators\\",
              IndicatorPath_VWAP);
        return (INIT_FAILED);
    }

    // 2. EMA 로딩
    handleEMA =
        iCustom(_Symbol, _Period, IndicatorPath_EMA, InpEmaPeriod, InpEmaColor);
    if (handleEMA == INVALID_HANDLE) {
        Print("CRITICAL ERROR: Failed to load EMA.");
        Print("Please move .ex5 file to: MQL5\\Indicators\\",
              IndicatorPath_EMA);
        return (INIT_FAILED);
    }

    ChartIndicatorAdd(0, 0, handleVWAP);
    ChartIndicatorAdd(0, 0, handleEMA);

    ArraySetAsSeries(vwapValues, true);
    ArraySetAsSeries(emaValues, true);

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    ObjectsDeleteAll(0, "PM_Box");
    ChartIndicatorDelete(0, 0, "p3pwp3p VWAP");
    ChartIndicatorDelete(0, 0, "p3pwp3p EMA");
    IndicatorRelease(handleVWAP);
    IndicatorRelease(handleEMA);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    bool newBar = isNewBar();

    if (CopyBuffer(handleVWAP, 0, 0, 2, vwapValues) < 2) return;
    if (CopyBuffer(handleEMA, 0, 0, 2, emaValues) < 2) return;

    managePreMarketLevels();

    if (!newBar) return;

    double closedPrice = iClose(_Symbol, _Period, 1);
    double closedVWAP = vwapValues[1];
    double closedEMA = emaValues[1];

    checkExitConditions(closedPrice, closedEMA);
    checkEntryConditions(closedPrice, closedVWAP);
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
        double h = iHigh(_Symbol, _Period, 1);
        double l = iLow(_Symbol, _Period, 1);

        if (pmHigh == 0 || h > pmHigh) pmHigh = h;
        if (pmLow == 0 || l < pmLow) pmLow = l;
        if (pmLow == 0) pmLow = l;

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
//| Core Logic: Check Entry                                          |
//+------------------------------------------------------------------+
void checkEntryConditions(double closePrice, double vwapVal) {
    MqlDateTime st;
    TimeToStruct(TimeCurrent(), st);
    string now = StringFormat("%02d:%02d", st.hour, st.min);
    if (now <= PreMarketEndTime) return;

    if (PositionsTotal() > 0 || OrdersTotal() > 0) return;

    if (closePrice > pmHigh && !isBreakoutBullish) {
        if (closePrice > vwapVal) {
            isBreakoutBullish = true;
            trade.BuyLimit(LotSize, pmHigh, _Symbol, 0, 0, ORDER_TIME_DAY, 0,
                           "Retest Buy");
        }
    }

    if (closePrice < pmLow && !isBreakoutBearish) {
        if (closePrice < vwapVal) {
            isBreakoutBearish = true;
            trade.SellLimit(LotSize, pmLow, _Symbol, 0, 0, ORDER_TIME_DAY, 0,
                            "Retest Sell");
        }
    }
}

//+------------------------------------------------------------------+
//| Core Logic: Check Exit                                           |
//+------------------------------------------------------------------+
void checkExitConditions(double closePrice, double emaVal) {
    double buffer = ExitBufferPoints * _Point;

    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket)) {
            long type = PositionGetInteger(POSITION_TYPE);

            if (type == POSITION_TYPE_BUY) {
                if (closePrice < pmHigh)
                    trade.PositionClose(ticket);
                else if (closePrice < (emaVal - buffer))
                    trade.PositionClose(ticket);
            } else if (type == POSITION_TYPE_SELL) {
                if (closePrice > pmLow)
                    trade.PositionClose(ticket);
                else if (closePrice > (emaVal + buffer))
                    trade.PositionClose(ticket);
            }
        }
    }
}