//+------------------------------------------------------------------+
//|                                     EMACrossRealtime.mq5         |
//|                                  Copyright 2025, p3pwp3p         |
//+------------------------------------------------------------------+
#property copyright "p3pwp3p"
#property link ""
#property version "1.00"

//--- Standard Library for Trading
#include <Trade/Trade.mqh>

//--- Input Parameters (PascalCase)
input double LotSize = 0.1;      // Trading Lot Size
input int FastPeriod = 30;       // Fast EMA Period
input int SlowPeriod = 60;       // Slow EMA Period
input int MagicNumber = 123456;  // Expert ID
input int Slippage = 3;          // Max Slippage Points

//--- Global Variables (camelCase)
CTrade trade;  // Trading Object
int fastHandle;
int slowHandle;
double fastBuffer[];
double slowBuffer[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // 전략 테스터 전용 (필요 없다면 이 부분 삭제 가능)
    if (!MQLInfoInteger(MQL_TESTER)) {
        Alert("Error: This EA is designed to run ONLY in the Strategy Tester.");
        Print("Error: This EA is designed to run ONLY in the Strategy Tester.");
        return (INIT_FAILED);
    }

    //--- Initialize Handles
    fastHandle = iMA(_Symbol, _Period, FastPeriod, 0, MODE_EMA, PRICE_CLOSE);
    slowHandle = iMA(_Symbol, _Period, SlowPeriod, 0, MODE_EMA, PRICE_CLOSE);

    if (fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE) {
        Print("Error creating MA handles.");
        return (INIT_FAILED);
    }

    //--- Set Magic Number for Trade Management
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(Slippage);

    //--- Set Array as Series (Index 0 is the newest)
    ArraySetAsSeries(fastBuffer, true);
    ArraySetAsSeries(slowBuffer, true);

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    //--- Release Handles
    IndicatorRelease(fastHandle);
    IndicatorRelease(slowHandle);
}

//+------------------------------------------------------------------+
//| Helper Function: Close All Positions of Specific Type            |
//+------------------------------------------------------------------+
void closePositions(ENUM_POSITION_TYPE typeToClose) {
    int total = PositionsTotal();

    // Loop backwards to close safely
    for (int i = total - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0) {
            // Check if it belongs to this EA and matches the type
            if (PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
                PositionGetInteger(POSITION_TYPE) == typeToClose) {
                trade.PositionClose(ticket);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Helper Function: Check if Position Exists                        |
//+------------------------------------------------------------------+
bool hasPosition(ENUM_POSITION_TYPE typeToCheck) {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0) {
            if (PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
                PositionGetInteger(POSITION_TYPE) == typeToCheck) {
                return (true);
            }
        }
    }
    return (false);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    //--- 1. Prepare Data
    // [수정됨] Index 0(현재가 반영)과 Index 1(직전 확정봉)을 가져옵니다.
    // Index 0의 EMA는 현재 가격(Current Price)에 따라 틱마다 변합니다.

    if (CopyBuffer(fastHandle, 0, 0, 2, fastBuffer) < 2) return;
    if (CopyBuffer(slowHandle, 0, 0, 2, slowBuffer) < 2) return;

    double fastCurr =
        fastBuffer[0];  // [중요] 현재 움직이는 EMA (Current Price 반영)
    double fastPrev = fastBuffer[1];  // 직전 캔들 EMA

    double slowCurr = slowBuffer[0];  // [중요] 현재 움직이는 EMA
    double slowPrev = slowBuffer[1];  // 직전 캔들 EMA

    //--- 2. Detect Real-time Crossover
    // 이전 캔들에서는 역배열이었는데(Prev < Prev),
    // 현재 순간 정배열이 되었다면(Curr >= Curr) -> 골든크로스 즉시 진입

    bool isGoldenCross = (fastPrev < slowPrev) && (fastCurr >= slowCurr);
    bool isDeadCross = (fastPrev > slowPrev) && (fastCurr <= slowCurr);

    //--- 3. Execute Strategy

    // [Scenario A] Golden Cross -> Close Sell, Open Buy
    if (isGoldenCross) {
        // 매도 포지션이 있다면 즉시 청산
        if (hasPosition(POSITION_TYPE_SELL)) {
            closePositions(POSITION_TYPE_SELL);
        }

        // 매수 포지션이 없다면 즉시 진입
        if (!hasPosition(POSITION_TYPE_BUY)) {
            trade.Buy(LotSize, _Symbol, 0, 0, 0, "Realtime EMA Golden Cross");
        }
    }

    // [Scenario B] Dead Cross -> Close Buy, Open Sell
    if (isDeadCross) {
        // 매수 포지션이 있다면 즉시 청산
        if (hasPosition(POSITION_TYPE_BUY)) {
            closePositions(POSITION_TYPE_BUY);
        }

        // 매도 포지션이 없다면 즉시 진입
        if (!hasPosition(POSITION_TYPE_SELL)) {
            trade.Sell(LotSize, _Symbol, 0, 0, 0, "Realtime EMA Dead Cross");
        }
    }
}
//+------------------------------------------------------------------+