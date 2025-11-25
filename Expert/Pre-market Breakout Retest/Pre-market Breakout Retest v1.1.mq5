//+------------------------------------------------------------------+
//|                        PreMarket_Ultimate_Combo_v7.0.mq5         |
//|                        Logic: Breakout -> Retest -> ReBreak      |
//|                        Visual: VWAP drawn as continuous Line     |
//+------------------------------------------------------------------+
#property copyright "Gemini AI"
#property link "https://www.mql5.com"
#property version "7.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "1. Time & Risk";
input string PreMarketStartTime = "04:00";
input string PreMarketEndTime = "09:30";
input double LotSize = 1.0;
input int Slippage = 3;

input group "2. Strategy Settings";
input double ExtensionPercent = 15.0;  // 리테스트 깊이 (%)
input double TrailingTriggerRatio = 1.0;
input double TrailingStepRatio = 0.5;

input group "3. Indicator Settings";
input int EMAPeriod = 20;
input color EMAColor = clrYellow;
input color VWAPColor = clrMagenta;  // VWAP 라인 색상

input int MagicNumber = 777777;

//--- States
enum ENUM_STRATEGY_STATE { STATE_WAITING, STATE_BREAKOUT, STATE_RETEST_DONE };

//--- Global Variables
CTrade trade;
int emaHandle;
double emaBuffer[];

// Strategy Variables
double pmHigh = 0;
double pmLow = 0;
double pmBoxHeight = 0;
double lineRetestBuy = 0;
double lineRetestSell = 0;

// VWAP Variables
double dailySumPV = 0;
double dailySumVol = 0;
double vwapValue = 0;  // 현재 실시간 VWAP 값

double avgOpen = 0;
double avgClose = 0;

// State Management
ENUM_STRATEGY_STATE buyState = STATE_WAITING;
ENUM_STRATEGY_STATE sellState = STATE_WAITING;

int lastDayOfYear = -1;
datetime lastBarTime = 0;

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

    // 초기화 시 오늘자 VWAP 히스토리 라인 쫙 그리기
    RedrawVWAPHistory();

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    ObjectsDeleteAll(0, "PM_");
    ObjectsDeleteAll(0, "VWAP_Seg_");  // VWAP 선분들 삭제
    ChartIndicatorDelete(0, 0, "EMA(" + IntegerToString(EMAPeriod) + ")");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // 1. VWAP 관리 (MA처럼 선 그리기)
    manageVWAPDrawing();

    // 2. 날짜 변경 체크
    checkNewDay();

    // 3. EMA 업데이트
    if (CopyBuffer(emaHandle, 0, 0, 10, emaBuffer) < 10) return;

    // 4. 프리마켓 분석
    managePreMarketAnalysis();

    // 5. 전략 로직 (3단계)
    checkStrategyLogic();

    // 6. 포지션 관리
    managePositions();
}

//+------------------------------------------------------------------+
//| Logic: VWAP Line Drawing (Continuous)                            |
//+------------------------------------------------------------------+
void manageVWAPDrawing() {
    datetime currentTime = iTime(_Symbol, _Period, 0);

    // 새 봉이 생기면 확정된 구간을 선으로 고정하고 누적 데이터 업데이트
    if (currentTime != lastBarTime) {
        lastBarTime = currentTime;
        // 새 봉이 떴으므로, 방금 마감된 봉까지의 VWAP 라인을 확정 짓기 위해
        // 전체 다시 계산 권장 (오차 보정)
        RedrawVWAPHistory();
    }

    // 실시간(Current Tick) 선분 그리기
    // 직전 봉의 VWAP 값과 현재 봉의 실시간 VWAP 값을 잇는 선

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
        vwapValue = curC;  // 데이터 없을 땐 종가

    // 직전 봉 시점의 VWAP 값 필요 (선 연결용)
    // dailySumPV/Vol 은 직전 봉까지의 합산임.
    double prevVWAP = (dailySumVol > 0) ? (dailySumPV / dailySumVol)
                                        : iClose(_Symbol, _Period, 1);

    // 현재 진행 중인 선분 그리기 (Live Line)
    string lineName = "VWAP_Seg_Live";
    datetime prevTime = iTime(_Symbol, _Period, 0);  // 현재 봉 시작 시간
    datetime futureTime =
        prevTime + PeriodSeconds();  // 현재 봉 끝나는 시간(대략)

    // 시각적으로 현재 봉 위치에 점을 찍거나 짧은 선을 유지
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

// 오늘 하루치 VWAP 라인을 다시 계산해서 그리는 함수 (MA처럼 보이게 함)
void RedrawVWAPHistory() {
    datetime dt = TimeCurrent();
    datetime startOfDay = dt - (dt % 86400);  // 오늘 00:00

    int startBar = iBarShift(_Symbol, _Period, startOfDay);
    if (startBar == -1) return;

    double runPV = 0;
    double runVol = 0;
    double lastVwap = 0;

    // 과거부터 현재 직전 봉(1)까지 루프
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

        // 선 그리기 (i+1 번째 VWAP -> i 번째 VWAP 연결)
        if (i < startBar)  // 첫 봉은 연결할 이전 점이 없으므로 패스
        {
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

    // 전역 변수 업데이트 (마지막 확정 데이터 저장)
    dailySumPV = runPV;
    dailySumVol = runVol;
}

//+------------------------------------------------------------------+
//| Logic: New Day Reset                                             |
//+------------------------------------------------------------------+
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

        ObjectsDeleteAll(0, "PM_");
        ObjectsDeleteAll(0, "VWAP_Seg_");  // 지난 날의 선 삭제
        RedrawVWAPHistory();               // 새 날짜 초기화
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
            double extension = pmBoxHeight * (ExtensionPercent / 100.0);

            lineRetestBuy = pmHigh - extension;
            lineRetestSell = pmLow + extension;

            drawLines();
        }
    }
}

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

