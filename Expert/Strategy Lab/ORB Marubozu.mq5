//+------------------------------------------------------------------+
//|                                   ORB_Marubozu_TrendFilter.mq5   |
//|                               Based on Trade with Pat Strategy   |
//+------------------------------------------------------------------+
#property copyright "Gemini"
#property link "https://www.mql5.com"
#property version "5.00"
#property strict

// --- 사용자 입력 (PascalCase) ---
input double LotSize = 0.1;          // 거래 랏 사이즈
input double RiskRewardRatio = 2.0;  // 손익비
input int MaxDailyTrades =
    2;  // 하루 최대 진입 횟수 (타임프레임이 커졌으므로 2회 추천)
input bool UseTrendFilter = true;  // ★ 추세 필터 사용 여부 (True/False)
input int TrendPeriod = 200;       // ★ 이동평균선 기간 (기본 200)
input int OrderExpirationMinutes =
    60;  // 미체결 주문 만료 시간 (봉이 커졌으므로 60분으로 늘림)
input int StartHour = 16;          // 오프닝 레인지 시작 시 (브로커 서버 시간)
input int StartMinute = 30;        // 오프닝 레인지 시작 분
input int EndHour = 16;            // 오프닝 레인지 종료 시
input int EndMinute = 45;          // 오프닝 레인지 종료 분
input double WickTolerance = 0.1;  // 마루보주 꼬리 허용 오차
input int MagicNumber = 123456;    // 매직 넘버

// --- 전역 변수 (camelCase) ---
double rangeHigh = 0;
double rangeLow = 0;
double rangeMidline = 0;
bool isRangeSet = false;
datetime lastTradeDate = 0;
datetime lastSignalTime = 0;
int dailyTradeCount = 0;
int maHandle = INVALID_HANDLE;  // MA 핸들

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    isRangeSet = false;
    lastSignalTime = 0;
    dailyTradeCount = 0;

    // 이동평균선 지표 핸들 생성 (EMA, Close 기준)
    if (UseTrendFilter) {
        maHandle =
            iMA(_Symbol, PERIOD_CURRENT, TrendPeriod, 0, MODE_EMA, PRICE_CLOSE);
        if (maHandle == INVALID_HANDLE) {
            Print("Failed to create MA handle");
            return (INIT_FAILED);
        }
    }

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    if (maHandle != INVALID_HANDLE) {
        IndicatorRelease(maHandle);
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    managePendingOrders();

    datetime currentTime = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(currentTime, dt);

    if (dt.day != timeToDay(lastTradeDate) && lastTradeDate != 0) {
        isRangeSet = false;
        rangeHigh = 0;
        rangeLow = 0;
        dailyTradeCount = 0;
    }

    if (!isRangeSet && isTimeAfterRange(dt)) {
        setOpeningRange();
    }

    if (isRangeSet && countActiveTrades() == 0 &&
        dailyTradeCount < MaxDailyTrades) {
        checkEntrySignal();
    }
}

// --- 사용자 정의 함수 ---

int timeToDay(datetime t) {
    MqlDateTime dt;
    TimeToStruct(t, dt);
    return dt.day;
}

bool isTimeAfterRange(MqlDateTime& dt) {
    if (dt.hour > EndHour) return true;
    if (dt.hour == EndHour && dt.min >= EndMinute) return true;
    return false;
}

void managePendingOrders() {
    for (int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if (OrderGetInteger(ORDER_MAGIC) == MagicNumber) {
            datetime setupTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
            if (TimeCurrent() > setupTime + (OrderExpirationMinutes * 60)) {
                MqlTradeRequest request;
                MqlTradeResult result;
                ZeroMemory(request);
                ZeroMemory(result);
                request.action = TRADE_ACTION_REMOVE;
                request.order = ticket;
                OrderSend(request, result);
            }
        }
    }
}

int countActiveTrades() {
    int count = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (PositionGetInteger(POSITION_MAGIC) == MagicNumber) count++;
    }
    for (int i = OrdersTotal() - 1; i >= 0; i--) {
        if (OrderGetInteger(ORDER_MAGIC) == MagicNumber) count++;
    }
    return count;
}

void setOpeningRange() {
    string dateStr = TimeToString(TimeCurrent(), TIME_DATE);
    datetime startDt = StringToTime(dateStr + " " + string(StartHour) + ":" +
                                    string(StartMinute));
    datetime endDt =
        StringToTime(dateStr + " " + string(EndHour) + ":" + string(EndMinute));

    // ★ 중요 변경: PERIOD_M1 -> PERIOD_CURRENT (사용자가 켠 차트의 시간대를
    // 따름)
    int startBar = iBarShift(_Symbol, PERIOD_CURRENT, startDt);
    int endBar = iBarShift(_Symbol, PERIOD_CURRENT, endDt);

    if (startBar == -1 || endBar == -1) return;

    double highest = -1.0;
    double lowest = 999999.0;

    for (int i = endBar; i <= startBar; i++) {
        double barHigh = iHigh(_Symbol, PERIOD_CURRENT, i);
        double barLow = iLow(_Symbol, PERIOD_CURRENT, i);
        if (barHigh > highest) highest = barHigh;
        if (barLow < lowest) lowest = barLow;
    }

    rangeHigh = highest;
    rangeLow = lowest;
    rangeMidline = (rangeHigh + rangeLow) / 2.0;
    isRangeSet = true;
}

