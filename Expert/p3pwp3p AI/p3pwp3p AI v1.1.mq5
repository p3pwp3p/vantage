//+------------------------------------------------------------------+
//|                                                    AI_Trader.mq5 |
//|                                  Copyright 2025, AI Benchmarking |
//+------------------------------------------------------------------+
#property copyright "AI Benchmarking"
#property version "1.0_Winner"

#include <Trade\Trade.mqh>

// ONNX 파일 내장
#resource "ForexAI.onnx" as const uchar ExtModel[]

// --- 사용자 입력 ---
input double MinConfidence = 0.6;
input double LotSize = 0.01;

// [수익의 핵심: 목표 및 방어 설정]
input int TpPoints = 2000;        // 2000 Point 익절
input int SlPoints = 1000;        // 1000 Point 손절
input int BE_Trigger = 300;       // 300 Point 수익 시 본절(BE) 발동
input int Trailing_Start = 1000;  // 1000 Point 수익 시 트레일링 시작
input int Trailing_Step = 400;

input int RsiPeriod = 14;
input int AtrPeriod = 14;
input int AdxPeriod = 14;

long onnxHandle;
int rsiHandle, atrHandle, adxHandle;
CTrade trade;
datetime lastBarTime = 0;

int OnInit() {
    onnxHandle = OnnxCreateFromBuffer(ExtModel, ONNX_DEFAULT);
    if (onnxHandle == INVALID_HANDLE) return (INIT_FAILED);

    // [핵심] 입력 4개 (RSI, ATR, ADX, Vol)
    long inputShape[] = {1, 4};
    if (!OnnxSetInputShape(onnxHandle, 0, inputShape)) return (INIT_FAILED);

    long outputShape0[] = {1};
    long outputShape1[] = {1, 2};
    OnnxSetOutputShape(onnxHandle, 0, outputShape0);
    OnnxSetOutputShape(onnxHandle, 1, outputShape1);

    rsiHandle = iRSI(_Symbol, _Period, RsiPeriod, PRICE_CLOSE);
    atrHandle = iATR(_Symbol, _Period, AtrPeriod);
    adxHandle = iADX(_Symbol, _Period, AdxPeriod);

    if (rsiHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE ||
        adxHandle == INVALID_HANDLE)
        return (INIT_FAILED);

    Print("AI Trader ($2700 Winner Version) Restored");
    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    if (onnxHandle != INVALID_HANDLE) OnnxRelease(onnxHandle);
    IndicatorRelease(rsiHandle);
    IndicatorRelease(atrHandle);
    IndicatorRelease(adxHandle);
}

void OnTick() {
    // 1. 청산 관리 (매 틱)
    ManageOpenPositions();

    if (!isNewBar()) return;
    if (PositionsTotal() > 0) return;

    double rsi[], atr[], adx[];
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(adx, true);

    if (CopyBuffer(rsiHandle, 0, 0, 2, rsi) < 2 ||
        CopyBuffer(atrHandle, 0, 0, 2, atr) < 2 ||
        CopyBuffer(adxHandle, 0, 0, 2, adx) < 2)
        return;

    // 입력 데이터 (4개)
    matrixf inputData(1, 4);
    inputData[0][0] = (float)rsi[1];
    inputData[0][1] = (float)atr[1];
    inputData[0][2] = (float)adx[1];
    inputData[0][3] = (float)MathAbs(iClose(_Symbol, _Period, 1) -
                                     iOpen(_Symbol, _Period, 1));

    long outLabel[1];
    matrixf outProbs(1, 2);

    if (!OnnxRun(onnxHandle, ONNX_NO_CONVERSION, inputData, outLabel, outProbs))
        return;

    float aiScore = outProbs[0][1];

    Comment("AI Score: ", DoubleToString(aiScore, 4));

    if (aiScore >= MinConfidence) {
        openBuyTrade();
    }
}

// --- 포인트 단위 청산 로직 ---
void ManageOpenPositions() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket)) {
            if (PositionGetString(POSITION_SYMBOL) == _Symbol) {
                double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double currentSl = PositionGetDouble(POSITION_SL);
                double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
                int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

                double profitPoints = (currentPrice - openPrice) / point;

                // 1. Trailing Stop
                if (profitPoints > Trailing_Start) {
                    double newSl = currentPrice - (Trailing_Step * point);
                    newSl = NormalizeDouble(newSl, digits);
                    if (newSl > currentSl && newSl > openPrice)
                        trade.PositionModify(ticket, newSl,
                                             PositionGetDouble(POSITION_TP));
                }
                // 2. Break Even (수익의 핵심)
                else if (profitPoints > BE_Trigger) {
                    if (currentSl < openPrice) {
                        double breakEvenLevel =
                            NormalizeDouble(openPrice + (10 * point), digits);
                        trade.PositionModify(ticket, breakEvenLevel,
                                             PositionGetDouble(POSITION_TP));
                    }
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

void openBuyTrade() {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    double sl = NormalizeDouble(ask - (SlPoints * _Point), digits);
    double tp = NormalizeDouble(ask + (TpPoints * _Point), digits);
    trade.Buy(LotSize, _Symbol, ask, sl, tp, "AI Trade");
}
//+------------------------------------------------------------------+