void drawLines() {
    datetime tStart = StringToTime(PreMarketStartTime);
    datetime tEnd = StringToTime(PreMarketEndTime);

    ObjectCreate(0, "PM_Box", OBJ_RECTANGLE, 0, tStart, pmHigh, tEnd, pmLow);
    ObjectSetInteger(0, "PM_Box", OBJPROP_COLOR, clrGray);
    ObjectSetInteger(0, "PM_Box", OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, "PM_Box", OBJPROP_FILL, false);

    ObjectCreate(0, "PM_Retest_Buy", OBJ_HLINE, 0, 0, lineRetestBuy);
    ObjectSetInteger(0, "PM_Retest_Buy", OBJPROP_COLOR, clrRed);
    ObjectSetString(0, "PM_Retest_Buy", OBJPROP_TEXT, "Buy Retest Target");

    ObjectCreate(0, "PM_Retest_Sell", OBJ_HLINE, 0, 0, lineRetestSell);
    ObjectSetInteger(0, "PM_Retest_Sell", OBJPROP_COLOR, clrBlue);
    ObjectSetString(0, "PM_Retest_Sell", OBJPROP_TEXT, "Sell Retest Target");

    ObjectCreate(0, "PM_AvgOpen", OBJ_HLINE, 0, 0, avgOpen);
    ObjectSetInteger(0, "PM_AvgOpen", OBJPROP_COLOR, clrGold);
    ObjectSetInteger(0, "PM_AvgOpen", OBJPROP_STYLE, STYLE_DASH);

    ObjectCreate(0, "PM_AvgClose", OBJ_HLINE, 0, 0, avgClose);
    ObjectSetInteger(0, "PM_AvgClose", OBJPROP_COLOR, clrGold);
    ObjectSetInteger(0, "PM_AvgClose", OBJPROP_STYLE, STYLE_DASH);
}

//+------------------------------------------------------------------+
//| Logic: 3-Step Strategy Check                                     |
//+------------------------------------------------------------------+
void checkStrategyLogic() {
    if (pmHigh == 0) return;
    if (PositionsTotal() > 0) return;

    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double close = iClose(_Symbol, _Period, 0);

    // --- BUY LOGIC ---
    switch (buyState) {
        case STATE_WAITING:
            if (close > pmHigh) {
                buyState = STATE_BREAKOUT;
                Print("Buy Step 1: Breakout > ", pmHigh);
            }
            break;
        case STATE_BREAKOUT:
            if (bid <= lineRetestBuy) {
                buyState = STATE_RETEST_DONE;
                Print("Buy Step 2: Retest Done @ ", bid);
            }
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

    // --- SELL LOGIC ---
    switch (sellState) {
        case STATE_WAITING:
            if (close < pmLow) {
                sellState = STATE_BREAKOUT;
                Print("Sell Step 1: Breakout < ", pmLow);
            }
            break;
        case STATE_BREAKOUT:
            if (bid >= lineRetestSell) {
                sellState = STATE_RETEST_DONE;
                Print("Sell Step 2: Retest Done @ ", bid);
            }
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

//+------------------------------------------------------------------+
//| Logic: Exits                                                     |
//+------------------------------------------------------------------+
void managePositions() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket)) {
            checkPartialClose(ticket);
            checkTrailingStop(ticket);
        }
    }
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

void checkTrailingStop(ulong ticket) {
    long type = PositionGetInteger(POSITION_TYPE);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double curSL = PositionGetDouble(POSITION_SL);
    double curPrice = (type == POSITION_TYPE_BUY)
                          ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                          : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double trigger = pmBoxHeight * TrailingTriggerRatio;
    double step = trigger * TrailingStepRatio;
    if (type == POSITION_TYPE_BUY) {
        if (curPrice >= openPrice + trigger) {
            double newSL = openPrice;
            int steps = (int)((curPrice - openPrice - trigger) / step);
            if (steps > 0) newSL += (steps * step);
            if (newSL > curSL && newSL < curPrice)
                trade.PositionModify(ticket, newSL, 0);
        }
    } else {
        if (curPrice <= openPrice - trigger) {
            double newSL = openPrice;
            int steps = (int)((openPrice - curPrice - trigger) / step);
            if (steps > 0) newSL -= (steps * step);
            if ((newSL < curSL || curSL == 0) && newSL > curPrice)
                trade.PositionModify(ticket, newSL, 0);
        }
    }
}