bool isMarubozu(int index, int type) {
    double open = iOpen(_Symbol, PERIOD_CURRENT, index);
    double close = iClose(_Symbol, PERIOD_CURRENT, index);
    double high = iHigh(_Symbol, PERIOD_CURRENT, index);
    double low = iLow(_Symbol, PERIOD_CURRENT, index);
    double toleranceVal =
        WickTolerance * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

    if (type == 1) {
        if (close > open && MathAbs(open - low) <= toleranceVal) return true;
    } else if (type == -1) {
        if (open > close && MathAbs(high - open) <= toleranceVal) return true;
    }
    return false;
}

// 추세 확인 함수 (가격이 EMA 위에 있는지 아래에 있는지)
// return: 1=Uptrend(Buy Only), -1=Downtrend(Sell Only), 0=No Filter
int getTrendDirection() {
    if (!UseTrendFilter) return 0;

    double maVal[];
    ArraySetAsSeries(maVal, true);

    // 현재 캔들(0)은 진행 중이므로 확정된 직전 캔들(1) 기준 or 현재가 기준
    // 여기서는 현재가(Close) 기준으로 판단
    if (CopyBuffer(maHandle, 0, 1, 1, maVal) < 0) return 0;

    double currentClose = iClose(_Symbol, PERIOD_CURRENT, 1);

    if (currentClose > maVal[0]) return 1;   // 상승 추세
    if (currentClose < maVal[0]) return -1;  // 하락 추세

    return 0;
}

void checkEntrySignal() {
    double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    int trend = getTrendDirection();  // 추세 방향 확인

    // 1. 상방 돌파 (Buy Signal) -> 추세가 하락(-1)이면 진입 금지
    if (currentBid > rangeHigh && trend != -1) {
        for (int i = 1; i <= 5;
             i++) {  // 타임프레임이 커졌으므로 탐색 범위 축소 (10->5)
            datetime candleTime = iTime(_Symbol, PERIOD_CURRENT, i);
            if (candleTime == lastSignalTime) continue;

            if (isMarubozu(i, 1)) {
                double entryPrice = iOpen(_Symbol, PERIOD_CURRENT, i);
                if (currentAsk > entryPrice) {
                    double sl = rangeMidline;
                    // 5분/15분봉은 캔들이 크므로 SL 여유폭을 좀 더 둠
                    if (sl >= entryPrice)
                        sl = entryPrice -
                             (200 * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
                    double risk = entryPrice - sl;
                    double tp = entryPrice + (risk * RiskRewardRatio);

                    if (placeLimitOrder(ORDER_TYPE_BUY_LIMIT, entryPrice, sl,
                                        tp)) {
                        lastSignalTime = candleTime;
                        dailyTradeCount++;
                    }
                    return;
                }
            }
        }
    }

    // 2. 하방 돌파 (Sell Signal) -> 추세가 상승(1)이면 진입 금지
    if (currentAsk < rangeLow && trend != 1) {
        for (int i = 1; i <= 5; i++) {
            datetime candleTime = iTime(_Symbol, PERIOD_CURRENT, i);
            if (candleTime == lastSignalTime) continue;

            if (isMarubozu(i, -1)) {
                double entryPrice = iOpen(_Symbol, PERIOD_CURRENT, i);
                if (currentBid < entryPrice) {
                    double sl = rangeMidline;
                    if (sl <= entryPrice)
                        sl = entryPrice +
                             (200 * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
                    double risk = sl - entryPrice;
                    double tp = entryPrice - (risk * RiskRewardRatio);

                    if (placeLimitOrder(ORDER_TYPE_SELL_LIMIT, entryPrice, sl,
                                        tp)) {
                        lastSignalTime = candleTime;
                        dailyTradeCount++;
                    }
                    return;
                }
            }
        }
    }
}

bool placeLimitOrder(ENUM_ORDER_TYPE orderType, double price, double sl,
                     double tp) {
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_PENDING;
    request.symbol = _Symbol;
    request.volume = LotSize;
    request.type = orderType;
    request.price = price;
    request.sl = sl;
    request.tp = tp;
    request.magic = MagicNumber;
    request.deviation = 10;  // 허용 슬리피지도 약간 늘림
    request.type_filling = ORDER_FILLING_FOK;

    bool res = OrderSend(request, result);

    if (!res) {
        Print("OrderSend error: ", result.retcode);
        return false;
    } else {
        Print("Limit Order Placed. Ticket: ", result.order);
        lastTradeDate = TimeCurrent();
        Sleep(1000);
        return true;
    }
}