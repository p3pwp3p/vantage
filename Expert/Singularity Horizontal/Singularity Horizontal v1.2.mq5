//+------------------------------------------------------------------+
//|                               Singularity Horizontal v1.1.mq5    |
//|                        Copyright 2025, p3pwp3p                   |
//+------------------------------------------------------------------+
#property copyright "p3pwp3p"
#property version "1.20"

#include <Trade/Trade.mqh>

//--- User Inputs
input group "Strategy Settings";
input int InputEmaPeriod = 9;  // 매매 기준 EMA (추세 추종용)
input double InputLotSize = 0.1;
input int InputStopLoss = 0;  // 0 권장 (자동 손절 로직 사용)
input int InputTakeProfit = 0;
input long InputMagicNumber = 20251120;
input color InputEmaColor = clrWhite;

input group "Entry Logic";
input bool InputUseRetestEntry = true;    // VWAP 터치 진입 사용
input int InputRetestGap = 10;            // 터치 인정 범위 (포인트)
input bool InputUseBreakoutEntry = true;  // 돌파 진입 사용
input int InputMaxSpread = 30;            // 스프레드 필터

input group "Filters";
// [Trend Ribbon] PB 영상처럼 5 EMA를 기준으로 한 빠른 리본을 봅니다.
input int InputRibbonPeriod = 5;         // 리본 지표용 EMA (짧게 설정)
input bool InputUseRibbonFilter = true;  // 리본 색상 일치 시에만 진입
input bool InputUseAdxFilter = true;
input int InputAdxThreshold = 20;
input bool InputUseSlopeFilter = true;
input double InputSlopeThreshold = 3.0;

input group "Exit Settings";
input bool InputUsePartialClose = true;  // 분할 청산 사용
input int InputPartialPips = 200;        // 200포인트 수익 시 절반 청산
input double InputPartialRatio = 0.5;
input bool InputUseBreakEven = true;  // 나머지 본절 설정
input int InputExitPoints = 40;       // 수익 중일 때 EMA 이탈 청산

input group "Visual Settings";
input bool InputShowDebugLog = true;

