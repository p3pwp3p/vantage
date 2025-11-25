//+------------------------------------------------------------------+
//|                        PreMarket_Ultimate_Combo_v15.0.mq5        |
//|                        Feature: Cumulative Re-entry Buffer       |
//+------------------------------------------------------------------+
#property copyright "Gemini AI"
#property link "https://www.mql5.com"
#property version "15.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "1. Time & Risk";
input string PreMarketStartTime = "04:00";
input string PreMarketEndTime = "09:30";
input double LotSize = 1.0;
input int Slippage = 3;

input group "2. Strategy Settings";
input double ExtensionPercent = 15.0;      // 리테스트 깊이 (Inside)
input double ReEntryBufferPercent = 10.0;  // [누적] 재진입 시마다 10%씩 추가

input group "3. Breakeven & Partial";
input int BE_TriggerPoints = 100;
input int BE_LockPoints = 10;
input bool UsePartialClose = false;

input group "4. Trailing Stop";
input double TrailingTriggerRatio = 0.5;
input double TrailingStepRatio = 0.3;

input group "5. Indicator Settings";
input int EMAPeriod = 20;
input color EMAColor = clrYellow;
input color VWAPColor = clrMagenta;

input int MagicNumber = 111227;

//--- States
enum ENUM_STRATEGY_STATE { STATE_WAITING, STATE_BREAKOUT, STATE_RETEST_DONE };

//--- Global Variables
CTrade trade;
int emaHandle;
double emaBuffer[];

double pmHigh = 0;
double pmLow = 0;
double pmBoxHeight = 0;
double lineRetestBuy = 0;
double lineRetestSell = 0;

double dailySumPV = 0;
double dailySumVol = 0;
double vwapValue = 0;
double avgOpen = 0;
double avgClose = 0;

ENUM_STRATEGY_STATE buyState = STATE_WAITING;
ENUM_STRATEGY_STATE sellState = STATE_WAITING;

int lastDayOfYear = -1;
datetime lastBarTime = 0;
string debugMsg = "Initializing...";

int tradesTodayCount = 0;  // 오늘 진입 횟수

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(Slippage);

    emaHandle = iMA(_Symbol, _Period, EMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
    if (emaHandle == INVALID_HANDLE) return (INIT_FAILED);

    ChartIndicatorAdd(0, 0, emaHandle);
    ArraySetAsSeries(emaBuffer, true);

    RedrawVWAPHistory();
    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    ObjectsDeleteAll(0, "PM_");
    ObjectsDeleteAll(0, "VWAP_Seg_");
    ChartIndicatorDelete(0, 0, "EMA(" + IntegerToString(EMAPeriod) + ")");
    Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    manageVWAPDrawing();
    checkNewDay();

    if (CopyBuffer(emaHandle, 0, 0, 10, emaBuffer) < 10) return;

    managePreMarketAnalysis();
    checkStrategyLogic();
    managePositions();

    UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void UpdateDashboard() {
    string text = "=== Strategy Status v15.0 (Cumulative Buffer) ===\n";
    text += "Box Height: " + DoubleToString(pmBoxHeight / _Point, 0) + " pts\n";
    text += "Trades Today: " + IntegerToString(tradesTodayCount) + "\n";

    // 현재 적용 중인 버퍼 계산
    double currentBufferPct = ReEntryBufferPercent * tradesTodayCount;
    double currentBufferPts = (pmBoxHeight * currentBufferPct / 100.0) / _Point;

    text += "Next Entry Buffer: +" + DoubleToString(currentBufferPct, 0) +
            "% (" + DoubleToString(currentBufferPts, 0) + " pts)\n";

    if (PositionsTotal() > 0) {
        for (int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if (PositionSelectByTicket(ticket) &&
                PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
                double diff =
                    MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) -
                            PositionGetDouble(POSITION_PRICE_CURRENT)) /
                    _Point;
                text += "\n[Position]\nProfit: " + DoubleToString(diff, 0) +
                        " pts\nMsg: " + debugMsg + "\n";
            }
        }
    }
    Comment(text);
}

