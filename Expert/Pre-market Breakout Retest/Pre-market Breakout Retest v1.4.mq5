//+------------------------------------------------------------------+
//|                        PreMarket_Ultimate_Combo_v20.0.mq5        |
//|                        Feature: Take Profit (Target Exit)        |
//+------------------------------------------------------------------+
#property copyright "Gemini AI"
#property link "https://www.mql5.com"
#property version "20.00"
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
input double TakeProfitRatio =
    2.0;  // [신규] 박스 크기의 2배 수익 시 전량 익절 (0=사용안함)

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
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(Slippage);

    emaHandle = iMA(_Symbol, _Period, EMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
    trendEmaHandle =
        iMA(_Symbol, PERIOD_H1, TrendFilterPeriod, 0, MODE_EMA, PRICE_CLOSE);

    if (emaHandle == INVALID_HANDLE || trendEmaHandle == INVALID_HANDLE)
        return (INIT_FAILED);

    ChartIndicatorAdd(0, 0, emaHandle);
    ArraySetAsSeries(emaBuffer, true);
    ArraySetAsSeries(trendEmaBuffer, true);

    RedrawVWAPHistory();
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

    checkAccountProtection();
    managePreMarketAnalysis();
    checkStrategyLogic();
    managePositions();

    UpdateDashboard();
}

void UpdateDashboard() {
    string text = "=== Strategy Status v20.0 (Take Profit Added) ===\n";
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
            // 1. 목표 수익(TP) 체크 [신규]
            checkTakeProfit(ticket);

            if (UsePartialClose) checkPartialClose(ticket);
            checkBreakeven(ticket);
            checkTrailingStop(ticket);

            if (UseAddPosition) checkAddPosition(ticket);
            checkEmergencyExit(ticket);
        }
    }
}

// [신규] 목표 수익 달성 시 전량 익절 (Take Profit)
void checkTakeProfit(ulong ticket) {
    if (TakeProfitRatio <= 0) return;  // 0이면 사용 안 함

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

// [수정] 물타기 로직: 횟수 제한 및 단순화
void checkAddPosition(ulong ticket) {
    if (currentAddCount >= MaxAddCount) return;

    long type = PositionGetInteger(POSITION_TYPE);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double vol = PositionGetDouble(POSITION_VOLUME);

    // 중복 진입 방지:
    // 현재가가 MidLine 근처에 있고, 아직 추가 진입 안했으면 실행.
    // v19.1 로직 유지하되 플래그 체크 확실히.
    if (hasAddedPosition) return;

    bool doAdd = false;

    if (type == POSITION_TYPE_BUY) {
        // 매수인데 박스 중간선 이하로 내려옴
        if (currentPrice <= pmMidLine) doAdd = true;
    } else {
        // 매도인데 박스 중간선 이상으로 올라옴
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
    double fixedSL_Dist = pmBoxHeight * 0.5;

    bool isBullish = true;
    bool isBearish = true;

    if (UseTrendFilter) {
        double trendEma = trendEmaBuffer[0];
        isBullish = (close > trendEma);
        isBearish = (close < trendEma);
    }

    switch (buyState) {
        case STATE_WAITING:
            // 첫 진입 기준 (재진입 버퍼 로직 포함하려면 여기서 분기)
            // 단순화를 위해 기본 로직 사용
            if (close > pmHigh) buyState = STATE_BREAKOUT;
            break;
        case STATE_BREAKOUT:
            if (bid <= lineRetestBuy) buyState = STATE_RETEST_DONE;
            break;
        case STATE_RETEST_DONE:
            if (bid > pmHigh && bid > vwapValue) {
                if (isBullish) {
                    trade.Buy(LotSize, _Symbol, ask, pmHigh - fixedSL_Dist, 0,
                              "Retest_Buy");
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
            if (bid < pmLow && bid < vwapValue) {
                if (isBearish) {
                    trade.Sell(LotSize, _Symbol, bid, pmLow + fixedSL_Dist, 0,
                               "Retest_Sell");
                    sellState = STATE_WAITING;
                    tradesTodayCount++;
                    drawLines();
                }
            }
            break;
    }
}

// ... (나머지 동일) ...
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
        tradesTodayCount = 0;
        currentAddCount = 0;
        hasAddedPosition = false;
        ObjectsDeleteAll(0, "PM_");
        ObjectsDeleteAll(0, "VWAP_Seg_");
        RedrawVWAPHistory();
    }
}
void managePreMarketAnalysis() {
    MqlDateTime st;
    TimeToStruct(TimeCurrent(), st);
    string now = StringFormat("%02d:%02d", st.hour, st.min);
    if (now > PreMarketEndTime && pmHigh == 0) {
        calculatePreMarketStats();
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
    datetime tCurrent = TimeCurrent();
    datetime tDayStart = tCurrent - (tCurrent % 86400);
    datetime tDayEnd = tDayStart + 86400;
    ObjectCreate(0, "PM_Box", OBJ_RECTANGLE, 0, tStart, pmHigh, tEnd, pmLow);
    ObjectSetInteger(0, "PM_Box", OBJPROP_COLOR, clrGray);
    ObjectSetInteger(0, "PM_Box", OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, "PM_Box", OBJPROP_FILL, false);
    CreateTrendLine("PM_Retest_Buy", tDayStart, lineRetestBuy, tDayEnd,
                    lineRetestBuy, clrRed, STYLE_SOLID);
    CreateTrendLine("PM_Retest_Sell", tDayStart, lineRetestSell, tDayEnd,
                    lineRetestSell, clrBlue, STYLE_SOLID);
    double addedBuffer =
        pmBoxHeight * (ReEntryBufferPercent / 100.0) * tradesTodayCount;
    double nextBuyLevel = pmHigh + addedBuffer;
    double nextSellLevel = pmLow - addedBuffer;
    CreateTrendLine("PM_NextEntry_Buy", tDayStart, nextBuyLevel, tDayEnd,
                    nextBuyLevel, clrLime, STYLE_DOT);
    CreateTrendLine("PM_NextEntry_Sell", tDayStart, nextSellLevel, tDayEnd,
                    nextSellLevel, clrLime, STYLE_DOT);
    CreateTrendLine("PM_MidLine", tDayStart, pmMidLine, tDayEnd, pmMidLine,
                    clrWhite, STYLE_DASH);
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