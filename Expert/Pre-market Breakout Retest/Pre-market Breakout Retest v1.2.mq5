//+------------------------------------------------------------------+
//|                        PreMarket_Ultimate_Combo_v9.0.mq5         |
//|                        Feature: Dashboard & Visual SL Update     |
//+------------------------------------------------------------------+
#property copyright "Gemini AI"
#property link "https://www.mql5.com"
#property version "9.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "1. Time & Risk";
input string PreMarketStartTime = "04:00";
input string PreMarketEndTime = "09:30";
input double LotSize = 1.0;
input int Slippage = 3;

input group "2. Strategy Settings";
input double ExtensionPercent = 15.0;
input double TrailingTriggerRatio = 0.5;  // [사용자 설정] 0.5 (50%)
input double TrailingStepRatio = 0.3;

input group "3. Indicator Settings";
input int EMAPeriod = 20;
input color EMAColor = clrYellow;
input color VWAPColor = clrMagenta;

input int MagicNumber = 999999;

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

// States
enum ENUM_STRATEGY_STATE { STATE_WAITING, STATE_BREAKOUT, STATE_RETEST_DONE };
ENUM_STRATEGY_STATE buyState = STATE_WAITING;
ENUM_STRATEGY_STATE sellState = STATE_WAITING;

int lastDayOfYear = -1;
datetime lastBarTime = 0;
string debugMsg = "Initializing...";

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
    Comment("");  // 댓글 삭제
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

    // 대시보드 출력
    UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Dashboard Function                                               |
//+------------------------------------------------------------------+
void UpdateDashboard() {
    string text = "=== Pre-Market Strategy Dashboard ===\n";
    text += "Server Time: " + TimeToString(TimeCurrent(), TIME_MINUTES) + "\n";
    text += "Box Height: " + DoubleToString(pmBoxHeight / _Point, 0) +
            " pts\n";  // 포인트 단위 변환

    double triggerPts = (pmBoxHeight * TrailingTriggerRatio) / _Point;
    text += "Trailing Trigger: " + DoubleToString(triggerPts, 0) + " pts (" +
            DoubleToString(TrailingTriggerRatio * 100, 0) + "%)\n";

    if (PositionsTotal() > 0) {
        for (int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if (PositionSelectByTicket(ticket)) {
                if (PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
                    double profit = PositionGetDouble(POSITION_PROFIT);
                    double open = PositionGetDouble(POSITION_PRICE_OPEN);
                    double current = PositionGetDouble(POSITION_PRICE_CURRENT);
                    double diff = MathAbs(open - current) / _Point;

                    text += "\n[Active Position]\n";
                    text +=
                        "Type: " +
                        (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY
                             ? "BUY"
                             : "SELL") +
                        "\n";
                    text +=
                        "Current Profit: " + DoubleToString(diff, 0) + " pts\n";
                    text += "Status: " + debugMsg + "\n";
                }
            }
        }
    } else {
        text += "\nNo Active Positions.";
    }

    Comment(text);
}

//+------------------------------------------------------------------+
//| Logic: Trailing Stop (Visual Update + StopsLevel)                |
//+------------------------------------------------------------------+
void checkTrailingStop(ulong ticket) {
    long type = PositionGetInteger(POSITION_TYPE);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double curSL = PositionGetDouble(POSITION_SL);
    double curPrice = (type == POSITION_TYPE_BUY)
                          ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                          : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    int stopsLevelPoints =
        (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double stopsLevelPrice =
        (stopsLevelPoints + 10) * _Point;  // 여유분 10포인트 추가

    double trigger = pmBoxHeight * TrailingTriggerRatio;
    double step = trigger * TrailingStepRatio;

    if (trigger == 0) {
        debugMsg = "Error: Box Height is 0";
        return;
    }

    double newSL = 0;
    bool modify = false;

    if (type == POSITION_TYPE_BUY) {
        // 현재 수익이 트리거를 넘었나?
        if (curPrice >= openPrice + trigger) {
            newSL = openPrice;  // 1단계: 본절

            // 2단계: 추가 상승분 반영
            int steps = (int)((curPrice - openPrice - trigger) / step);
            if (steps > 0) newSL += (steps * step);

            // 조건: SL 상승 & 안전거리 확보
            if (newSL > curSL && newSL < (curPrice - stopsLevelPrice)) {
                modify = true;
            } else if (newSL <= curSL)
                debugMsg = "Waiting for more profit (Step)";
            else
                debugMsg = "Too close to price (StopsLevel)";
        } else
            debugMsg = "Not reached Trigger yet";
    } else  // SELL
    {
        // 현재 수익이 트리거를 넘었나?
        if (curPrice <= openPrice - trigger) {
            newSL = openPrice;  // 1단계: 본절

            // 2단계: 추가 하락분 반영
            int steps = (int)((openPrice - curPrice - trigger) / step);
            if (steps > 0) newSL -= (steps * step);

            // 조건: SL 하락 & 안전거리 확보
            // curSL == 0 인 경우는 초기 SL이 없는 경우(방어)
            if ((newSL < curSL || curSL == 0) &&
                newSL > (curPrice + stopsLevelPrice)) {
                modify = true;
            } else if (newSL >= curSL && curSL != 0)
                debugMsg = "Waiting for more profit (Step)";
            else
                debugMsg = "Too close to price (StopsLevel)";
        } else
            debugMsg = "Not reached Trigger yet";
    }

    if (modify) {
        if (trade.PositionModify(ticket, newSL, 0)) {
            debugMsg = "SL Moved to " + DoubleToString(newSL, _Digits);
            Print("Trailing Success: SL moved to ", newSL);

            // [시각화] 노란색 점선(AvgOpen/Close)을 실제 SL 위치로 이동시켜
            // 보여줌
            if (type == POSITION_TYPE_BUY)
                ObjectSetDouble(0, "PM_AvgOpen", OBJPROP_PRICE, 0, newSL);
            else
                ObjectSetDouble(0, "PM_AvgClose", OBJPROP_PRICE, 0, newSL);
        } else {
            debugMsg = "Modify Failed: Err " + IntegerToString(GetLastError());
            Print("Trailing Error: ", GetLastError());
        }
    }
}

// ... (나머지 기본 함수들은 이전과 동일하지만, 매직넘버 필터 적용됨) ...

void managePositions() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket)) {
            // 매직 넘버 확인 (내 포지션만 건드리기)
            if (PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
                checkPartialClose(ticket);
                checkTrailingStop(ticket);
            }
        }
    }
}

