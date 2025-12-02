//+------------------------------------------------------------------+
//|                                 Pre-market Breakout Retest.mq5   |
//|                                             Copyright, p3pwp3p   |
//+------------------------------------------------------------------+
#property copyright "p3pwp3p"
#property link "https://www.mql5.com"
#property version "1.4"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "1. Time & Risk";
input string PreMarketStartTime = "04:00";
input string PreMarketEndTime = "09:30";
input double LotSize = 1.0;
input int Slippage = 3;
input double MaxDrawdownPercent = 5.0;

input group "2. Strategy Settings";
input double ExtensionPercent = 15.0;
input double ReEntryBufferPercent = 10.0;
input bool UseTrendFilter = true;
input int TrendFilterPeriod = 50;

input group "3. Take Profit (New)";
input double TakeProfitRatio = 2.0;

input group "4. Add Position (Refined)";
input bool UseAddPosition = true;
input double AddPositionMultiplier = 1.0;
input int MaxAddCount = 1;

input group "5. Breakeven (Looser)";
input int BE_TriggerPoints = 300;
input int BE_LockPoints = 10;
input bool UsePartialClose = false;

input group "6. Trailing Stop";
input double TrailingTriggerRatio = 0.5;
input double TrailingStepRatio = 0.3;

input group "7. Indicator Settings";
input int EMAPeriod = 20;
input color EMAColor = clrYellow;
input color VWAPColor = clrMagenta;

input group "8. Advanced Filters";
input int RSIPeriod = 14;
input double RSI_BuyThreshold = 60;
input double RSI_SellThreshold = 40;

input group "9. Dynamic Risk (ATR)";
input int ATRPeriod = 14;
input double ATR_SL_Ratio = 1.5;
input double ATR_TP_Ratio = 3.0;

input int MagicNumber = 111232;

//--- Global Variables
CTrade trade;
int emaHandle;
int trendEmaHandle;
double emaBuffer[];
double trendEmaBuffer[];

double pmHigh = 0;
double pmLow = 0;
double pmBoxHeight = 0;
double pmMidLine = 0;
double lineRetestBuy = 0;
double lineRetestSell = 0;
double lineReEntryBuy = 0;
double lineReEntrySell = 0;

double dailySumPV = 0;
double dailySumVol = 0;
double vwapValue = 0;
double avgOpen = 0;
double avgClose = 0;

int rsiHandle;
int atrHandle;
double rsiBuffer[];
double atrBuffer[];

enum ENUM_STRATEGY_STATE { STATE_WAITING, STATE_BREAKOUT, STATE_RETEST_DONE };
ENUM_STRATEGY_STATE buyState = STATE_WAITING;
ENUM_STRATEGY_STATE sellState = STATE_WAITING;

int lastDayOfYear = -1;
datetime lastBarTime = 0;
string debugMsg = "Initializing...";
int tradesTodayCount = 0;

