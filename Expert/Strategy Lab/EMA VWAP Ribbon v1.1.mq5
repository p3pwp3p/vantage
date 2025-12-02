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
input int InputStartHour = 1;         // 시작 시간 (1 = 01:00부터 거래)
input int InputCrossGap = 30;         // 크로스 갭 (포인트 단위)
input int InputAdxThreshold = 25;     // 횡보 필터 기준값
input int InputCooldownMinutes = 30;  // 쿨다운 시간 (분)

input group "Emergency Exit";
input double InputBreakMultiplier =
    1.5;  // ★ 강한 돌파 기준 (ATR의 몇 배만큼 뚫어야 청산할지)

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
int adxHandle;
int atrHandle;  // ★ ATR 핸들 추가
double vwapBuffer[];
double ribbonColorBuffer[];
double emaBuffer[];
double adxBuffer[];
double atrBuffer[];  // ★ ATR 버퍼 추가
datetime lastBarTime = 0;
datetime lastExitTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    trade.SetExpertMagicNumber(InputMagicNumber);
    trade.SetDeviationInPoints(InputSlippage);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    trade.SetAsyncMode(false);

    lastBarTime = 0;
    lastExitTime = 0;

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

    // 4. ADX 핸들
    adxHandle = iADX(_Symbol, _Period, 14);
    if (adxHandle == INVALID_HANDLE) return (INIT_FAILED);

    // ★ 5. ATR 핸들 (강한 돌파 감지용, 기간 14)
    atrHandle = iATR(_Symbol, _Period, 14);
    if (atrHandle == INVALID_HANDLE) {
        Print("Failed to create ATR handle.");
        return (INIT_FAILED);
    }

    ArraySetAsSeries(emaBuffer, true);
    ArraySetAsSeries(vwapBuffer, true);
    ArraySetAsSeries(ribbonColorBuffer, true);
    ArraySetAsSeries(adxBuffer, true);
    ArraySetAsSeries(atrBuffer, true);

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    if (emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
    if (vwapHandle != INVALID_HANDLE) IndicatorRelease(vwapHandle);
    if (ribbonHandle != INVALID_HANDLE) IndicatorRelease(ribbonHandle);
    if (adxHandle != INVALID_HANDLE) IndicatorRelease(adxHandle);
    if (atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    if (!updateBuffers()) return;

    checkExitSignal();
    checkEntrySignal();
}

// --- 사용자 정의 함수 ---

bool updateBuffers() {
    if (CopyBuffer(emaHandle, 0, 0, 3, emaBuffer) < 3) return false;
    if (CopyBuffer(vwapHandle, 0, 0, 3, vwapBuffer) < 3) return false;
    if (CopyBuffer(ribbonHandle, 2, 0, 3, ribbonColorBuffer) < 3) return false;
    if (CopyBuffer(adxHandle, 0, 0, 3, adxBuffer) < 3) return false;
    if (CopyBuffer(atrHandle, 0, 0, 3, atrBuffer) < 3)
        return false;  // ATR 복사
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

void checkEntrySignal() {
    // 1. 시간 필터
    datetime currentBarTime = iTime(_Symbol, _Period, 0);
    MqlDateTime dt;
    TimeToStruct(currentBarTime, dt);
    if (dt.hour < InputStartHour) return;

    // 2. 캔들 중복 진입 방지
    if (lastBarTime == currentBarTime) return;

    // 3. 쿨다운 체크
    if (TimeCurrent() < lastExitTime + (InputCooldownMinutes * 60)) return;

    // 4. 횡보장 필터
    if (adxBuffer[1] < InputAdxThreshold) return;

    // 5. 확정된 캔들(1, 2) 기준 크로스 체크
    double ema2 = emaBuffer[2];
    double ema1 = emaBuffer[1];
    double vwap2 = vwapBuffer[2];
    double vwap1 = vwapBuffer[1];

    if (ema2 == 0 || ema1 == 0 || vwap2 == 0 || vwap1 == 0 ||
        vwap1 == EMPTY_VALUE)
        return;

    double gapValue = InputCrossGap * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

    bool isGoldenCrossWithGap =
        (ema2 < vwap2 + gapValue) && (ema1 > vwap1 + gapValue);
    bool isDeadCrossWithGap =
        (ema2 > vwap2 - gapValue) && (ema1 < vwap1 - gapValue);

    if (isGoldenCrossWithGap) {
        if (!hasPosition(POSITION_TYPE_BUY)) {
            if (trade.Buy(InputLotSize, _Symbol)) {
                Print("Buy Order (Confirmed Bar).");
                lastBarTime = currentBarTime;
            }
        }
    } else if (isDeadCrossWithGap) {
        if (!hasPosition(POSITION_TYPE_SELL)) {
            if (trade.Sell(InputLotSize, _Symbol)) {
                Print("Sell Order (Confirmed Bar).");
                lastBarTime = currentBarTime;
            }
        }
    }
}

void checkExitSignal() {
    double currentColor = ribbonColorBuffer[0];
    double currentEMA = emaBuffer[0];                   // 현재 진행 중인 EMA
    double currentClose = iClose(_Symbol, _Period, 0);  // 현재 가격
    double currentATR = atrBuffer[0];                   // 현재 ATR

    if (currentColor == EMPTY_VALUE) return;

    // ★ 강한 돌파 기준 계산
    double strongBreakDist = currentATR * InputBreakMultiplier;

    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (PositionGetInteger(POSITION_MAGIC) == InputMagicNumber) {
            long type = PositionGetInteger(POSITION_TYPE);
            bool closeIt = false;
            string exitReason = "";

            // 1. 매수 포지션 청산 조건
            if (type == POSITION_TYPE_BUY) {
                // A. 리본 색상 변경 (기본)
                if (currentColor == 1.0) {
                    closeIt = true;
                    exitReason = "Ribbon Color Change";
                }
                // B. ★ 강한 하락 돌파 (Emergency Exit)
                // 현재가가 EMA보다 아래에 있고, 그 거리가 ATR*1.5 이상일 때
                else if (currentClose < currentEMA &&
                         (currentEMA - currentClose) > strongBreakDist) {
                    closeIt = true;
                    exitReason = "Strong Downward Break";
                }
            }
            // 2. 매도 포지션 청산 조건
            else if (type == POSITION_TYPE_SELL) {
                // A. 리본 색상 변경 (기본)
                if (currentColor == 0.0) {
                    closeIt = true;
                    exitReason = "Ribbon Color Change";
                }
                // B. ★ 강한 상승 돌파 (Emergency Exit)
                // 현재가가 EMA보다 위에 있고, 그 거리가 ATR*1.5 이상일 때
                else if (currentClose > currentEMA &&
                         (currentClose - currentEMA) > strongBreakDist) {
                    closeIt = true;
                    exitReason = "Strong Upward Break";
                }
            }

            if (closeIt) {
                if (trade.PositionClose(ticket)) {
                    lastExitTime = TimeCurrent();
                    Print("Position Closed. Reason: ", exitReason);
                }
            }
        }
    }
}