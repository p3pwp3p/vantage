//+------------------------------------------------------------------+
//|                               Singularity Horizontal v1.3.mq5    |
//|                        Copyright 2025, p3pwp3p                   |
//+------------------------------------------------------------------+
#property copyright "p3pwp3p"
#property version "1.30"  // Trailing Stop 기능 추가 패치

#include <Trade/Trade.mqh>

//--- User Inputs
input group "Strategy Settings";
input int InputEmaPeriod = 9;
input double InputLotSize = 0.1;
input int InputStopLoss = 0;
input int InputTakeProfit = 0;
input long InputMagicNumber = 20251120;
input color InputEmaColor = clrWhite;

input group "Entry Logic (Gap)";
input bool InputUseGapEntry = true;
input int InputMaxSpread = 30;

input group "Filters";
input bool InputUseTrendAlign = true;
input bool InputUseRibbonFilter = true;
input bool InputUseAdxFilter = true;
input int InputAdxThreshold = 20;

input group "Exit Settings";
// [신규] 트레이링 스탑 (수익 추적)
input bool InputUseTrailingStop = true;  // 사용 여부
input int InputTrailingStart = 100;      // 100포인트(10핍) 수익부터 작동 시작
input int InputTrailingDist = 50;        // 가격 뒤 50포인트(5핍) 간격 유지
input int InputTrailingStep = 10;  // 10포인트 단위로 SL 갱신 (서버 부하 방지)
input int InputMinProfit = 100;

// 분할 청산
input bool InputUsePartialClose = true;
input int InputPartialPips = 200;
input double InputPartialRatio = 0.5;
input bool InputUseBreakEven = true;
// 전체 청산 (EMA 이탈)
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
    trpHandle = iCustom(_Symbol, _Period, "Trend Ribbon Pro");  // 기본값 호출
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
    // 1. 청산 및 관리 (가장 중요하므로 매 틱 실행)
    if (PositionsTotal() > 0) {
        CheckExitSignal();                              // 1) EMA 이탈 청산
        if (InputUsePartialClose) CheckPartialClose();  // 2) 분할 청산
        if (InputUseTrailingStop)
            CheckTrailingStop();  // 3) [신규] 트레이링 스탑
    }

    // 2. 진입 (실시간 Gap 감시)
    if (PositionsTotal() == 0) CheckEntrySignal();
}

