//+------------------------------------------------------------------+
//|                               Singularity Horizontal v1.1.mq5    |
//|                        Copyright 2025, p3pwp3p                   |
//+------------------------------------------------------------------+
#property copyright "p3pwp3p"
#property version "1.11"  // 횡보장 필터 강화 버전

#include <Trade/Trade.mqh>

//--- User Inputs
input group "Strategy Settings";
input int InputEmaPeriod = 9;
input double InputLotSize = 0.1;
input int InputStopLoss = 0;
input int InputTakeProfit = 0;
input long InputMagicNumber = 20251120;
input color InputEmaColor = clrWhite;

input group "Entry Logic";
input bool InputUseRetestEntry = true;
input int InputRetestGap = 10;
input bool InputUseBreakoutEntry = true;

// [필수] 스프레드 필터
input int InputMaxSpread = 30;

input group "Filters";
input bool InputUseRibbonFilter = true;
input bool InputUseAdxFilter = true;
input int InputAdxThreshold = 20;  // 기준을 조금 낮춤 (너무 안 잡힐까봐)

// [핵심 수정] 기울기 필터 기본값 ON / 강도 강화
input bool InputUseSlopeFilter = true;
input double InputSlopeThreshold =
    3.0;  // 2.0 -> 3.0으로 강화 (더 가파를 때만 진입)

input group "Exit Settings";
input int InputExitPoints = 40;

input group "Visual Settings";
input bool InputShowDebugLog = true;

//--- Global Variables
int emaHandle;
int vwapHandle;
int trpHandle;
int adxHandle;
CTrade trade;

datetime lastBarTime;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit() {
    emaHandle = iCustom(_Symbol, _Period, "Singularity EMA", InputEmaPeriod, 0,
                        MODE_EMA, InputEmaColor);
    vwapHandle = iCustom(_Symbol, _Period, "Singularity VWAP");
    trpHandle = iCustom(_Symbol, _Period, "Trend Ribbon Pro");
    adxHandle = iADX(_Symbol, _Period, 14);

    if (emaHandle == INVALID_HANDLE || vwapHandle == INVALID_HANDLE ||
        trpHandle == INVALID_HANDLE || adxHandle == INVALID_HANDLE) {
        return (INIT_FAILED);
    }

    if (MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE)) {
        ChartIndicatorAdd(0, 0, vwapHandle);
        ChartIndicatorAdd(0, 0, trpHandle);
        ChartIndicatorAdd(0, 0, emaHandle);
    }

    trade.SetExpertMagicNumber(InputMagicNumber);
    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    IndicatorRelease(emaHandle);
    IndicatorRelease(vwapHandle);
    IndicatorRelease(trpHandle);
    IndicatorRelease(adxHandle);
}

void OnTick() {
    if (PositionsTotal() > 0) CheckExitSignal();

    // 진입 (실시간 감시)
    if (PositionsTotal() == 0) CheckEntrySignal();
}

