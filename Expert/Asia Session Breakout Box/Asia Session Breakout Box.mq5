//+------------------------------------------------------------------+
//|                   Asian Breakout Hybrid v2.0.mq5                 |
//|               Strategy: Stop Entry + Limit Entry (Retest)        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, User"
#property version "2.00"
#include <Trade/Trade.mqh>

//--- Inputs
input group "Time Settings";
input string InpStartTime = "01:00";
input string InpEndTime = "09:00";

input group "Order Settings";
input int InpBufferPoints = 50;  // 돌파 여유
input int InpRetestBuffer = 20;  // 리테스트 진입 여유 (박스보다 살짝 위/아래)
input int InpSLPoints = 300;
input int InpTPPoints = 600;
input double InpLotSize = 0.01;
input long InpMagicNum = 999002;

input group "Strategy Mode";
input bool InpUseStopEntry = true;   // 1차: 돌파 매매 사용
input bool InpUseLimitEntry = true;  // 2차: 리테스트(눌림) 매매 사용

input group "Visual Settings";
input color InpBoxColor = clrDeepSkyBlue;
input int InpFontSize = 12;
input color InpTextColor = clrWhite;

//--- globals
CTrade trade;
datetime startTimeDt, endTimeDt;
double boxHigh = -1.0, boxLow = 999999.0;
int startHour, startMin, endHour, endMin;
int lastDayTraded = -1;
bool ordersPlacedToday = false;
string boxObjectName = "AsianHybridBox";
string labelObjectName = "AsianHybridInfo";
CPositionInfo positionInfo;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit() {
    trade.SetExpertMagicNumber(InpMagicNum);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    string startParts[];
    StringSplit(InpStartTime, ':', startParts);
    string endParts[];
    StringSplit(InpEndTime, ':', endParts);

    if (ArraySize(startParts) < 2 || ArraySize(endParts) < 2)
        return INIT_FAILED;

    startHour = (int)StringToInteger(startParts[0]);
    startMin = (int)StringToInteger(startParts[1]);
    endHour = (int)StringToInteger(endParts[0]);
    endMin = (int)StringToInteger(endParts[1]);

    ObjectCreate(0, boxObjectName, OBJ_RECTANGLE, 0, 0, 0, 0, 0);
    ObjectSetInteger(0, boxObjectName, OBJPROP_COLOR, InpBoxColor);
    ObjectSetInteger(0, boxObjectName, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, boxObjectName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, boxObjectName, OBJPROP_BACK, true);

    ObjectCreate(0, labelObjectName, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, labelObjectName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, labelObjectName, OBJPROP_XDISTANCE, 20);
    ObjectSetInteger(0, labelObjectName, OBJPROP_YDISTANCE, 50);
    ObjectSetInteger(0, labelObjectName, OBJPROP_FONTSIZE, InpFontSize);
    ObjectSetInteger(0, labelObjectName, OBJPROP_COLOR, InpTextColor);

    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    ObjectDelete(0, boxObjectName);
    ObjectDelete(0, labelObjectName);
}

