//+------------------------------------------------------------------+
//|                                        SupplyDemandStrategy.mq5  |
//|                                  Copyright 2025, Gemini AI Asst  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Gemini AI Asst"
#property link "https://www.mql5.com"
#property version "2.00"
#property strict

//+------------------------------------------------------------------+
//| Inputs (PascalCase)                                              |
//+------------------------------------------------------------------+
// --- 자금 관리 설정 ---
input bool InpUseMoneyManagement =
    true;                           // 자금 관리 사용 여부 (False면 고정 랏)
input double InpRiskPercent = 2.0;  // 리스크 퍼센트 (잔고 대비 손절 금액 %)
input double InpFixedLot = 0.1;     // 고정 랏 사이즈 (자금 관리 미사용 시)

// --- 전략 필터 설정 ---
input int InpCooldownBars = 3;      // 손절 후 진입 금지 캔들 수 (쿨타임)
input int InpMagicNumber = 123456;  // 매직 넘버

// --- 기존 전략 설정 ---
input int InpEmaPeriod = 50;            // 추세 확인용 EMA 기간
input double InpRiskRewardRatio = 1.5;  // 손익비 (1:1.5)
input int InpZoneLookBack = 50;         // 수요 존을 찾을 과거 캔들 범위
input double InpImpulseFactor = 1.5;    // 강한 상승 판단 기준 (ATR 대비 배수)

//+------------------------------------------------------------------+
//| Global Variables (camelCase)                                     |
//+------------------------------------------------------------------+
int emaHandle;             // EMA 핸들
int atrHandle;             // ATR 핸들
double emaBuffer[];        // EMA 데이터 버퍼
double atrBuffer[];        // ATR 데이터 버퍼
datetime lastBarTime = 0;  // 새로운 캔들 확인용

//+------------------------------------------------------------------+
//| Initialization Function                                          |
//+------------------------------------------------------------------+
int OnInit() {
    emaHandle = iMA(_Symbol, _Period, InpEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
    atrHandle = iATR(_Symbol, _Period, 14);

    if (emaHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE) {
        Print("지표 핸들 생성 실패");
        return (INIT_FAILED);
    }

    ArraySetAsSeries(emaBuffer, true);
    ArraySetAsSeries(atrBuffer, true);

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization Function                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    IndicatorRelease(emaHandle);
    IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Tick Function                                                    |
//+------------------------------------------------------------------+
void OnTick() {
    if (!isNewBar()) return;

    // [중요] 과거 데이터 조회 범위 수정 (Array Out of Range 방지)
    int requiredData = InpZoneLookBack + 5;

    if (CopyBuffer(emaHandle, 0, 0, requiredData, emaBuffer) < 0) return;
    if (CopyBuffer(atrHandle, 0, 0, requiredData, atrBuffer) < 0) return;

    // 1. 오픈된 포지션이 없고
    // 2. 쿨타임(연패 휴식) 중이 아닐 때만 로직 실행
    if (!checkOpenPositions() && !isCoolingDown()) {
        findAndTradeDemandZone();
    }
}

//+------------------------------------------------------------------+
//| Custom Functions (camelCase)                                     |
//+------------------------------------------------------------------+

bool isNewBar() {
    datetime currentBarTime = iTime(_Symbol, _Period, 0);
    if (lastBarTime != currentBarTime) {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}

bool checkOpenPositions() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket)) {
            if (PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
                PositionGetString(POSITION_SYMBOL) == _Symbol) {
                return true;
            }
        }
    }
    return false;
}

