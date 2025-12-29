//+------------------------------------------------------------------+
//|                                              Gold Open Price.mq5 |
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

input group "Trailing Stop Settings";
input int InputTslTrigger = 250;
input int InputTslDistance = 50;
input int InputTslStep = 50;

CTrade trade;
datetime lastEntryDate = 0;

int OnInit() {
    trade.SetExpertMagicNumber(InputMagicNumber);
    return (INIT_SUCCEEDED);
}

void OnTick() {
    applyTrailingStop();
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
    double buySl = NormalizeDouble(buyStopPrice - slDist, _Digits);
    double sellSl = NormalizeDouble(sellStopPrice + slDist, _Digits);

    // --- [수정 1] 이미 주문이 있는지 확인하는 로직 추가 ---
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
    // ----------------------------------------------------

    bool buyResult = false;
    bool sellResult = false;

    // --- [수정 2] 없을 때만 주문 실행 ---
    if (!buyExists) {
        if (trade.BuyStop(InputLotSize, buyStopPrice, _Symbol, buySl, 0.0,
                          ORDER_TIME_DAY, 0, "Buy Stop Breakout"))
            buyResult = true;
        else
            Print("Buy Stop Error: ", trade.ResultRetcodeDescription());
    } else {
        buyResult = true;  // 이미 있으면 성공으로 간주
    }

    if (!sellExists) {
        if (trade.SellStop(InputLotSize, sellStopPrice, _Symbol, sellSl, 0.0,
                           ORDER_TIME_DAY, 0, "Sell Stop Breakout"))
            sellResult = true;
        else
            Print("Sell Stop Error: ", trade.ResultRetcodeDescription());
    } else {
        sellResult = true;  // 이미 있으면 성공으로 간주
    }

    // --- [수정 3] 둘 다 처리 시도가 끝났으면 true 반환하여 루프 종료 ---
    // 실패했더라도 true를 반환해야 다음 틱에 무한 반복하지 않음.
    // (실패 원인은 저널 로그에서 확인 후 수정하는 것이 원칙)
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

void applyTrailingStop() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0) {
            if (PositionGetInteger(POSITION_MAGIC) == InputMagicNumber &&
                PositionGetString(POSITION_SYMBOL) == _Symbol) {
                double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double currentSl = PositionGetDouble(POSITION_SL);
                long type = PositionGetInteger(POSITION_TYPE);
                double point = _Point;

                if (type == POSITION_TYPE_BUY) {
                    double profitPoints = (currentPrice - openPrice) / point;
                    if (profitPoints > InputTslTrigger) {
                        double newSl =
                            currentPrice - (InputTslDistance * point);
                        if (newSl > currentSl + (InputTslStep * point) ||
                            currentSl == 0.0) {
                            trade.PositionModify(
                                ticket, NormalizeDouble(newSl, _Digits), 0.0);
                        }
                    }
                } else if (type == POSITION_TYPE_SELL) {
                    double profitPoints = (openPrice - currentPrice) / point;
                    if (profitPoints > InputTslTrigger) {
                        double newSl =
                            currentPrice + (InputTslDistance * point);
                        if (newSl < currentSl - (InputTslStep * point) ||
                            currentSl == 0.0) {
                            trade.PositionModify(
                                ticket, NormalizeDouble(newSl, _Digits), 0.0);
                        }
                    }
                }
            }
        }
    }
}