// (이하 VWAP, Box 그리기 등 보조 함수는 v8.0과 동일하여 생략하되, 전체
// 복붙용으로 필요하시면 말씀주세요. 위쪽 핵심 로직이 바뀌었으니 기존 v8.0
// 코드의 해당 부분만 교체하시거나, 아래 전체 코드를 사용하세요.)

// --- 아래는 전체 코드 완성본을 위해 필요한 나머지 함수들입니다 ---

void manageVWAPDrawing() { /* v8.0과 동일 */
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

void RedrawVWAPHistory() { /* v8.0과 동일 */
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

void checkNewDay() { /* v8.0과 동일 */
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
        ObjectsDeleteAll(0, "PM_");
        ObjectsDeleteAll(0, "VWAP_Seg_");
        RedrawVWAPHistory();
    }
}

void managePreMarketAnalysis() { /* v8.0과 동일 */
    MqlDateTime st;
    TimeToStruct(TimeCurrent(), st);
    string now = StringFormat("%02d:%02d", st.hour, st.min);
    if (now > PreMarketEndTime && pmHigh == 0) {
        calculatePreMarketStats();
        if (pmHigh > 0) {
            pmBoxHeight = pmHigh - pmLow;
            double extension = pmBoxHeight * (ExtensionPercent / 100.0);
            lineRetestBuy = pmHigh - extension;
            lineRetestSell = pmLow + extension;
            drawLines();
        }
    }
}

void calculatePreMarketStats() { /* v8.0과 동일 */
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

void drawLines() { /* v8.0과 동일 */
    datetime tStart = StringToTime(PreMarketStartTime);
    datetime tEnd = StringToTime(PreMarketEndTime);
    ObjectCreate(0, "PM_Box", OBJ_RECTANGLE, 0, tStart, pmHigh, tEnd, pmLow);
    ObjectSetInteger(0, "PM_Box", OBJPROP_COLOR, clrGray);
    ObjectSetInteger(0, "PM_Box", OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, "PM_Box", OBJPROP_FILL, false);
    ObjectCreate(0, "PM_Retest_Buy", OBJ_HLINE, 0, 0, lineRetestBuy);
    ObjectSetInteger(0, "PM_Retest_Buy", OBJPROP_COLOR, clrRed);
    ObjectCreate(0, "PM_Retest_Sell", OBJ_HLINE, 0, 0, lineRetestSell);
    ObjectSetInteger(0, "PM_Retest_Sell", OBJPROP_COLOR, clrBlue);
    ObjectCreate(0, "PM_AvgOpen", OBJ_HLINE, 0, 0, avgOpen);
    ObjectSetInteger(0, "PM_AvgOpen", OBJPROP_COLOR, clrGold);
    ObjectSetInteger(0, "PM_AvgOpen", OBJPROP_STYLE, STYLE_DASH);
    ObjectCreate(0, "PM_AvgClose", OBJ_HLINE, 0, 0, avgClose);
    ObjectSetInteger(0, "PM_AvgClose", OBJPROP_COLOR, clrGold);
    ObjectSetInteger(0, "PM_AvgClose", OBJPROP_STYLE, STYLE_DASH);
}

void checkStrategyLogic() { /* v8.0과 동일 */
    if (pmHigh == 0) return;
    if (PositionsTotal() > 0) return;
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double close = iClose(_Symbol, _Period, 0);
    switch (buyState) {
        case STATE_WAITING:
            if (close > pmHigh) buyState = STATE_BREAKOUT;
            break;
        case STATE_BREAKOUT:
            if (bid <= lineRetestBuy) buyState = STATE_RETEST_DONE;
            break;
        case STATE_RETEST_DONE:
            if (bid > pmHigh && bid > vwapValue) {
                double sl = MathMax(avgOpen, avgClose);
                if (sl >= bid) sl = pmLow;
                trade.Buy(LotSize, _Symbol, ask, sl, 0, "Retest_Buy_Entry");
                buyState = STATE_WAITING;
            }
            break;
    }
    switch (sellState) {
        case STATE_WAITING:
            if (close < pmLow) sellState = STATE_BREAKOUT;
            break;
        case STATE_BREAKOUT:
            if (bid >= lineRetestSell) sellState = STATE_RETEST_DONE;
            break;
        case STATE_RETEST_DONE:
            if (bid < pmLow && bid < vwapValue) {
                double sl = MathMin(avgOpen, avgClose);
                if (sl <= bid) sl = pmHigh;
                trade.Sell(LotSize, _Symbol, bid, sl, 0, "Retest_Sell_Entry");
                sellState = STATE_WAITING;
            }
            break;
    }
}

void checkPartialClose(ulong ticket) { /* v8.0과 동일 */
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