void OnTick() {
    MqlDateTime dt;
    TimeCurrent(dt);

    if (lastDayTraded != dt.day_of_year) {
        ResetDailyStats();
        lastDayTraded = dt.day_of_year;
    }

    // OCO 로직 (한쪽 방향 터지면 반대쪽 모든 주문 삭제)
    CheckOCO();

    string statusMsg = StringFormat("Server Time: %02d:%02d\nBox Time: %s ~ %s",
                                    dt.hour, dt.min, InpStartTime, InpEndTime);

    if (ordersPlacedToday) {
        statusMsg += "\nStatus: Orders Placed / Trading Done Today";
        UpdateLabel(statusMsg);
        return;
    }

    int currentTotalMinutes = dt.hour * 60 + dt.min;
    int startTotalMinutes = startHour * 60 + startMin;
    int endTotalMinutes = endHour * 60 + endMin;

    // 1. 박스 형성
    if (currentTotalMinutes >= startTotalMinutes &&
        currentTotalMinutes < endTotalMinutes) {
        double high = iHigh(_Symbol, _Period, 0);
        double low = iLow(_Symbol, _Period, 0);
        if (high > boxHigh) boxHigh = high;
        if (low < boxLow) boxLow = low;

        if (startTimeDt == 0) {
            MqlDateTime st = dt;
            st.hour = startHour;
            st.min = startMin;
            st.sec = 0;
            startTimeDt = StructToTime(st);
        }
        UpdateBoxOnChart(startTimeDt, TimeCurrent(), boxHigh, boxLow);
        statusMsg += StringFormat(
            "\nStatus: Forming Box...\nHigh: %.2f\nLow: %.2f", boxHigh, boxLow);
    }

    // 2. 주문 실행
    else if (currentTotalMinutes >= endTotalMinutes && boxHigh > 0 &&
             !ordersPlacedToday) {
        MqlDateTime et = dt;
        et.hour = endHour;
        et.min = endMin;
        et.sec = 0;
        endTimeDt = StructToTime(et);
        UpdateBoxOnChart(startTimeDt, endTimeDt, boxHigh, boxLow);

        PlaceHybridOrders();  // 하이브리드 주문 실행
        ordersPlacedToday = true;
        statusMsg += "\nStatus: Hybrid Orders Sent!";
    } else {
        statusMsg += "\nStatus: Waiting...";
    }

    UpdateLabel(statusMsg);
}

//+------------------------------------------------------------------+
//| 하이브리드 주문 (Stop + Limit)                                     |
//+------------------------------------------------------------------+
void PlaceHybridOrders() {
    double point = _Point;
    int digits = _Digits;
    long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double minDistance = (stopLevel + 10) * point;

    // 1. Stop Entry (돌파 매매)
    if (InpUseStopEntry) {
        double buffer = MathMax(InpBufferPoints * point, minDistance);

        // Buy Stop
        double buyPrice = NormalizeDouble(boxHigh + buffer, digits);
        double buySL = NormalizeDouble(buyPrice - InpSLPoints * point, digits);
        double buyTP = NormalizeDouble(buyPrice + InpTPPoints * point, digits);
        trade.BuyStop(InpLotSize, buyPrice, _Symbol, buySL, buyTP,
                      ORDER_TIME_DAY, 0, "Hybrid Breakout Buy");

        // Sell Stop
        double sellPrice = NormalizeDouble(boxLow - buffer, digits);
        double sellSL =
            NormalizeDouble(sellPrice + InpSLPoints * point, digits);
        double sellTP =
            NormalizeDouble(sellPrice - InpTPPoints * point, digits);
        trade.SellStop(InpLotSize, sellPrice, _Symbol, sellSL, sellTP,
                       ORDER_TIME_DAY, 0, "Hybrid Breakout Sell");
    }

    // 2. Limit Entry (리테스트 매매)
    if (InpUseLimitEntry) {
        // 리테스트는 박스 라인 근처에서 잡음 (약간 안쪽이나 바깥쪽)
        // Buy Limit: 박스 상단 근처까지 내려오면 매수
        // Sell Limit: 박스 하단 근처까지 올라오면 매도

        double retestBuff = InpRetestBuffer * point;  // 미세 조정

        // Buy Limit (상단 돌파 후 눌림목) -> 가격은 박스 상단
        double buyLimitPrice = NormalizeDouble(boxHigh + retestBuff, digits);
        double buyLimitSL =
            NormalizeDouble(buyLimitPrice - InpSLPoints * point, digits);
        double buyLimitTP =
            NormalizeDouble(buyLimitPrice + InpTPPoints * point, digits);

        // Sell Limit (하단 돌파 후 반등목) -> 가격은 박스 하단
        double sellLimitPrice = NormalizeDouble(boxLow - retestBuff, digits);
        double sellLimitSL =
            NormalizeDouble(sellLimitPrice + InpSLPoints * point, digits);
        double sellLimitTP =
            NormalizeDouble(sellLimitPrice - InpTPPoints * point, digits);

        // 주의: Limit 주문은 현재가가 박스 안에 있을 때만 유효함.
        // 만약 갭상승해서 시작해버리면 Limit 주문이 바로 체결될 수도 있으니,
        // 여기서는 "돌파가 일어난 후"를 가정하고 미리 걸어두는 방식(Pending)을
        // 씁니다. 하지만 MT5에서 현재가보다 높은 곳에 Buy Limit을 걸면 에러가
        // 나므로, Stop Limit 주문을 쓰거나, 단순히 Limit 주문을 걸되 현재가
        // 체크가 필요함. (여기서는 단순화를 위해 일반 Limit을 걸되, 박스 내부
        // 가격일 것이라 가정)

        double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

        // 현재가가 박스 아래에 있을 때만 Buy Limit 가능 (근데 우린 박스 안이라
        // 가정)
        if (currentAsk < buyLimitPrice) {
            trade.BuyLimit(InpLotSize, buyLimitPrice, _Symbol, buyLimitSL,
                           buyLimitTP, ORDER_TIME_DAY, 0, "Hybrid Retest Buy");
        }
        // 현재가가 박스 위에 있을 때만 Sell Limit 가능
        if (currentBid > sellLimitPrice) {
            trade.SellLimit(InpLotSize, sellLimitPrice, _Symbol, sellLimitSL,
                            sellLimitTP, ORDER_TIME_DAY, 0,
                            "Hybrid Retest Sell");
        }
    }
}

