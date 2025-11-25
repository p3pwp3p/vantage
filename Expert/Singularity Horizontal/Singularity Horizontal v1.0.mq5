//+------------------------------------------------------------------+
//|                               Singularity Horizontal v1.0.mq5    |
//|                        Copyright 2025, p3pwp3p                   |
//+------------------------------------------------------------------+
#property copyright "p3pwp3p"
#property version "1.00"

#include <Trade/Trade.mqh>

input group "Strategy Settings";
input int InputEmaPeriod = 9;
input double InputLotSize = 0.1;
input int InputStopLoss = 0;
input int InputTakeProfit = 0;
input long InputMagicNumber = 20251120;
input color InputEmaColor = clrWhite;

input group "Trend Strength Filters";
input bool InputUseAdxFilter = true;
input int InputAdxPeriod = 14;
input int InputAdxThreshold = 25;
input bool InputUseSlopeFilter = true;
input double InputSlopeThreshold = 2.0;

input group "Entry Filters";
input bool InputUseDistanceFilter = true;
input int InputMaxVwapDistance = 1300;

input bool InputUseRetestFilter = false;
input int InputRetestBars = 5;
input bool InputUseHighLowFilter = false;
input int InputHighLowBars = 5;

input group "Exit Settings";
input int InputExitPoints = 40;

input group "Visual Settings";
input bool InputShowDebugLog = true;

int emaHandle;
int vwapHandle;
int trpHandle;
int adxHandle;
CTrade trade;
datetime lastBarTime;

int OnInit() {
    emaHandle = iCustom(_Symbol, _Period, "Singularity EMA", InputEmaPeriod, 0,
                        MODE_EMA, InputEmaColor);
    vwapHandle = iCustom(_Symbol, _Period, "Singularity VWAP");
    trpHandle = iCustom(_Symbol, _Period, "Trend Ribbon Pro");
    adxHandle = iADX(_Symbol, _Period, InputAdxPeriod);

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
    if (isNewBar()) {
        if (PositionsTotal() == 0) CheckEntrySignal();
    }
}