//--- Global Variables
int emaHandle;
int vwapHandle;
int trpHandle;
int adxHandle;
CTrade trade;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit() {
    // 1. 매매 기준 EMA (9일선)
    emaHandle = iCustom(_Symbol, _Period, "Singularity EMA", InputEmaPeriod, 0,
                        MODE_EMA, InputEmaColor);

    // 2. VWAP
    vwapHandle = iCustom(_Symbol, _Period, "Singularity VWAP");

    // 3. 리본 (PB 스타일 - 5일선 등 짧은 EMA 기준)
    // 파라미터 순서: InputEmaPeriod, InputMethod, InputPrice
    trpHandle = iCustom(_Symbol, _Period, "Trend Ribbon Pro", InputRibbonPeriod,
                        MODE_EMA, PRICE_CLOSE);

    // 4. ADX
    adxHandle = iADX(_Symbol, _Period, 14);

    if (emaHandle == INVALID_HANDLE || vwapHandle == INVALID_HANDLE ||
        trpHandle == INVALID_HANDLE || adxHandle == INVALID_HANDLE) {
        Print("지표 로딩 실패. Indicators 폴더 파일 확인 바람.");
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
    if (PositionsTotal() > 0) {
        CheckExitSignal();
        if (InputUsePartialClose) CheckPartialClose();
    }

    if (PositionsTotal() == 0) CheckEntrySignal();
}

//+------------------------------------------------------------------+
//| 진입 로직 (하이브리드 + 필터)                                      |
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

    double emaCurrent = emaBuffer[1];
    double emaPrev = emaBuffer[2];

    double ribbonColor = ribbonBuffer[1];
    double adxValue = adxBuffer[1];

    if (vwapNow == 0.0 || ribbonColor == EMPTY_VALUE) return;

    // --- 필터 체크 ---
    bool filterPass = true;
    if (InputUseAdxFilter && adxValue < InputAdxThreshold) filterPass = false;

    double emaSlope = (emaCurrent - emaPrev) / point;
    if (InputUseSlopeFilter && MathAbs(emaSlope) < InputSlopeThreshold)
        filterPass = false;

    if (!filterPass) return;

    // --- [전략 1] 리테스트 (Touch) ---
    bool buyRetest = false;
    bool sellRetest = false;

    if (InputUseRetestEntry) {
        double gap = InputRetestGap * point;
        if (closePrev > vwapBuffer[1] && emaSlope > 0) {
            if (ask <= vwapNow + gap && ask >= vwapNow - gap) buyRetest = true;
        }
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
    if ((buyRetest || buyBreakout) &&
        (!InputUseRibbonFilter || ribbonColor == 0.0)) {
        trade.Buy(InputLotSize, _Symbol, 0, 0, 0,
                  buyRetest ? "VWAP Retest Buy" : "EMA Breakout Buy");
    }

    if ((sellRetest || sellBreakout) &&
        (!InputUseRibbonFilter || ribbonColor == 1.0)) {
        trade.Sell(InputLotSize, _Symbol, 0, 0, 0,
                   sellRetest ? "VWAP Retest Sell" : "EMA Breakout Sell");
    }
}

//+------------------------------------------------------------------+
//| 청산 로직 (PB 스타일: 이익중 EMA 이탈 / 손실중 VWAP 이탈)          |
//+------------------------------------------------------------------+
void CheckExitSignal() {
    double emaBuffer[], vwapBuffer[];
    ArraySetAsSeries(emaBuffer, true);
    ArraySetAsSeries(vwapBuffer, true);

    if (CopyBuffer(emaHandle, 0, 0, 1, emaBuffer) < 1) return;
    if (CopyBuffer(vwapHandle, 0, 0, 1, vwapBuffer) < 1) return;

    double currentEma = emaBuffer[0];
    double currentVwap = vwapBuffer[0];
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

        // [수익 중] 9 EMA 추세 추종 (이탈 시 익절)
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

        // [손실 중] VWAP 지지/저항 실패 시 손절
        if (currentProfit < 0) {
            if (type == POSITION_TYPE_BUY &&
                currentBid < currentVwap - (exitDist / 2)) {
                trade.PositionClose(ticket);
                Print("StopLoss Buy: VWAP Broken");
            }
            if (type == POSITION_TYPE_SELL &&
                currentAsk > currentVwap + (exitDist / 2)) {
                trade.PositionClose(ticket);
                Print("StopLoss Sell: VWAP Broken");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 분할 청산 및 본절 로직                                            |
//+------------------------------------------------------------------+
void CheckPartialClose() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (ticket <= 0) continue;
        if (PositionGetInteger(POSITION_MAGIC) != InputMagicNumber) continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double profitPoints = 0;
        long type = PositionGetInteger(POSITION_TYPE);
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

        if (type == POSITION_TYPE_BUY)
            profitPoints = (bid - openPrice) / _Point;
        else
            profitPoints = (openPrice - ask) / _Point;

        if (profitPoints >= InputPartialPips) {
            bool isSLMoved = false;
            if (type == POSITION_TYPE_BUY && currentSL >= openPrice)
                isSLMoved = true;
            if (type == POSITION_TYPE_SELL && currentSL > 0 &&
                currentSL <= openPrice)
                isSLMoved = true;

            if (!isSLMoved) {
                double volume = PositionGetDouble(POSITION_VOLUME);
                double closeVol = volume * InputPartialRatio;
                double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
                double stepVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
                closeVol = MathFloor(closeVol / stepVol) * stepVol;
                if (closeVol < minVol) closeVol = minVol;

                if (closeVol < volume)
                    trade.PositionClosePartial(ticket, closeVol);

                if (InputUseBreakEven) {
                    double newSL = (type == POSITION_TYPE_BUY)
                                       ? openPrice + 10 * _Point
                                       : openPrice - 10 * _Point;
                    trade.PositionModify(ticket, newSL, 0);
                }
            }
        }
    }
}