//+------------------------------------------------------------------+
//| Logic: Strategy (Cumulative Re-Entry)                            |
//+------------------------------------------------------------------+
void checkStrategyLogic() {
    if (pmHigh == 0) return;
    if (PositionsTotal() > 0) return;  // 포지션 있으면 대기

    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double close = iClose(_Symbol, _Period, 0);
    double fixedSL_Dist = pmBoxHeight * 0.5;

    // [수정] 누적 진입 장벽 계산
    // 1차: 0%, 2차: 10%, 3차: 20% ...
    double addedBuffer =
        pmBoxHeight * (ReEntryBufferPercent / 100.0) * tradesTodayCount;

    double triggerBuyLevel = pmHigh + addedBuffer;
    double triggerSellLevel = pmLow - addedBuffer;

    // --- BUY LOGIC ---
    switch (buyState) {
        case STATE_WAITING:
            if (close > triggerBuyLevel) buyState = STATE_BREAKOUT;
            break;

        case STATE_BREAKOUT:
            if (bid <= lineRetestBuy) buyState = STATE_RETEST_DONE;
            break;

        case STATE_RETEST_DONE:
            // 재진입 시에도 높아진 트리거 레벨을 뚫어야 함
            if (bid > triggerBuyLevel && bid > vwapValue) {
                // SL은 여전히 박스 기준 50%
                double sl = pmHigh - fixedSL_Dist;
                if (trade.Buy(LotSize, _Symbol, ask, sl, 0, "Retest_Buy")) {
                    buyState = STATE_WAITING;
                    tradesTodayCount++;
                    // 진입 후 라인 다시 그리기 (다음 버퍼 보여주기 위해)
                    drawLines();
                }
            }
            break;
    }

    // --- SELL LOGIC ---
    switch (sellState) {
        case STATE_WAITING:
            if (close < triggerSellLevel) sellState = STATE_BREAKOUT;
            break;

        case STATE_BREAKOUT:
            if (bid >= lineRetestSell) sellState = STATE_RETEST_DONE;
            break;

        case STATE_RETEST_DONE:
            if (bid < triggerSellLevel && bid < vwapValue) {
                double sl = pmLow + fixedSL_Dist;
                if (trade.Sell(LotSize, _Symbol, bid, sl, 0, "Retest_Sell")) {
                    sellState = STATE_WAITING;
                    tradesTodayCount++;
                    drawLines();
                }
            }
            break;
    }
}

//+------------------------------------------------------------------+
//| Logic: Pre-Market Analysis                                       |
//+------------------------------------------------------------------+
void managePreMarketAnalysis() {
    MqlDateTime st;
    TimeToStruct(TimeCurrent(), st);
    string now = StringFormat("%02d:%02d", st.hour, st.min);
    if (now > PreMarketEndTime && pmHigh == 0) {
        calculatePreMarketStats();
        if (pmHigh > 0) {
            pmBoxHeight = pmHigh - pmLow;

            // 리테스트 라인 (Inside) - 변동 없음
            double extension = pmBoxHeight * (ExtensionPercent / 100.0);
            lineRetestBuy = pmHigh - extension;
            lineRetestSell = pmLow + extension;

            drawLines();
        }
    }
}