//+------------------------------------------------------------------+
//| 진입 로직 (기울기 필터 필수 적용)                                   |
//+------------------------------------------------------------------+
void CheckEntrySignal() {
    long currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    if (currentSpread > InputMaxSpread) return;

    double vwapBuffer[], emaBuffer[], ribbonBuffer[], adxBuffer[];
    MqlRates rates[];

    ArraySetAsSeries(vwapBuffer, true);
    ArraySetAsSeries(emaBuffer, true);
    ArraySetAsSeries(ribbonBuffer, true);
    ArraySetAsSeries(adxBuffer, true);
    ArraySetAsSeries(rates, true);

    if (CopyBuffer(vwapHandle, 0, 0, 3, vwapBuffer) < 3) return;
    if (CopyBuffer(emaHandle, 0, 0, 3, emaBuffer) < 3) return;
    if (CopyBuffer(trpHandle, 2, 0, 2, ribbonBuffer) < 2) return;
    if (CopyBuffer(adxHandle, 0, 0, 2, adxBuffer) < 2) return;
    if (CopyRates(_Symbol, _Period, 0, 3, rates) < 3) return;

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

    double vwapNow = vwapBuffer[0];
    double closePrev = rates[1].close;
    double closePrev2 = rates[2].close;

    double emaCurrent = emaBuffer[1];  // 1번봉 EMA
    double emaPrev = emaBuffer[2];     // 2번봉 EMA

    double ribbonColor = ribbonBuffer[1];
    double adxValue = adxBuffer[1];

    if (vwapNow == 0.0 || ribbonColor == EMPTY_VALUE) return;

    // --- [핵심] 기울기(Slope) 계산 ---
    // (현재 EMA - 직전 EMA) / Point = 기울기 점수
    double emaSlope = (emaCurrent - emaPrev) / point;

    // 기울기가 평평하면(설정값보다 작으면) 무조건 리턴 (횡보장 필터)
    if (InputUseSlopeFilter) {
        if (MathAbs(emaSlope) < InputSlopeThreshold) {
            // 디버그 로그가 필요하면 주석 해제
            // if(InputShowDebugLog) Print("진입 보류: EMA 평평함 (Slope: ",
            // DoubleToString(MathAbs(emaSlope), 2), ")");
            return;
        }
    }

    // --- 나머지 필터 ---
    bool filterPass = true;
    if (InputUseAdxFilter && adxValue < InputAdxThreshold) filterPass = false;
    if (!filterPass) return;

    // --- [전략 1] 리테스트 (Touch) ---
    bool buyRetest = false;
    bool sellRetest = false;

    if (InputUseRetestEntry) {
        double gap = InputRetestGap * point;

        // [BUY] 상승장 확정 + 눌림목 + (중요) 기울기도 양수여야 함
        if (closePrev > vwapBuffer[1] && emaSlope > 0) {
            if (ask <= vwapNow + gap && ask >= vwapNow - gap) buyRetest = true;
        }
        // [SELL] 하락장 확정 + 반등 + (중요) 기울기도 음수여야 함
        if (closePrev < vwapBuffer[1] && emaSlope < 0) {
            if (bid >= vwapNow - gap && bid <= vwapNow + gap) sellRetest = true;
        }
    }

    // --- [전략 2] 돌파 (Breakout) ---
    bool buyBreakout = false;
    bool sellBreakout = false;

    if (InputUseBreakoutEntry) {
        if (closePrev2 <= emaBuffer[2] && closePrev > emaCurrent) {
            if (closePrev > vwapBuffer[1] && emaSlope > 0) buyBreakout = true;
        }
        if (closePrev2 >= emaBuffer[2] && closePrev < emaCurrent) {
            if (closePrev < vwapBuffer[1] && emaSlope < 0) sellBreakout = true;
        }
    }

    // --- 최종 진입 ---

    // BUY: 리본 필터 적용
    if ((buyRetest || buyBreakout) &&
        (!InputUseRibbonFilter || ribbonColor == 0.0)) {
        trade.Buy(InputLotSize, _Symbol, 0, 0, 0,
                  buyRetest ? "VWAP Retest Buy" : "EMA Breakout Buy");
        return;
    }

    // SELL: 리본 필터 적용
    if ((sellRetest || sellBreakout) &&
        (!InputUseRibbonFilter || ribbonColor == 1.0)) {
        trade.Sell(InputLotSize, _Symbol, 0, 0, 0,
                   sellRetest ? "VWAP Retest Sell" : "EMA Breakout Sell");
        return;
    }
}

//+------------------------------------------------------------------+
//| 청산 로직                                                        |
//+------------------------------------------------------------------+
void CheckExitSignal() {
    double emaBuffer[];
    ArraySetAsSeries(emaBuffer, true);
    if (CopyBuffer(emaHandle, 0, 0, 1, emaBuffer) < 1) return;

    double currentEma = emaBuffer[0];
    double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double exitDist = InputExitPoints * _Point;

    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (ticket <= 0) continue;
        if (PositionGetInteger(POSITION_MAGIC) != InputMagicNumber) continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

        long type = PositionGetInteger(POSITION_TYPE);
        double currentProfit = PositionGetDouble(POSITION_PROFIT);

        if (currentProfit > 0) {
            if (type == POSITION_TYPE_BUY &&
                (currentEma - currentBid) >= exitDist) {
                trade.PositionClose(ticket);
                Print("Exit Buy (Profit)");
            }
            if (type == POSITION_TYPE_SELL &&
                (currentAsk - currentEma) >= exitDist) {
                trade.PositionClose(ticket);
                Print("Exit Sell (Profit)");
            }
        }

        if (currentProfit < 0) {
            double vwapArr[];
            ArraySetAsSeries(vwapArr, true);
            if (CopyBuffer(vwapHandle, 0, 0, 1, vwapArr) < 1) return;
            double vwapVal = vwapArr[0];

            if (type == POSITION_TYPE_BUY &&
                currentBid < vwapVal - (exitDist / 2)) {
                trade.PositionClose(ticket);
                Print("StopLoss Buy: VWAP Broken");
            }
            if (type == POSITION_TYPE_SELL &&
                currentAsk > vwapVal + (exitDist / 2)) {
                trade.PositionClose(ticket);
                Print("StopLoss Sell: VWAP Broken");
            }
        }
    }
}

bool isNewBar() {
    datetime currentBarTime = iTime(_Symbol, _Period, 0);
    if (lastBarTime != currentBarTime) {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}