int currentAddCount = 0;
bool hasAddedPosition = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(Slippage);

    emaHandle = iMA(_Symbol, _Period, EMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
    trendEmaHandle =
        iMA(_Symbol, PERIOD_H1, TrendFilterPeriod, 0, MODE_EMA, PRICE_CLOSE);

    rsiHandle = iRSI(_Symbol, _Period, RSIPeriod, PRICE_CLOSE);
    atrHandle = iATR(_Symbol, _Period, ATRPeriod);

    if (emaHandle == INVALID_HANDLE || trendEmaHandle == INVALID_HANDLE ||
        rsiHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
        return (INIT_FAILED);

    ChartIndicatorAdd(0, 0, emaHandle);

    ArraySetAsSeries(emaBuffer, true);
    ArraySetAsSeries(trendEmaBuffer, true);

    ArraySetAsSeries(rsiBuffer, true);
    ArraySetAsSeries(atrBuffer, true);

    redrawVWAPHistory();
    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    ObjectsDeleteAll(0, "PM_");
    ObjectsDeleteAll(0, "VWAP_Seg_");
    ChartIndicatorDelete(0, 0, "EMA(" + IntegerToString(EMAPeriod) + ")");
    Comment("");
}

void OnTick() {
    manageVWAPDrawing();
    checkNewDay();

    if (CopyBuffer(emaHandle, 0, 0, 10, emaBuffer) < 10) return;
    if (CopyBuffer(trendEmaHandle, 0, 0, 10, trendEmaBuffer) < 10) return;

    if (CopyBuffer(rsiHandle, 0, 0, 2, rsiBuffer) < 2) return;
    if (CopyBuffer(atrHandle, 0, 0, 2, atrBuffer) < 2) return;

    checkAccountProtection();
    managePreMarketAnalysis();
    checkStrategyLogic();
    managePositions();

    updateDashboard();
}

void updateDashboard() {
    string text = "=== Strategy Status v20.0 (Optimized) ===\n";
    text += "Box Height: " + DoubleToString(pmBoxHeight / _Point, 0) + " pts\n";

    double tpDist = pmBoxHeight * TakeProfitRatio;
    text += "Target TP: " + DoubleToString(tpDist / _Point, 0) + " pts (" +
            DoubleToString(TakeProfitRatio, 1) + "x Box)\n";

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

void checkAccountProtection() {
    if (PositionsTotal() == 0) return;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double floatingPL = equity - balance;
    double drawdownPercent = (MathAbs(floatingPL) / balance) * 100.0;

    if (floatingPL < 0 && drawdownPercent >= MaxDrawdownPercent) {
        Print("CRITICAL: Max Drawdown Reached. Closing ALL.");
        for (int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if (PositionSelectByTicket(ticket) &&
                PositionGetInteger(POSITION_MAGIC) == MagicNumber)
                trade.PositionClose(ticket);
        }
        debugMsg = "Emergency Liquidated!";
    }
}

void managePositions() {
    if (PositionsTotal() == 0) {
        currentAddCount = 0;
        hasAddedPosition = false;
    }

    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket) &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
            checkTakeProfit(ticket);
            if (UsePartialClose) checkPartialClose(ticket);
            checkBreakeven(ticket);
            checkTrailingStop(ticket);

            if (UseAddPosition) checkAddPosition(ticket);
            checkEmergencyExit(ticket);
        }
    }
}

void checkTakeProfit(ulong ticket) {
    if (TakeProfitRatio <= 0) return;

    long type = PositionGetInteger(POSITION_TYPE);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double curPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double profitPoints = 0;

    double tpDistance = pmBoxHeight * TakeProfitRatio;

    if (type == POSITION_TYPE_BUY)
        profitPoints = curPrice - openPrice;
    else
        profitPoints = openPrice - curPrice;

    if (profitPoints >= tpDistance) {
        trade.PositionClose(ticket);
        Print("Take Profit Reached (", DoubleToString(profitPoints / _Point, 0),
              " pts). Secure the bag!");
        debugMsg = "TP Hit! Profit Secured.";
    }
}

void checkAddPosition(ulong ticket) {
    if (currentAddCount >= MaxAddCount) return;

    long type = PositionGetInteger(POSITION_TYPE);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double vol = PositionGetDouble(POSITION_VOLUME);

    if (hasAddedPosition) return;

    bool doAdd = false;

    if (type == POSITION_TYPE_BUY) {
        if (currentPrice <= pmMidLine) doAdd = true;
    } else {
        if (currentPrice >= pmMidLine) doAdd = true;
    }

    if (doAdd) {
        double sl = (type == POSITION_TYPE_BUY) ? pmLow : pmHigh;
        if (type == POSITION_TYPE_BUY) {
            if (trade.Buy(vol * AddPositionMultiplier, _Symbol,
                          SymbolInfoDouble(_Symbol, SYMBOL_ASK), sl, 0,
                          "AddOn_Buy")) {
                currentAddCount++;
                hasAddedPosition = true;
                Print("Add Position Executed (", currentAddCount, "/",
                      MaxAddCount, ")");
            }
        } else {
            if (trade.Sell(vol * AddPositionMultiplier, _Symbol,
                           SymbolInfoDouble(_Symbol, SYMBOL_BID), sl, 0,
                           "AddOn_Sell")) {
                currentAddCount++;
                hasAddedPosition = true;
                Print("Add Position Executed (", currentAddCount, "/",
                      MaxAddCount, ")");
            }
        }
    }
}