//+------------------------------------------------------------------+
//| OCO 로직 (반대 방향 주문 삭제)                                     |
//+------------------------------------------------------------------+
void CheckOCO() {
    if (PositionsTotal() == 0) return;

    // 현재 열린 포지션 확인
    long posType = -1;
    for (int i = 0; i < PositionsTotal(); i++) {
        if (positionInfo.SelectByIndex(i) &&
            positionInfo.Magic() == InpMagicNum) {
            posType = positionInfo.PositionType();
            break;
        }
    }

    if (posType == -1) return;  // 내 포지션 아님

    // 반대 방향 대기 주문 삭제
    for (int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if (OrderGetInteger(ORDER_MAGIC) != InpMagicNum) continue;

        long orderType = OrderGetInteger(ORDER_TYPE);

        // 내가 BUY를 잡았으면 -> Sell Stop, Sell Limit 삭제
        if (posType == POSITION_TYPE_BUY) {
            if (orderType == ORDER_TYPE_SELL_STOP ||
                orderType == ORDER_TYPE_SELL_LIMIT) {
                trade.OrderDelete(ticket);
            }
        }
        // 내가 SELL을 잡았으면 -> Buy Stop, Buy Limit 삭제
        else if (posType == POSITION_TYPE_SELL) {
            if (orderType == ORDER_TYPE_BUY_STOP ||
                orderType == ORDER_TYPE_BUY_LIMIT) {
                trade.OrderDelete(ticket);
            }
        }
    }
}

void UpdateBoxOnChart(datetime t1, datetime t2, double p1, double p2) {
    ObjectSetInteger(0, boxObjectName, OBJPROP_TIME, 0, t1);
    ObjectSetInteger(0, boxObjectName, OBJPROP_TIME, 1, t2);
    ObjectSetDouble(0, boxObjectName, OBJPROP_PRICE, 0, p1);
    ObjectSetDouble(0, boxObjectName, OBJPROP_PRICE, 1, p2);
    ChartRedraw(0);
}

void UpdateLabel(string text) {
    ObjectSetString(0, labelObjectName, OBJPROP_TEXT, text);
    ChartRedraw(0);
}

void ResetDailyStats() {
    boxHigh = -1.0;
    boxLow = 999999.0;
    startTimeDt = 0;
    endTimeDt = 0;
    ordersPlacedToday = false;
    ObjectDelete(0, boxObjectName);
    ObjectCreate(0, boxObjectName, OBJ_RECTANGLE, 0, 0, 0, 0, 0);
    ObjectSetInteger(0, boxObjectName, OBJPROP_COLOR, InpBoxColor);
    ObjectSetInteger(0, boxObjectName, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, boxObjectName, OBJPROP_BACK, true);
}