//+------------------------------------------------------------------+
//| [신규] 트레이링 스탑 로직                                          |
//+------------------------------------------------------------------+
void CheckTrailingStop() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (ticket <= 0) continue;
        if (PositionGetInteger(POSITION_MAGIC) != InputMagicNumber) continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

        long type = PositionGetInteger(POSITION_TYPE);
        double currentSL = PositionGetDouble(POSITION_SL);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

        double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

        // 포인트 단위를 가격 단위로 변환
        double startDist = InputTrailingStart * point;
        double trailDist = InputTrailingDist * point;
        double stepDist = InputTrailingStep * point;

        // [BUY 포지션]
        if (type == POSITION_TYPE_BUY) {
            // 1. 현재 수익이 시작 기준(Start)을 넘었는가?
            if (bid - openPrice > startDist) {
                // 2. 새로운 SL 목표가 계산 (현재가 - 간격)
                double newSL = bid - trailDist;

                // 3. 기존 SL보다 높고, 변경 폭(Step)만큼 움직였을 때만 수정
                if (newSL > currentSL + stepDist) {
                    if (trade.PositionModify(ticket, newSL, 0)) {
                        // Print("Trailing Stop: SL moved up to ", newSL);
                    }
                }
            }
        }

        // [SELL 포지션]
        if (type == POSITION_TYPE_SELL) {
            // 1. 현재 수익이 시작 기준을 넘었는가? (진입가 - 현재가)
            if (openPrice - ask > startDist) {
                // 2. 새로운 SL 목표가 계산 (현재가 + 간격)
                double newSL = ask + trailDist;

                // 3. 기존 SL보다 낮고(더 타이트하고), 변경 폭만큼 움직였을 때만
                // 수정 (SELL의 SL은 0일 때 가장 높으므로 0체크 필요)
                if (currentSL == 0 || newSL < currentSL - stepDist) {
                    if (trade.PositionModify(ticket, newSL, 0)) {
                        // Print("Trailing Stop: SL moved down to ", newSL);
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 진입 로직 (v1.3 Gap Entry)                                       |
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

    if (CopyBuffer(vwapHandle, 0, 0, 2, vwapBuffer) < 2) return;
    if (CopyBuffer(emaHandle, 0, 0, 2, emaBuffer) < 2) return;
    if (CopyBuffer(trpHandle, 2, 0, 2, ribbonBuffer) < 2) return;
    if (CopyBuffer(adxHandle, 0, 0, 2, adxBuffer) < 2) return;
    if (CopyRates(_Symbol, _Period, 0, 2, rates) < 2) return;

    double vwapNow = vwapBuffer[0];
    double emaNow = emaBuffer[0];
    double ribbonColor = ribbonBuffer[0];
    double adxValue = adxBuffer[0];

    double openPrev = rates[1].open;
    double closePrev = rates[1].close;
    double highNow = rates[0].high;
    double lowNow = rates[0].low;

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if (vwapNow == 0.0 || ribbonColor == EMPTY_VALUE) return;
    if (InputUseAdxFilter && adxValue < InputAdxThreshold) return;

    bool isAlignedBuy = true;
    bool isAlignedSell = true;
    if (InputUseTrendAlign) {
        isAlignedBuy = (emaNow > vwapNow);
        isAlignedSell = (emaNow < vwapNow);
    }

    bool isBuySignal = false;
    bool isSellSignal = false;

    if (InputUseGapEntry) {
        if (isAlignedBuy && closePrev > openPrev &&
            (!InputUseRibbonFilter || ribbonColor == 0.0) && ask > vwapNow &&
            lowNow > emaNow) {
            isBuySignal = true;
        }

        if (isAlignedSell && openPrev > closePrev &&
            (!InputUseRibbonFilter || ribbonColor == 1.0) && bid < vwapNow &&
            highNow < emaNow) {
            isSellSignal = true;
        }
    }

    if (isBuySignal) {
        double sl = (InputStopLoss > 0) ? ask - InputStopLoss * _Point : 0;
        double tp = (InputTakeProfit > 0) ? ask + InputTakeProfit * _Point : 0;
        trade.Buy(InputLotSize, _Symbol, 0, sl, tp, "Gap Buy");
    } else if (isSellSignal) {
        double sl = (InputStopLoss > 0) ? bid + InputStopLoss * _Point : 0;
        double tp = (InputTakeProfit > 0) ? bid - InputTakeProfit * _Point : 0;
        trade.Sell(InputLotSize, _Symbol, 0, sl, tp, "Gap Sell");
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
    double exitDist   = InputExitPoints * _Point; 

    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (ticket <= 0) continue;
        if (PositionGetInteger(POSITION_MAGIC) != InputMagicNumber) continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

        long type = PositionGetInteger(POSITION_TYPE);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        
        // [수정] 단순 금액(Profit)이 아니라 '포인트' 단위로 수익 계산
        double profitPoints = 0;
        if (type == POSITION_TYPE_BUY)  profitPoints = (currentBid - openPrice) / _Point;
        if (type == POSITION_TYPE_SELL) profitPoints = (openPrice - currentAsk) / _Point;

        // 1. 수익 중일 때: EMA 이탈 청산 (Trailing Exit)
        // [핵심] "최소 수익(InputMinProfit) 이상일 때만" 작동
        if (profitPoints > InputMinProfit) {
            if (type == POSITION_TYPE_BUY) {
                // 현재가가 EMA보다 40포인트 아래로 떨어짐
                if ((currentEma - currentBid) >= exitDist) {
                    trade.PositionClose(ticket);
                    Print("Exit Buy (Profit Trailing)");
                }
            }
            if (type == POSITION_TYPE_SELL) {
                // 현재가가 EMA보다 40포인트 위로 올라감
                if ((currentAsk - currentEma) >= exitDist) {
                    trade.PositionClose(ticket);
                    Print("Exit Sell (Profit Trailing)");
                }
            }
        }
        
        // 2. 손실 중일 때: VWAP 지지/저항 실패 시 손절 (Stop Loss)
        if (profitPoints < 0) {
             double vwapArr[]; ArraySetAsSeries(vwapArr,true);
             if(CopyBuffer(vwapHandle,0,0,1,vwapArr)<1) return;
             double vwapVal = vwapArr[0];
             
             if (type == POSITION_TYPE_BUY && currentBid < vwapVal - (exitDist/2)) { 
                 trade.PositionClose(ticket);
                 Print("StopLoss Buy: VWAP Broken");
             }
             if (type == POSITION_TYPE_SELL && currentAsk > vwapVal + (exitDist/2)) {
                 trade.PositionClose(ticket);
                 Print("StopLoss Sell: VWAP Broken");
             }
        }
    }
}

//+------------------------------------------------------------------+
//| 분할 청산 로직                                                   |
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