void drawLines() {
    datetime tStart = StringToTime(PreMarketStartTime);
    datetime tEnd = StringToTime(PreMarketEndTime);
    datetime tCurrent = TimeCurrent();
    datetime tDayStart = tCurrent - (tCurrent % 86400);
    datetime tDayEnd = tDayStart + 86400;

    ObjectCreate(0, "PM_Box", OBJ_RECTANGLE, 0, tStart, pmHigh, tEnd, pmLow);
    ObjectSetInteger(0, "PM_Box", OBJPROP_COLOR, clrGray);
    ObjectSetInteger(0, "PM_Box", OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, "PM_Box", OBJPROP_FILL, false);

    // 리테스트 타겟 (빨강/파랑)
    CreateTrendLine("PM_Retest_Buy", tDayStart, lineRetestBuy, tDayEnd,
                    lineRetestBuy, clrRed, STYLE_SOLID);
    CreateTrendLine("PM_Retest_Sell", tDayStart, lineRetestSell, tDayEnd,
                    lineRetestSell, clrBlue, STYLE_SOLID);

    // [수정] 현재 진입 가능한 레벨 표시 (초록 점선) - 누적 버퍼 반영
    double addedBuffer =
        pmBoxHeight * (ReEntryBufferPercent / 100.0) * tradesTodayCount;
    double nextBuyLevel = pmHigh + addedBuffer;
    double nextSellLevel = pmLow - addedBuffer;

    CreateTrendLine("PM_NextEntry_Buy", tDayStart, nextBuyLevel, tDayEnd,
                    nextBuyLevel, clrLime, STYLE_DOT);
    CreateTrendLine("PM_NextEntry_Sell", tDayStart, nextSellLevel, tDayEnd,
                    nextSellLevel, clrLime, STYLE_DOT);

    // [삭제됨] AvgOpen/Close 라인 그리기 제거
}

void CreateTrendLine(string name, datetime t1, double p1, datetime t2,
                     double p2, color c, ENUM_LINE_STYLE style) {
    if (ObjectFind(0, name) < 0)
        ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
    else {
        ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
        ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
        ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
        ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
    }
    ObjectSetInteger(0, name, OBJPROP_COLOR, c);
    ObjectSetInteger(0, name, OBJPROP_STYLE, style);
    ObjectSetInteger(0, name, OBJPROP_RAY, false);
}

void checkNewDay() {
    datetime dt = TimeCurrent();
    MqlDateTime st;
    TimeToStruct(dt, st);
    if (lastDayOfYear != st.day_of_year) {
        lastDayOfYear = st.day_of_year;
        dailySumPV = 0;
        dailySumVol = 0;
        pmHigh = 0;
        pmLow = 0;
        pmBoxHeight = 0;
        avgOpen = 0;
        avgClose = 0;
        buyState = STATE_WAITING;
        sellState = STATE_WAITING;
        tradesTodayCount = 0;  // [리셋]
        ObjectsDeleteAll(0, "PM_");
        ObjectsDeleteAll(0, "VWAP_Seg_");
        RedrawVWAPHistory();
    }
}

