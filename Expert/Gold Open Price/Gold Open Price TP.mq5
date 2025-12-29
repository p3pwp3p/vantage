//+------------------------------------------------------------------+
//|                                     Gold Open Price Fixed TP.mq5 |
//|                                  Copyright 2025, p3pwp3p         |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, p3pwp3p"
#property link "https://www.mql5.com"
#property version "1.00"
#property strict

#include <Trade\Trade.mqh>

input group "Base Settings";
input double InputLotSize = 0.01;
input int InputMagicNumber = 20250101;

input group "Time Settings";
input int InputStartHour = 1;
input int InputStartMinute = 0;
input int InputDeleteHour = 23;

input group "Strategy Settings";
input double InputRatio = 0.25;
input int InputStopLoss = 400;
input int InputTakeProfit = 200;

CTrade trade;
datetime lastEntryDate = 0;

int OnInit() {
    trade.SetExpertMagicNumber(InputMagicNumber);
    return (INIT_SUCCEEDED);
}

void OnTick() {
    checkAndDeletePendingOrders();

    datetime currentTime = TimeCurrent();

    MqlDateTime dtStruct;
    TimeToStruct(currentTime, dtStruct);
    dtStruct.hour = 0;
    dtStruct.min = 0;
    dtStruct.sec = 0;
    datetime todayMidnight = StructToTime(dtStruct);

    datetime targetTime =
        todayMidnight + (InputStartHour * 3600) + (InputStartMinute * 60);

    if (currentTime >= targetTime && lastEntryDate != todayMidnight) {
        if (!isMarketOpen()) return;

        double referencePrice = getPriceAtTime(targetTime);

        if (referencePrice > 0.0) {
            if (placeDailyOrders(referencePrice)) {
                lastEntryDate = todayMidnight;
            }
        }
    }
}

bool isMarketOpen() {
    if (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) ==
        SYMBOL_TRADE_MODE_DISABLED)
        return false;

    datetime currentTime = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(currentTime, dt);

    datetime sessionStart, sessionEnd;

    if (!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dt.day_of_week, 0,
                                sessionStart, sessionEnd)) {
        return false;
    }

    long currentSeconds = dt.hour * 3600 + dt.min * 60 + dt.sec;

    MqlDateTime dtStart;
    TimeToStruct(sessionStart, dtStart);
    long startSeconds = dtStart.hour * 3600 + dtStart.min * 60 + dtStart.sec;

    MqlDateTime dtEnd;
    TimeToStruct(sessionEnd, dtEnd);
    long endSeconds = dtEnd.hour * 3600 + dtEnd.min * 60 + dtEnd.sec;

    if (currentSeconds >= startSeconds && currentSeconds < endSeconds) {
        return true;
    }

    return false;
}

double getPriceAtTime(datetime targetTime) {
    MqlRates rates[];
    int copied = CopyRates(_Symbol, PERIOD_M1, targetTime, 1, rates);

    if (copied > 0) {
        if (MathAbs(rates[0].time - targetTime) < 3600) {
            return rates[0].open;
        }
    }
    return 0.0;
}

bool placeDailyOrders(double refPrice) {
    int calculatedPoints = (int)(refPrice * InputRatio);
    double priceDistance = calculatedPoints * _Point;

    double buyStopPrice = NormalizeDouble(refPrice + priceDistance, _Digits);
    double sellStopPrice = NormalizeDouble(refPrice - priceDistance, _Digits);

    double slDist = InputStopLoss * _Point;
    double tpDist = InputTakeProfit * _Point;

    double buySl = NormalizeDouble(buyStopPrice - slDist, _Digits);
    double buyTp = NormalizeDouble(buyStopPrice + tpDist, _Digits);

    double sellSl = NormalizeDouble(sellStopPrice + slDist, _Digits);
    double sellTp = NormalizeDouble(sellStopPrice - tpDist, _Digits);

    bool buyExists = false;
    bool sellExists = false;

    for (int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if (ticket > 0) {
            if (OrderGetInteger(ORDER_MAGIC) == InputMagicNumber &&
                OrderGetString(ORDER_SYMBOL) == _Symbol) {
                if (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP)
                    buyExists = true;
                if (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP)
                    sellExists = true;
            }
        }
    }

    bool buyResult = false;
    bool sellResult = false;

    if (!buyExists) {
        if (trade.BuyStop(InputLotSize, buyStopPrice, _Symbol, buySl, buyTp,
                          ORDER_TIME_DAY, 0, "Buy Stop Breakout"))
            buyResult = true;
    } else {
        buyResult = true;
    }

    if (!sellExists) {
        if (trade.SellStop(InputLotSize, sellStopPrice, _Symbol, sellSl, sellTp,
                           ORDER_TIME_DAY, 0, "Sell Stop Breakout"))
            sellResult = true;
    } else {
        sellResult = true;
    }

    return true;
}

void checkAndDeletePendingOrders() {
    MqlDateTime dt;
    TimeCurrent(dt);

    if (dt.hour == InputDeleteHour && dt.min == 0 && dt.sec < 10) {
        for (int i = OrdersTotal() - 1; i >= 0; i--) {
            ulong ticket = OrderGetTicket(i);
            if (ticket > 0) {
                if (OrderGetInteger(ORDER_MAGIC) == InputMagicNumber &&
                    OrderGetString(ORDER_SYMBOL) == _Symbol) {
                    ENUM_ORDER_TYPE type =
                        (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
                    if (type == ORDER_TYPE_BUY_STOP ||
                        type == ORDER_TYPE_SELL_STOP) {
                        trade.OrderDelete(ticket);
                    }
                }
            }
        }
    }
}