// [추가됨] 쿨타임 확인 함수: 마지막 거래가 손절이면 일정 시간 대기
bool isCoolingDown() {
    if (InpCooldownBars <= 0) return false;

    // 거래 내역 전체 조회 (최근 내역 위주로 최적화 가능)
    HistorySelect(0, TimeCurrent());
    int dealsTotal = HistoryDealsTotal();

    for (int i = dealsTotal - 1; i >= 0; i--) {
        ulong ticket = HistoryDealGetTicket(i);
        if (ticket > 0) {
            // 내 전략(매직넘버)과 심볼이 일치하고, '진입'이 아니라 '청산(Entry
            // Out)'인 딜 확인
            if (HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber &&
                HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol &&
                HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) {
                double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);

                // 마지막 청산이 손실인 경우에만 쿨타임 체크
                if (profit < 0) {
                    datetime dealTime =
                        (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
                    datetime timeLimit =
                        dealTime + (PeriodSeconds() * InpCooldownBars);

                    // 현재 시간이 아직 제한 시간(마지막 손절 시간 + N개 캔들)
                    // 안쪽이라면
                    if (TimeCurrent() < timeLimit) {
                        Print("쿨타임 적용 중: ", TimeToString(timeLimit),
                              " 까지 매매 금지");
                        return true;  // 쿨타임 중임
                    }
                }
                return false;  // 마지막 거래가 수익이었거나, 시간이 지났으면
                               // 통과
            }
        }
    }
    return false;  // 거래 내역 없음
}

// [추가됨] 리스크 기반 랏 사이즈 계산 함수
double getRiskLotSize(double entryPrice, double stopLossPrice) {
    if (!InpUseMoneyManagement) return InpFixedLot;

    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskMoney = balance * (InpRiskPercent / 100.0);  // 감당할 손실 금액

    double slPoints = MathAbs(entryPrice - stopLossPrice);
    if (slPoints == 0) return InpFixedLot;  // 에러 방지

    // 심볼의 1랏당 가치 계산
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

    if (tickValue == 0 || tickSize == 0) return InpFixedLot;

    // 공식: 랏 = 리스크금액 / (손절포인트 * 틱가치비율)
    // XAUUSD 등에서 TickValue 보정을 위해 표준 공식 사용
    double lossPerLot = (slPoints / tickSize) * tickValue;
    if (lossPerLot == 0) return InpFixedLot;

    double calculatedLot = riskMoney / lossPerLot;

    // 브로커의 최소/최대/단위 랏 조건에 맞춤
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    calculatedLot = MathFloor(calculatedLot / stepLot) * stepLot;

    if (calculatedLot < minLot)
        calculatedLot =
            minLot;  // 최소 랏보다는 커야 함 (리스크 초과 가능성 있음)
    if (calculatedLot > maxLot) calculatedLot = maxLot;

    return calculatedLot;
}

void findAndTradeDemandZone() {
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(_Symbol, _Period, 0, InpZoneLookBack, rates);

    if (copied < InpZoneLookBack) return;

    if (rates[0].close < emaBuffer[0]) return;  // 추세 필터

    for (int i = 2; i < InpZoneLookBack - 5; i++) {
        double bodySize = MathAbs(rates[i].close - rates[i].open);
        bool isBullish = rates[i].close > rates[i].open;

        if (isBullish && bodySize > (atrBuffer[i] * InpImpulseFactor)) {
            double zoneHigh = rates[i + 1].high;
            double zoneLow = rates[i + 1].low;

            // 되돌림 확인
            if (rates[0].low <= zoneHigh && rates[0].close >= zoneLow) {
                entryLong(zoneLow);
                return;
            }
        }
    }
}

void entryLong(double stopLossLevel) {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl = stopLossLevel;

    // 최소 스프레드 보정
    if (ask - sl < SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point) {
        sl = ask - (atrBuffer[0] * 0.5);
    }

    // [수정] 자금 관리가 적용된 랏 사이즈 계산
    double lotSize = getRiskLotSize(ask, sl);

    double risk = ask - sl;
    double tp = ask + (risk * InpRiskRewardRatio);

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = ORDER_TYPE_BUY;
    request.price = ask;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.magic = InpMagicNumber;
    request.comment = "Demand Zone Entry";
    request.type_filling = ORDER_FILLING_IOC;

    if (!OrderSend(request, result)) {
        Print("OrderSend error: ", GetLastError());
    }
}