// ... (나머지 동일 함수: calculatePreMarketStats, checkTrailingStop,
// checkBreakeven, managePositions, manageVWAPDrawing, RedrawVWAPHistory,
// checkPartialClose) ...
void calculatePreMarketStats() {
    double tempHigh = 0;
    double tempLow = 999999;
    double sumOpen = 0;
    double sumClose = 0;
    int count = 0;
    int bars = iBars(_Symbol, _Period);
    for (int i = 0; i < MathMin(bars, 1440 / _Period); i++) {
        datetime t = iTime(_Symbol, _Period, i);
        MqlDateTime dt;
        TimeToStruct(t, dt);
        string ts = StringFormat("%02d:%02d", dt.hour, dt.min);
        if (dt.day_of_year == lastDayOfYear && ts >= PreMarketStartTime &&
            ts <= PreMarketEndTime) {
            double h = iHigh(_Symbol, _Period, i);
            double l = iLow(_Symbol, _Period, i);
            if (h > tempHigh) tempHigh = h;
            if (l < tempLow) tempLow = l;
            sumOpen += iOpen(_Symbol, _Period, i);
            sumClose += iClose(_Symbol, _Period, i);
            count++;
        }
    }
    if (count > 0) {
        pmHigh = tempHigh;
        pmLow = tempLow;
        avgOpen = sumOpen / count;
        avgClose = sumClose / count;
    }
}
void managePositions() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket) &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
            if (UsePartialClose) checkPartialClose(ticket);
            checkBreakeven(ticket);
            checkTrailingStop(ticket);
        }
    }
}
void checkBreakeven(ulong ticket) {
    long type = PositionGetInteger(POSITION_TYPE);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentSL = PositionGetDouble(POSITION_SL);
    double curPrice = (type == POSITION_TYPE_BUY)
                          ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                          : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double pointsProfit = MathAbs(curPrice - openPrice) / _Point;
    int stopsLevelPoints =
        (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double stopsLevelPrice = (stopsLevelPoints + 5) * _Point;
    if (type == POSITION_TYPE_BUY && currentSL >= openPrice) return;
    if (type == POSITION_TYPE_SELL && currentSL > 0 && currentSL <= openPrice)
        return;
    if (pointsProfit >= BE_TriggerPoints) {
        double newSL = (type == POSITION_TYPE_BUY)
                           ? openPrice + (BE_LockPoints * _Point)
                           : openPrice - (BE_LockPoints * _Point);
        bool safe = (type == POSITION_TYPE_BUY)
                        ? (newSL < (curPrice - stopsLevelPrice))
                        : (newSL > (curPrice + stopsLevelPrice));
        if (safe && trade.PositionModify(ticket, newSL, 0))
            Print("Breakeven Activated");
    }
}
void checkTrailingStop(ulong ticket) {
    long type = PositionGetInteger(POSITION_TYPE);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentSL = PositionGetDouble(POSITION_SL);
    double curPrice = (type == POSITION_TYPE_BUY)
                          ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                          : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    int stopsLevelPoints =
        (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double stopsLevelPrice = (stopsLevelPoints + 5) * _Point;
    double trigger = pmBoxHeight * TrailingTriggerRatio;
    double step = trigger * TrailingStepRatio;
    if (trigger == 0) return;
    double newSL = 0;
    bool shouldModify = false;
    if (type == POSITION_TYPE_BUY) {
        if (curPrice >= openPrice + trigger) {
            double targetSL = curPrice - step;
            if (targetSL < openPrice) targetSL = openPrice;
            if (targetSL > currentSL &&
                targetSL < (curPrice - stopsLevelPrice)) {
                newSL = targetSL;
                shouldModify = true;
                debugMsg = "Buy TS Gap Follow";
            }
        }
    } else {
        if (curPrice <= openPrice - trigger) {
            double targetSL = curPrice + step;
            if (targetSL > openPrice) targetSL = openPrice;
            if ((targetSL < currentSL || currentSL == 0) &&
                targetSL > (curPrice + stopsLevelPrice)) {
                newSL = targetSL;
                shouldModify = true;
                debugMsg = "Sell TS Gap Follow";
            }
        }
    }
    if (shouldModify) {
        if (trade.PositionModify(ticket, newSL, 0)) {
            if (type == POSITION_TYPE_BUY)
                ObjectSetDouble(0, "PM_AvgOpen", OBJPROP_PRICE, 0, newSL);
            else
                ObjectSetDouble(0, "PM_AvgClose", OBJPROP_PRICE, 0, newSL);
        } else
            debugMsg = "TS Err: " + IntegerToString(GetLastError());
    }
}
void manageVWAPDrawing() {
    datetime currentTime = iTime(_Symbol, _Period, 0);
    if (currentTime != lastBarTime) {
        lastBarTime = currentTime;
        RedrawVWAPHistory();
    }
    double curH = iHigh(_Symbol, _Period, 0);
    double curL = iLow(_Symbol, _Period, 0);
    double curC = iClose(_Symbol, _Period, 0);
    double curTyp = (curH + curL + curC) / 3.0;
    long curV = iVolume(_Symbol, _Period, 0);
    double tempSumPV = dailySumPV + (curTyp * (double)curV);
    double tempSumVol = dailySumVol + (double)curV;
    if (tempSumVol > 0)
        vwapValue = tempSumPV / tempSumVol;
    else
        vwapValue = curC;
    double prevVWAP = (dailySumVol > 0) ? (dailySumPV / dailySumVol)
                                        : iClose(_Symbol, _Period, 1);
    string lineName = "VWAP_Seg_Live";
    datetime prevTime = iTime(_Symbol, _Period, 0);
    if (ObjectFind(0, lineName) < 0)
        ObjectCreate(0, lineName, OBJ_TREND, 0, prevTime, prevVWAP,
                     TimeCurrent(), vwapValue);
    else {
        ObjectSetDouble(0, lineName, OBJPROP_PRICE, 0, prevVWAP);
        ObjectSetInteger(0, lineName, OBJPROP_TIME, 0, prevTime);
        ObjectSetDouble(0, lineName, OBJPROP_PRICE, 1, vwapValue);
        ObjectSetInteger(0, lineName, OBJPROP_TIME, 1, TimeCurrent());
    }
    ObjectSetInteger(0, lineName, OBJPROP_COLOR, VWAPColor);
    ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, lineName, OBJPROP_RAY, false);
}
void RedrawVWAPHistory() {
    datetime dt = TimeCurrent();
    datetime startOfDay = dt - (dt % 86400);
    int startBar = iBarShift(_Symbol, _Period, startOfDay);
    if (startBar == -1) return;
    double runPV = 0;
    double runVol = 0;
    double lastVwap = 0;
    for (int i = startBar; i >= 1; i--) {
        double h = iHigh(_Symbol, _Period, i);
        double l = iLow(_Symbol, _Period, i);
        double c = iClose(_Symbol, _Period, i);
        double typ = (h + l + c) / 3.0;
        long v = iVolume(_Symbol, _Period, i);
        if (v > 0) {
            runPV += (typ * (double)v);
            runVol += (double)v;
        }
        double currentVwap = (runVol > 0) ? (runPV / runVol) : c;
        if (i < startBar) {
            string segName = "VWAP_Seg_" + IntegerToString(i);
            datetime t1 = iTime(_Symbol, _Period, i + 1);
            datetime t2 = iTime(_Symbol, _Period, i);
            if (ObjectFind(0, segName) < 0)
                ObjectCreate(0, segName, OBJ_TREND, 0, t1, lastVwap, t2,
                             currentVwap);
            else {
                ObjectSetDouble(0, segName, OBJPROP_PRICE, 0, lastVwap);
                ObjectSetDouble(0, segName, OBJPROP_PRICE, 1, currentVwap);
                ObjectSetInteger(0, segName, OBJPROP_TIME, 0, t1);
                ObjectSetInteger(0, segName, OBJPROP_TIME, 1, t2);
            }
            ObjectSetInteger(0, segName, OBJPROP_COLOR, VWAPColor);
            ObjectSetInteger(0, segName, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, segName, OBJPROP_RAY, false);
            ObjectSetInteger(0, segName, OBJPROP_SELECTABLE, false);
        }
        lastVwap = currentVwap;
    }
    dailySumPV = runPV;
    dailySumVol = runVol;
}
void checkPartialClose(ulong ticket) {
    double vol = PositionGetDouble(POSITION_VOLUME);
    if (vol < LotSize * 0.9) return;
    int rubbing = 0;
    for (int j = 1; j <= 5; j++) {
        double h = iHigh(_Symbol, _Period, j);
        double l = iLow(_Symbol, _Period, j);
        double ema = emaBuffer[j];
        if (l <= ema && h >= ema) rubbing++;
    }
    if (rubbing >= 5 && PositionGetDouble(POSITION_PROFIT) > 0)
        trade.PositionClosePartial(ticket, vol * 0.5);
}