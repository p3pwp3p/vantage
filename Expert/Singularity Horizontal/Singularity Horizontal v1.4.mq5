//+------------------------------------------------------------------+
//|                               Singularity Horizontal v1.7.mq5    |
//|                        Copyright 2025, p3pwp3p                   |
//+------------------------------------------------------------------+
#property copyright "p3pwp3p"
#property version "1.70"  // 시간대 제한(Time Filter) 추가

#include <Trade/Trade.mqh>

//--- User Inputs
input group "Strategy Settings";
input int InputEmaPeriod = 9;
input double InputLotSize = 0.1;
input int InputStopLoss = 0;
input int InputTakeProfit = 0;
input long InputMagicNumber = 20251120;
input color InputEmaColor = clrWhite;

// [신규] 시간 제한 설정 (브로커 서버 시간 기준)
input group "Time Settings";
input bool InputUseTimer = true;  // 시간 제한 사용할까?
input int InputStartHour = 21;    // 시작 시간 (예: 15시 = 미장 프리마켓 쯤)
input int InputEndHour = 5;      // 종료 시간 (예: 23시)

input group "Entry Logic";
input bool InputSimpleEntry = true;
input int InputMaxSpread = 30;

input group "Filters";
input bool InputUseTrendAlign = false;
input bool InputUseRibbonFilter = false;
input bool InputUseAdxFilter = false;
input int InputAdxThreshold = 20;
input bool InputUseSlopeFilter = false;
input double InputSlopeThreshold = 0.5;

input group "Exit Settings";
input int InputExitPoints = 40;
input bool InputUsePartialClose = true;
input int InputPartialPips = 200;
input double InputPartialRatio = 0.5;
input bool InputUseBreakEven = true;
input int InputMinProfit = 100;

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
    trpHandle = iCustom(_Symbol, _Period, "Trend Ribbon Pro", 5);
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
    if (PositionsTotal() > 0) {
        CheckExitSignal_Realtime();  // 급락 감시
    }

    if (isNewBar()) {
        if (PositionsTotal() > 0) {
            CheckExitSignal_Close();
            if (InputUsePartialClose) CheckPartialClose();
        }

        // [핵심] 시간이 맞을 때만 진입 시도
        if (PositionsTotal() == 0) {
            if (IsTradingTime()) CheckEntrySignal();
        }
    }
}

//+------------------------------------------------------------------+
//| [신규] 거래 시간 확인 함수                                         |
//+------------------------------------------------------------------+
bool IsTradingTime() {
    if (!InputUseTimer) return true;  // 타이머 안 쓰면 항상 True

    MqlDateTime dt;
    TimeCurrent(dt);  // 현재 서버 시간

    int currentHour = dt.hour;

    // 시작 시간 <= 현재 시간 < 종료 시간
    // 예: 15시 ~ 20시 설정 시 -> 15:00 ~ 19:59:59 까지 거래
    if (currentHour >= InputStartHour && currentHour < InputEndHour) {
        return true;
    }

    return false;
}

// ... (나머지 CheckEntrySignal, Exit 로직은 기존 v1.61과 동일) ...
// ... (전체 코드가 필요하면 다시 붙여넣겠습니다) ...

//+------------------------------------------------------------------+
//| 진입 로직 (Simple Mode)                                          |
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

    double closePrev = rates[1].close;
    double openPrev = rates[1].open;
    double vwapVal = vwapBuffer[1];
    double emaVal = emaBuffer[1];
    double ribbonColor = ribbonBuffer[1];
    double adxValue = adxBuffer[1];

    if (InputUseAdxFilter && adxValue < 20) return;
    if (InputUseTrendAlign) {
        if (closePrev > vwapVal && emaVal < vwapVal) return;
        if (closePrev < vwapVal && emaVal > vwapVal) return;
    }
    if (InputUseRibbonFilter) {
        if (closePrev > vwapVal && ribbonColor != 0.0) return;
        if (closePrev < vwapVal && ribbonColor != 1.0) return;
    }

    bool isBuy = false;
    bool isSell = false;

    if (InputSimpleEntry) {
        if (closePrev > openPrev && closePrev > emaVal && closePrev > vwapVal)
            isBuy = true;
        if (closePrev < openPrev && closePrev < emaVal && closePrev < vwapVal)
            isSell = true;
    }

    if (isBuy) trade.Buy(InputLotSize, _Symbol, 0, 0, 0, "Simple Buy");
    if (isSell) trade.Sell(InputLotSize, _Symbol, 0, 0, 0, "Simple Sell");
}

// ... (CheckExitSignal_Close, CheckExitSignal_Realtime, CheckPartialClose,
// isNewBar는 v1.61과 동일) ...
// ... (아래 생략된 부분은 기존 코드 그대로 쓰시면 됩니다) ...
void CheckExitSignal_Close() {
    double emaBuffer[];
    MqlRates rates[];
    ArraySetAsSeries(emaBuffer, true);
    ArraySetAsSeries(rates, true);
    if (CopyBuffer(emaHandle, 0, 0, 2, emaBuffer) < 2) return;
    if (CopyRates(_Symbol, _Period, 0, 2, rates) < 2) return;
    double closePrev = rates[1].close;
    double emaPrev = emaBuffer[1];
    double exitDist = InputExitPoints * _Point;

    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (ticket <= 0) continue;
        if (PositionGetInteger(POSITION_MAGIC) != InputMagicNumber) continue;
        long type = PositionGetInteger(POSITION_TYPE);

        if (type == POSITION_TYPE_BUY) {
            if ((emaPrev - closePrev) >= exitDist) trade.PositionClose(ticket);
        }
        if (type == POSITION_TYPE_SELL) {
            if ((closePrev - emaPrev) >= exitDist) trade.PositionClose(ticket);
        }
    }
}

void CheckExitSignal_Realtime() {
    double emaBuffer[];
    ArraySetAsSeries(emaBuffer, true);
    if (CopyBuffer(emaHandle, 0, 0, 1, emaBuffer) < 1) return;
    double currentEma = emaBuffer[0];
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double emergencyDist = 150 * _Point;

    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (ticket <= 0) continue;
        if (PositionGetInteger(POSITION_MAGIC) != InputMagicNumber) continue;
        long type = PositionGetInteger(POSITION_TYPE);
        if (type == POSITION_TYPE_BUY && (currentEma - bid) >= emergencyDist)
            trade.PositionClose(ticket);
        if (type == POSITION_TYPE_SELL && (ask - currentEma) >= emergencyDist)
            trade.PositionClose(ticket);
    }
}

void CheckPartialClose() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (ticket <= 0) continue;
        if (PositionGetInteger(POSITION_MAGIC) != InputMagicNumber) continue;
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        long type = PositionGetInteger(POSITION_TYPE);
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double profitPoints = (type == POSITION_TYPE_BUY)
                                  ? (bid - openPrice) / _Point
                                  : (openPrice - ask) / _Point;

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

bool isNewBar() {
    datetime currentBarTime = iTime(_Symbol, _Period, 0);
    if (lastBarTime != currentBarTime) {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}