void checkStrategyLogic() {
    if (pmHigh == 0) return;
    if (PositionsTotal() > 0) return;

    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double close = iClose(_Symbol, _Period, 0);

    // [수정됨] ATR 기반 SL/TP 계산
    double currentATR = atrBuffer[0];
    double slDistance = currentATR * ATR_SL_Ratio;  // ATR 기반 손절폭
    double tpDistance = currentATR * ATR_TP_Ratio;  // ATR 기반 익절폭

    // [추가됨] RSI 값 확인
    double currentRSI = rsiBuffer[0];

    bool isBullish = true;
    bool isBearish = true;

    if (UseTrendFilter) {
        double trendEma = trendEmaBuffer[0];
        isBullish = (close > trendEma);
        isBearish = (close < trendEma);
    }

    // 상태 머신 로직
    switch (buyState) {
        case STATE_WAITING:
            if (close > pmHigh) buyState = STATE_BREAKOUT;
            break;
        case STATE_BREAKOUT:
            if (bid <= lineRetestBuy) buyState = STATE_RETEST_DONE;
            break;
        case STATE_RETEST_DONE:
            // [조건 강화] Bid가 High 위에 있고, VWAP 위에 있으며,
            // ★ RSI가 50 이상이어야 함 (상승 모멘텀 확인)
            if (bid > pmHigh && bid > vwapValue &&
                currentRSI > RSI_BuyThreshold) {
                if (isBullish) {
                    double slPrice = pmHigh - slDistance;  // ATR SL 적용
                    double tpPrice = pmHigh + tpDistance;  // ATR TP 적용

                    trade.Buy(LotSize, _Symbol, ask, slPrice, tpPrice,
                              "Retest_Buy_RSI");
                    buyState = STATE_WAITING;
                    tradesTodayCount++;
                    drawLines();
                }
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
            // [조건 강화] Bid가 Low 아래 있고, VWAP 아래 있으며,
            // ★ RSI가 50 이하이어야 함 (하락 모멘텀 확인)
            if (bid < pmLow && bid < vwapValue &&
                currentRSI < RSI_SellThreshold) {
                if (isBearish) {
                    double slPrice = pmLow + slDistance;  // ATR SL 적용
                    double tpPrice = pmLow - tpDistance;  // ATR TP 적용

                    trade.Sell(LotSize, _Symbol, bid, slPrice, tpPrice,
                               "Retest_Sell_RSI");
                    sellState = STATE_WAITING;
                    tradesTodayCount++;
                    drawLines();
                }
            }
            break;
    }
}

void checkEmergencyExit(ulong ticket) {
    long type = PositionGetInteger(POSITION_TYPE);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    if (type == POSITION_TYPE_BUY) {
        if (currentPrice < pmLow) {
            trade.PositionClose(ticket);
            Print("Emergency Exit (Buy)");
        }
    } else {
        if (currentPrice > pmHigh) {
            trade.PositionClose(ticket);
            Print("Emergency Exit (Sell)");
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
    double breathingRoom = (stopsLevelPoints + 50) * _Point;

    if (type == POSITION_TYPE_BUY && currentSL >= openPrice) return;
    if (type == POSITION_TYPE_SELL && currentSL > 0 && currentSL <= openPrice)
        return;

    if (pointsProfit >= BE_TriggerPoints) {
        double newSL = 0;
        bool modify = false;
        if (type == POSITION_TYPE_BUY) {
            newSL = openPrice + (BE_LockPoints * _Point);
            if (curPrice > (newSL + breathingRoom))
                modify = true;
            else
                debugMsg = "BE Waiting for room...";
        } else {
            newSL = openPrice - (BE_LockPoints * _Point);
            if (curPrice < (newSL - breathingRoom))
                modify = true;
            else
                debugMsg = "BE Waiting for room...";
        }
        if (modify && trade.PositionModify(ticket, newSL, 0))
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
    double trailGap = pmBoxHeight * TrailingStepRatio;

    if (trigger == 0) return;
    double newSL = 0;
    bool shouldModify = false;

    if (type == POSITION_TYPE_BUY) {
        if (curPrice >= openPrice + trigger) {
            double targetSL = curPrice - trailGap;
            if (targetSL < openPrice) targetSL = openPrice;
            if (targetSL > currentSL &&
                targetSL < (curPrice - stopsLevelPrice)) {
                newSL = targetSL;
                shouldModify = true;
                debugMsg = "Buy TS Following";
            }
        }
    } else {
        if (curPrice <= openPrice - trigger) {
            double targetSL = curPrice + trailGap;
            if (targetSL > openPrice) targetSL = openPrice;
            if ((targetSL < currentSL || currentSL == 0) &&
                targetSL > (curPrice + stopsLevelPrice)) {
                newSL = targetSL;
                shouldModify = true;
                debugMsg = "Sell TS Following";
            }
        }
    }

    if (shouldModify) {
        if (trade.PositionModify(ticket, newSL, 0)) {
            if (type == POSITION_TYPE_BUY)
                ObjectSetDouble(0, "PM_AvgOpen", OBJPROP_PRICE, 0, newSL);
            else
                ObjectSetDouble(0, "PM_AvgClose", OBJPROP_PRICE, 0, newSL);
        }
    }
}

void manageVWAPDrawing() {
    datetime currentTime = iTime(_Symbol, _Period, 0);
    if (currentTime != lastBarTime) {
        lastBarTime = currentTime;
        redrawVWAPHistory();
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

void redrawVWAPHistory() {
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

void checkNewDay() {
    datetime dt = TimeCurrent();
    MqlDateTime st;
    TimeToStruct(dt, st);

    // [수정] 단순 day_of_year 비교는 연도 변경 시(12/31->1/1) 문제 발생 가능.
    // 날짜+연도 조합이나, 리셋 로직을 좀 더 확실하게 처리.
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
        tradesTodayCount = 0;
        currentAddCount = 0;
        hasAddedPosition = false;

        ObjectsDeleteAll(0, "PM_");
        ObjectsDeleteAll(0, "VWAP_Seg_");
        redrawVWAPHistory();
    }
}

// [개선] 반복문 제거 및 배열 사용으로 속도 최적화
void managePreMarketAnalysis() {
    MqlDateTime st;
    TimeToStruct(TimeCurrent(), st);
    string now = StringFormat("%02d:%02d", st.hour, st.min);

    if (now > PreMarketEndTime && pmHigh == 0) {
        calculatePreMarketStats();  // 함수 호출로 변경

        if (pmHigh > 0) {
            pmBoxHeight = pmHigh - pmLow;
            pmMidLine = (pmHigh + pmLow) / 2.0;
            double extension = pmBoxHeight * (ExtensionPercent / 100.0);

            lineRetestBuy = pmHigh - extension;
            lineRetestSell = pmLow + extension;

            double reEntryBuffer = pmBoxHeight * (ReEntryBufferPercent / 100.0);
            lineReEntryBuy = pmHigh + reEntryBuffer;
            lineReEntrySell = pmLow - reEntryBuffer;

            drawLines();
        }
    }
}

void drawLines() {
    datetime tStart = StringToTime(PreMarketStartTime);
    datetime tEnd = StringToTime(PreMarketEndTime);

    // 만약 tStart가 tEnd보다 크면(야간 시장 등), 날짜 보정 필요하지만 기본 로직
    // 유지
    datetime tCurrent = TimeCurrent();
    datetime tDayStart = tCurrent - (tCurrent % 86400);
    datetime tDayEnd = tDayStart + 86400;

    ObjectCreate(0, "PM_Box", OBJ_RECTANGLE, 0, tStart, pmHigh, tEnd, pmLow);
    ObjectSetInteger(0, "PM_Box", OBJPROP_COLOR, clrGray);
    ObjectSetInteger(0, "PM_Box", OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, "PM_Box", OBJPROP_FILL, false);

    createTrendLine("PM_Retest_Buy", tDayStart, lineRetestBuy, tDayEnd,
                    lineRetestBuy, clrRed, STYLE_SOLID);
    createTrendLine("PM_Retest_Sell", tDayStart, lineRetestSell, tDayEnd,
                    lineRetestSell, clrBlue, STYLE_SOLID);

    double addedBuffer =
        pmBoxHeight * (ReEntryBufferPercent / 100.0) * tradesTodayCount;
    double nextBuyLevel = pmHigh + addedBuffer;
    double nextSellLevel = pmLow - addedBuffer;

    createTrendLine("PM_NextEntry_Buy", tDayStart, nextBuyLevel, tDayEnd,
                    nextBuyLevel, clrLime, STYLE_DOT);
    createTrendLine("PM_NextEntry_Sell", tDayStart, nextSellLevel, tDayEnd,
                    nextSellLevel, clrLime, STYLE_DOT);
    createTrendLine("PM_MidLine", tDayStart, pmMidLine, tDayEnd, pmMidLine,
                    clrWhite, STYLE_DASH);
}

void createTrendLine(string name, datetime t1, double p1, datetime t2,
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

// [최적화] CopyBuffer/iBarShift 사용으로 반복문 대체
void calculatePreMarketStats() {
    datetime tCurrent = TimeCurrent();
    // 오늘 날짜의 00:00 구하기
    datetime dayStart = tCurrent - (tCurrent % 86400);

    // 시작 시간과 종료 시간을 datetime으로 변환
    datetime dtStart = StringToTime(PreMarketStartTime);
    datetime dtEnd = StringToTime(PreMarketEndTime);

    // 만약 현재 시간이 StartTime보다 작다면(즉, 어제 데이터를 봐야 하는 경우)
    // 등의 처리는 생략 기본적인 당일 PreMarket 기준

    int startBar = iBarShift(_Symbol, _Period, dtStart);
    int endBar = iBarShift(_Symbol, _Period, dtEnd);

    // 유효성 검사
    if (startBar == -1 || endBar == -1 || startBar < endBar) return;

    int count = startBar - endBar + 1;
    if (count <= 0) return;

    double highBuffer[];
    double lowBuffer[];

    // 배열 가져오기 (고가, 저가)
    if (CopyHigh(_Symbol, _Period, endBar, count, highBuffer) != count) return;
    if (CopyLow(_Symbol, _Period, endBar, count, lowBuffer) != count) return;

    // 배열에서 최대값/최소값 인덱스 찾기
    int maxIdx = ArrayMaximum(highBuffer);
    int minIdx = ArrayMinimum(lowBuffer);

    if (maxIdx != -1 && minIdx != -1) {
        pmHigh = highBuffer[maxIdx];
        pmLow = lowBuffer[minIdx];

        // 평균값 계산 (필요하다면 루프 사용하지만, Open/Close 평균은 중요도가
        // 낮아 생략 가능하거나 간단히 CopyOpen/CopyClose로 합산 가능. 여기선
        // High/Low가 핵심이므로 이것만 처리)
    }
}

void checkPartialClose(ulong ticket) {
    double vol = PositionGetDouble(POSITION_VOLUME);
    if (vol < LotSize * 0.9) return;

    int rubbing = 0;
    for (int j = 1; j <= 5; j++) {
        // [주의] emaBuffer는 OnTick에서 CopyBuffer로 업데이트됨.
        // 배열 인덱스 접근 시 범위 초과 주의 (여기서는 안전해 보임)
        double h = iHigh(_Symbol, _Period, j);
        double l = iLow(_Symbol, _Period, j);
        double ema = emaBuffer[j];

        if (l <= ema && h >= ema) rubbing++;
    }

    if (rubbing >= 5 && PositionGetDouble(POSITION_PROFIT) > 0)
        trade.PositionClosePartial(ticket, vol * 0.5);
}