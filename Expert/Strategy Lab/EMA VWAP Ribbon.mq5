//+------------------------------------------------------------------+
//|                                          EMA VWAP Ribbon.mq5     |
//|                                     Copyright 2025, p3pwp3p      |
//+------------------------------------------------------------------+
#property copyright "p3pwp3p"
#property link "https://www.mql5.com"
#property version "1.00"
#property strict

#include <Trade\Trade.mqh>

// --- Inputs (PascalCase) ---
input group "Trade Settings";
input double InputLotSize = 0.1;      // 거래 랏 사이즈
input int InputMagicNumber = 888888;  // 매직 넘버
input int InputSlippage = 10;         // 허용 슬리피지

input group "Filter Settings";
input int InputStartHour = 1;  // 시작 시간 (1 = 01:00부터 거래)
input int InputCrossGap = 30;  // ★ 크로스 갭 (포인트 단위, 예: 30 = 3 pips)

input group "EMA Settings";
input int InputEmaPeriod = 8;  // EMA 기간

input group "Ribbon Settings";
input int InputRibbonFast = 20;  // Ribbon Fast MA
input int InputRibbonSlow = 50;  // Ribbon Slow MA
input int InputRibbonSens = 3;   // Ribbon Sensitivity

// --- Global Variables (camelCase) ---
CTrade trade;
int vwapHandle;
int ribbonHandle;
int emaHandle;
double vwapBuffer[];
double ribbonColorBuffer[];
double emaBuffer[];
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // CTrade 설정
    trade.SetExpertMagicNumber(InputMagicNumber);
    trade.SetDeviationInPoints(InputSlippage);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    trade.SetAsyncMode(false);

    lastBarTime = 0;

    // 1. EMA 핸들
    emaHandle = iMA(_Symbol, _Period, InputEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
    if (emaHandle == INVALID_HANDLE) return (INIT_FAILED);

    // 2. VWAP 핸들
    vwapHandle = iCustom(_Symbol, _Period, "p3pwp3p\\p3pwp3p VWAP", clrMagenta);
    if (vwapHandle == INVALID_HANDLE) {
        vwapHandle = iCustom(_Symbol, _Period, "p3pwp3p VWAP", clrMagenta);
        if (vwapHandle == INVALID_HANDLE) return (INIT_FAILED);
    }

    // 3. Trend Ribbon 핸들
    ribbonHandle = iCustom(_Symbol, _Period, "p3pwp3p\\Trend Ribbon Pro");
    if (ribbonHandle == INVALID_HANDLE) {
        ribbonHandle = iCustom(_Symbol, _Period, "Trend Ribbon Pro");
        if (ribbonHandle == INVALID_HANDLE) return (INIT_FAILED);
    }

    ArraySetAsSeries(emaBuffer, true);
    ArraySetAsSeries(vwapBuffer, true);
    ArraySetAsSeries(ribbonColorBuffer, true);

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    if (emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
    if (vwapHandle != INVALID_HANDLE) IndicatorRelease(vwapHandle);
    if (ribbonHandle != INVALID_HANDLE) IndicatorRelease(ribbonHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    if (!updateBuffers()) return;

    // 1. 색상 청산
    checkExitSignal();

    // 2. 갭 필터가 적용된 진입 로직
    checkEntrySignal();
}

// --- 사용자 정의 함수 ---

bool updateBuffers() {
    if (CopyBuffer(emaHandle, 0, 0, 3, emaBuffer) < 3) return false;
    if (CopyBuffer(vwapHandle, 0, 0, 3, vwapBuffer) < 3) return false;
    if (CopyBuffer(ribbonHandle, 2, 0, 3, ribbonColorBuffer) < 3) return false;
    return true;
}

bool hasPosition(ENUM_POSITION_TYPE type) {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (PositionGetSymbol(i) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InputMagicNumber) {
            if (PositionGetInteger(POSITION_TYPE) == type) return true;
        }
    }
    return false;
}

void closeOppositePositions(ENUM_POSITION_TYPE newEntryType) {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (PositionGetInteger(POSITION_MAGIC) == InputMagicNumber) {
            long currentType = PositionGetInteger(POSITION_TYPE);
            if (newEntryType == POSITION_TYPE_BUY &&
                currentType == POSITION_TYPE_SELL) {
                trade.PositionClose(ticket);
            } else if (newEntryType == POSITION_TYPE_SELL &&
                       currentType == POSITION_TYPE_BUY) {
                trade.PositionClose(ticket);
            }
        }
    }
}

void checkEntrySignal() {
    datetime currentBarTime = iTime(_Symbol, _Period, 0);

    // 시간 필터
    MqlDateTime dt;
    TimeToStruct(currentBarTime, dt);
    if (dt.hour < InputStartHour) return;

    // 중복 진입 방지
    if (lastBarTime == currentBarTime) return;

    double ema1 = emaBuffer[1];
    double ema0 = emaBuffer[0];
    double vwap1 = vwapBuffer[1];
    double vwap0 = vwapBuffer[0];

    if (ema1 == 0 || ema0 == 0 || vwap1 == 0 || vwap0 == 0 ||
        vwap1 == EMPTY_VALUE || vwap0 == EMPTY_VALUE)
        return;

    // 갭(Gap) 계산
    double gapValue = InputCrossGap * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

    // ★ 갭 필터 적용 진입 조건
    // 매수: EMA가 (VWAP + Gap) 라인을 아래에서 위로 뚫을 때
    // 매도: EMA가 (VWAP - Gap) 라인을 위에서 아래로 뚫을 때
    bool isGoldenCrossWithGap =
        (ema1 < vwap1 + gapValue) && (ema0 > vwap1 + gapValue);
    bool isDeadCrossWithGap =
        (ema1 > vwap1 - gapValue) && (ema0 < vwap1 - gapValue);

    if (isGoldenCrossWithGap) {
        closeOppositePositions(POSITION_TYPE_BUY);

        if (!hasPosition(POSITION_TYPE_BUY)) {
            if (trade.Buy(InputLotSize, _Symbol)) {
                Print("Buy Order (Gap Filtered).");
                lastBarTime = currentBarTime;
            }
        }
    } else if (isDeadCrossWithGap) {
        closeOppositePositions(POSITION_TYPE_SELL);

        if (!hasPosition(POSITION_TYPE_SELL)) {
            if (trade.Sell(InputLotSize, _Symbol)) {
                Print("Sell Order (Gap Filtered).");
                lastBarTime = currentBarTime;
            }
        }
    }
}

void checkExitSignal() {
    double currentColor = ribbonColorBuffer[0];
    if (currentColor == EMPTY_VALUE) return;

    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (PositionGetInteger(POSITION_MAGIC) == InputMagicNumber) {
            long type = PositionGetInteger(POSITION_TYPE);
            bool closeIt = false;

            if (type == POSITION_TYPE_BUY && currentColor == 1.0)
                closeIt = true;
            else if (type == POSITION_TYPE_SELL && currentColor == 0.0)
                closeIt = true;

            if (closeIt) {
                trade.PositionClose(ticket);
            }
        }
    }
}

int countPositions() {
    int count = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (PositionGetInteger(POSITION_MAGIC) == InputMagicNumber) count++;
    }
    return count;
}