void CheckEntrySignal() {
    int lookBack = MathMax(InputRetestBars, InputHighLowBars) + 5;

    double emaBuffer[], vwapBuffer[], ribbonColorBuf[], adxBuffer[];
    MqlRates rates[];

    ArraySetAsSeries(emaBuffer, true);
    ArraySetAsSeries(vwapBuffer, true);
    ArraySetAsSeries(ribbonColorBuf, true);
    ArraySetAsSeries(adxBuffer, true);
    ArraySetAsSeries(rates, true);

    if (CopyBuffer(emaHandle, 0, 0, lookBack, emaBuffer) < lookBack) return;
    if (CopyBuffer(vwapHandle, 0, 0, lookBack, vwapBuffer) < lookBack) return;
    if (CopyBuffer(trpHandle, 2, 0, 2, ribbonColorBuf) < 2) return;
    if (CopyBuffer(adxHandle, 0, 0, 2, adxBuffer) < 2) return;
    if (CopyRates(_Symbol, _Period, 0, lookBack, rates) < lookBack) return;

    double closeCurrent = rates[1].close;
    double vwapCurrent = vwapBuffer[1];
    double emaCurrent = emaBuffer[1];
    double emaPrev = emaBuffer[2];
    double ribbonColor = ribbonColorBuf[1];
    double adxCurrent = adxBuffer[1];

    if (vwapCurrent == 0.0 || ribbonColor == EMPTY_VALUE) return;

    double distPoints = MathAbs(closeCurrent - vwapCurrent) / _Point;
    bool distPass = true;

    if (InputUseDistanceFilter) {
        if (distPoints > InputMaxVwapDistance) distPass = false;
    }

    bool adxPass = (!InputUseAdxFilter || adxCurrent >= InputAdxThreshold);
    double emaSlope = (emaCurrent - emaPrev) / _Point;
    bool slopePass =
        (!InputUseSlopeFilter || MathAbs(emaSlope) >= InputSlopeThreshold);

    bool retestForBuy = true, retestForSell = true;
    if (InputUseRetestFilter) {
        retestForBuy = wasRetesting(rates, vwapBuffer, InputRetestBars, true);
        retestForSell = wasRetesting(rates, vwapBuffer, InputRetestBars, false);
    }

    bool breakoutBuy = true, breakoutSell = true;
    if (InputUseHighLowFilter) {
        double highestHigh = -1.0;
        double lowestLow = 999999.0;
        for (int i = 2; i <= InputHighLowBars + 1; i++) {
            if (rates[i].high > highestHigh) highestHigh = rates[i].high;
            if (rates[i].low < lowestLow) lowestLow = rates[i].low;
        }
        breakoutBuy = (closeCurrent > highestHigh);
        breakoutSell = (closeCurrent < lowestLow);
    }

    bool commonFilter = distPass && adxPass && slopePass;

    bool isBuySignal = commonFilter && retestForBuy && breakoutBuy &&
                       (closeCurrent > vwapCurrent) &&
                       (closeCurrent > emaCurrent);

    bool isSellSignal = commonFilter && retestForSell && breakoutSell &&
                        (closeCurrent < vwapCurrent) &&
                        (closeCurrent < emaCurrent);

    if (InputShowDebugLog) {
        bool basicBuy =
            (closeCurrent > vwapCurrent && closeCurrent > emaCurrent);
        bool basicSell =
            (closeCurrent < vwapCurrent && closeCurrent < emaCurrent);

        if ((basicBuy || basicSell) && !isBuySignal && !isSellSignal) {
            string reason = "진입 보류: ";

            if (InputUseDistanceFilter && !distPass)
                reason += StringFormat("[VWAP이격과다: %.0f] ", distPoints);

            if (!adxPass) reason += "[ADX약함] ";
            if (!slopePass) reason += "[기울기평평] ";

            Print(reason);
        }
    }

    if (isBuySignal) {
        double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double sl = (InputStopLoss > 0) ? ask - InputStopLoss * _Point : 0;
        double tp = (InputTakeProfit > 0) ? ask + InputTakeProfit * _Point : 0;

        if (!InputUseSlopeFilter || emaSlope > 0)
            trade.Buy(InputLotSize, _Symbol, 0, sl, tp, "Singularity Buy");
    } else if (isSellSignal) {
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double sl = (InputStopLoss > 0) ? bid + InputStopLoss * _Point : 0;
        double tp = (InputTakeProfit > 0) ? bid - InputTakeProfit * _Point : 0;

        if (!InputUseSlopeFilter || emaSlope < 0)
            trade.Sell(InputLotSize, _Symbol, 0, sl, tp, "Singularity Sell");
    }
}

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
            if (type == POSITION_TYPE_BUY) {
                if ((currentEma - currentBid) >= exitDist) {
                    trade.PositionClose(ticket);
                    Print("Exit Buy (Profit): EMA 이탈 익절");
                }
            }
            if (type == POSITION_TYPE_SELL) {
                if ((currentAsk - currentEma) >= exitDist) {
                    trade.PositionClose(ticket);
                    Print("Exit Sell (Profit): EMA 돌파 익절");
                }
            }
        }
    }
}

bool wasRetesting(MqlRates& rates[], double& vwap[], int barsToCheck,
                  bool forBuy) {
    for (int i = 2; i <= barsToCheck + 1; i++) {
        double vwapVal = vwap[i];
        if (forBuy) {
            if (rates[i].low <= vwapVal) return true;
        } else {
            if (rates[i].high >= vwapVal) return true;
        }
    }
    return false;
}

bool isNewBar() {
    datetime currentBarTime = iTime(_Symbol, _Period, 0);
    if (lastBarTime != currentBarTime) {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}