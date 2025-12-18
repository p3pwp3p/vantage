//+------------------------------------------------------------------+
//|                                  Quantum Emperor benchmark.mq5   |
//|                                  Copyright 2025, p3pwp3p         |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, p3pwp3p"
#property link "https://www.mql5.com"
#property version "1.6"  // Stealth & Direction Lock
#property strict

#include <Trade\AccountInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\Trade.mqh>

// --- Inputs ---
input group "Basic Settings";
input bool Auto = true;
input int InpRiskLevel = 3;
input double Lot = 0.01;
input int InpMagicNumber = 777777;
input string EAComment = "QE v7.5";
input int MaxOpenPositions = 10;

input group "Time Settings";
input string Box_Start_Time = "02:00";  // 박스 시작
input int TradeStartHour = 11;          // 박스 끝 & 감시 시작
input int TradeEndHour = 23;            // 감시 종료

input group "Stealth Entry Settings";
input int EntryCooldownSeconds = 3600;  // 진입 후 1시간 휴식
input double EntryBufferPip = 20.0;     // 돌파 버퍼 (20포인트)
input double MaxBoxSizePip = 80.0;      // 박스 크기 제한
input double MinBoxSizePip = 5.0;

input group "Take Profit";
input bool UseSpreadCorrection = true;
input bool UseATR_TP = false;
input double TP1_Ratio = 0.6;
input double TP2_Ratio = 1.2;
input double MinTP_Pips = 20.0;
input double FixedTP1_Points = 600.0;
input double FixedTP2_Points = 600.0;

input group "Trailing Stop";
input bool UseTrailingStop = true;
input double TrailingStart = 50.0;
input double TrailingStep = 10.0;
input double TrailingDist = 20.0;

input group "Grid & Recovery";
input bool EnableGrid = true;
input double GridStep = 100.0;
input double GridProfitTarget = 50.0;
input bool SmartRecovery = true;
input double SmartRecoveryMultiplier = 1.6;
input int SmartRecoveryMultiplierTimes = 3;

input group "Filters";
input int TradeFriday = 1;
input int Slippage = 5;
input double StopLoss = 2500.0;

// --- Globals ---
CTrade trade;
CSymbolInfo symbolInfo;
CPositionInfo positionInfo;
COrderInfo orderInfo;
int atrHandle;
double displayATR;
datetime lastEntryTime = 0;
double dailyHigh = 0;
double dailyLow = 0;
datetime lastCalcDate = 0;

// --- Prototypes ---
void updateInfoPanel();
void performDailyReset();
void manageGridOrders();
void manageGridExit();
void manageRecoveryOrders();
void manageTrailingStop();
bool hasRecoveryOrder(ulong parentTicket, double price);
void placeRecoveryOrder(ulong parentTicket, ENUM_POSITION_TYPE parentType,
                        double price, double volume);
void checkStealthEntry();  // [NEW] 시장가 추적 진입
double getHighest(datetime start, datetime end);
double getLowest(datetime start, datetime end);
void closeAllPositions();
void deletePendingOrders();
double verifyVolume(double vol);
bool hasGridOrder(ENUM_POSITION_TYPE type);
int getDailyLockedDirection();  // [NEW] 오늘 방향 확인

// --- OnInit ---
int OnInit() {
    if (!symbolInfo.Name(Symbol())) return (INIT_FAILED);
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(Slippage);
    trade.SetTypeFilling(ORDER_FILLING_IOC);
    atrHandle = iATR(Symbol(), PERIOD_D1, 14);
    return (INIT_SUCCEEDED);
}
void OnDeinit(const int reason) {
    IndicatorRelease(atrHandle);
    Comment("");
}

// --- OnTick ---
void OnTick() {
    if (!Auto || !symbolInfo.RefreshRates()) return;

    updateInfoPanel();
    performDailyReset();

    // 1. 포지션 관리 (최우선)
    if (PositionsTotal() > 0) {
        manageGridExit();
        if (EnableGrid) manageGridOrders();
        if (SmartRecovery) manageRecoveryOrders();
        if (UseTrailingStop) manageTrailingStop();
    }

    // 2. 스텔스 진입 감시 (Pending Order 없음)
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);

    if (dt.hour >= TradeStartHour && dt.hour < TradeEndHour) {
        // 쿨타임 & 포지션 개수 체크
        if (TimeCurrent() - lastEntryTime > EntryCooldownSeconds) {
            if (PositionsTotal() < MaxOpenPositions) {
                checkStealthEntry();
            }
        }
    }
}

// ──────────────────────────────────────────────────────────────────
// [NEW] 스텔스 진입 로직 (Stop 주문 없이 가격 추적)
// ──────────────────────────────────────────────────────────────────
void checkStealthEntry() {
    datetime currentTime = TimeCurrent();
    string dateStr = TimeToString(currentTime, TIME_DATE);

    // 박스 시간: 02:00 ~ 11:00 (TradeStartHour)
    datetime startTime = StringToTime(dateStr + " " + Box_Start_Time);
    datetime endTime =
        StringToTime(StringFormat("%s %02d:00", dateStr, TradeStartHour));

    // 1. 박스 계산 (매 틱 계산하지 않고, 하루 한 번 계산 후 저장)
    // TradeStartHour(11시)가 지났고, 아직 계산 안 했거나 날짜가 바뀌었으면 계산
    if (currentTime >= endTime) {
        if (dailyHigh == 0 || dailyLow == 0) {
            dailyHigh = getHighest(startTime, endTime);
            dailyLow = getLowest(startTime, endTime);

            // 계산 실패 시 리턴
            if (dailyHigh == 0 || dailyLow == 0) return;

            double boxSize = (dailyHigh - dailyLow) / symbolInfo.Point() / 10.0;
            Print("📦 Box Calculated: ", boxSize, " Pips");

            // 박스 크기 필터 (조건 안 맞으면 dailyHigh를 -1로 만들어 오늘 진입
            // 차단)
            if (boxSize > MaxBoxSizePip || boxSize < MinBoxSizePip) {
                dailyHigh = -1;
                Print("⛔ Box Filter: Skipped Today.");
                return;
            }
        }
    } else {
        return;  // 아직 11시 전임
    }

    // 필터에 걸린 날은 패스
    if (dailyHigh == -1) return;

    // 2. 방향 고정 (Direction Lock) 확인
    // 0: 자유, 1: 매수만 가능, -1: 매도만 가능
    int lockedDir = getDailyLockedDirection();

    // 3. 현재가 확인
    double ask = symbolInfo.Ask();
    double bid = symbolInfo.Bid();
    double point = symbolInfo.Point();
    double buffer = EntryBufferPip * 10 * point;

    // 4. 진입 조건 체크

    // [Buy Condition] Ask가 High + Buffer 돌파
    if (ask > dailyHigh + buffer) {
        // 매도 락(-1)이 걸려있으면 진입 불가
        if (lockedDir != -1) {
            executeEntry(ORDER_TYPE_BUY, ask);
        }
    }

    // [Sell Condition] Bid가 Low - Buffer 돌파
    if (bid < dailyLow - buffer) {
        // 매수 락(1)이 걸려있으면 진입 불가
        if (lockedDir != 1) {
            executeEntry(ORDER_TYPE_SELL, bid);
        }
    }
}

// 진입 실행 함수 (3분할)
void executeEntry(ENUM_ORDER_TYPE type, double price) {
    double sl_base = StopLoss * symbolInfo.Point();
    double spread = (UseSpreadCorrection)
                        ? (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) *
                              symbolInfo.Point()
                        : 0;

    double sl_real = sl_base + spread;

    double tp1_p = FixedTP1_Points * symbolInfo.Point();
    double tp2_p = FixedTP2_Points * symbolInfo.Point();

    if (UseATR_TP) {
        // ATR 로직 필요 시 여기에 추가 (단, 성능을 위해 고정값 추천)
    }

    double tp1_real = tp1_p - spread;
    double tp2_real = tp2_p - spread;

    if (type == ORDER_TYPE_BUY) {
        trade.Buy(Lot, Symbol(), price, price - sl_real, price + tp1_real,
                  EAComment + "-TP1");
        trade.Buy(Lot, Symbol(), price, price - sl_real, price + tp2_real,
                  EAComment + "-TP2");
        trade.Buy(Lot, Symbol(), price, price - sl_real, 0,
                  EAComment + "-Main");
        Print("🚀 Stealth Buy Executed at ", price);
    } else {
        trade.Sell(Lot, Symbol(), price, price + sl_real, price - tp1_real,
                   EAComment + "-TP1");
        trade.Sell(Lot, Symbol(), price, price + sl_real, price - tp2_real,
                   EAComment + "-TP2");
        trade.Sell(Lot, Symbol(), price, price + sl_real, 0,
                   EAComment + "-Main");
        Print("🚀 Stealth Sell Executed at ", price);
    }

    lastEntryTime = TimeCurrent();  // 쿨타임 시작
}

// ──────────────────────────────────────────────────────────────────
// [NEW] 오늘 거래 방향 확인 (Lock)
// ──────────────────────────────────────────────────────────────────
int getDailyLockedDirection() {
    datetime startOfDay = iTime(Symbol(), PERIOD_D1, 0);
    datetime now = TimeCurrent();

    // 오늘 히스토리 조회
    if (HistorySelect(startOfDay, now)) {
        int total = HistoryDealsTotal();
        // 거래 내역이 하나라도 있으면 그 방향으로 락
        for (int i = 0; i < total; i++) {
            ulong ticket = HistoryDealGetTicket(i);
            if (HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber &&
                HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN) {
                long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
                if (dealType == DEAL_TYPE_BUY)
                    return 1;  // 오늘 이미 매수함 -> 매수만 허용 (또는 매도
                               // 금지)
                if (dealType == DEAL_TYPE_SELL)
                    return -1;  // 오늘 이미 매도함 -> 매도만 허용
            }
        }
    }
    return 0;  // 아직 거래 없음 -> 자유
}

// --- Helpers ---
void performDailyReset() {
    datetime today = iTime(Symbol(), PERIOD_D1, 0);
    static datetime lastDay = 0;
    if (lastDay != today) {
        lastDay = today;
        dailyHigh = 0;  // 박스 초기화
        dailyLow = 0;
        deletePendingOrders();  // 혹시 모를 잔여 주문 삭제
    }
}

void updateInfoPanel() {
    if (!MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
    int dir = getDailyLockedDirection();
    string dirStr = (dir == 0) ? "None" : (dir == 1 ? "Buy Only" : "Sell Only");
    string info = StringFormat(
        "── [ QE v4.2 Stealth ] ──\nTarget: High %.5f / Low %.5f\nLocked Dir: "
        "%s",
        dailyHigh, dailyLow, dirStr);
    Comment(info);
}

// (나머지 Grid, Recovery, Trailing, Helper 함수들은 v1.61과 동일하게 유지)
// 전체 코드 길이 제한으로 인해, 아래 함수들은 기존 코드를 그대로 사용해주세요.
// manageGridOrders, manageGridExit, manageRecoveryOrders, manageTrailingStop,
// placeRecoveryOrder, hasRecoveryOrder, getHighest, getLowest,
// closeAllPositions, deletePendingOrders, verifyVolume, hasGridOrder
// -------------------------------------------------------------
// [필수 포함 함수들 - 복사해서 아래에 붙여넣으세요]
void manageGridOrders() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (positionInfo.SelectByIndex(i) &&
            positionInfo.Magic() == InpMagicNumber) {
            if (StringFind(positionInfo.Comment(), "Recovery") >= 0) continue;
            double entry = positionInfo.PriceOpen();
            double cur = positionInfo.PriceCurrent();
            ENUM_POSITION_TYPE type = positionInfo.PositionType();
            if (type == POSITION_TYPE_BUY &&
                cur <= entry - (GridStep * symbolInfo.Point())) {
                if (!hasGridOrder(type)) {
                    double sl = StopLoss * symbolInfo.Point();
                    trade.Buy(Lot, Symbol(), cur, cur - sl, 0,
                              EAComment + "-Grid");
                }
            } else if (type == POSITION_TYPE_SELL &&
                       cur >= entry + (GridStep * symbolInfo.Point())) {
                if (!hasGridOrder(type)) {
                    double sl = StopLoss * symbolInfo.Point();
                    trade.Sell(Lot, Symbol(), cur, cur + sl, 0,
                               EAComment + "-Grid");
                }
            }
        }
    }
}
void manageGridExit() {
    if (PositionsTotal() < 2) return;
    double vol = 0;
    double wp = 0;
    int b = 0;
    int s = 0;
    bool g = false;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (positionInfo.SelectByIndex(i) &&
            positionInfo.Magic() == InpMagicNumber) {
            if (StringFind(positionInfo.Comment(), "-Grid") >= 0 ||
                StringFind(positionInfo.Comment(), "Recovery") >= 0)
                g = true;
            vol += positionInfo.Volume();
            wp += positionInfo.PriceOpen() * positionInfo.Volume();
            if (positionInfo.PositionType() == POSITION_TYPE_BUY)
                b++;
            else
                s++;
        }
    }
    if (!g && PositionsTotal() <= 3) return;
    if (vol == 0) return;
    double avg = wp / vol;
    double tgt = GridProfitTarget * symbolInfo.Point();
    if (b > 0 && symbolInfo.Ask() >= avg + tgt) closeAllPositions();
    if (s > 0 && symbolInfo.Bid() <= avg - tgt) closeAllPositions();
}
void manageRecoveryOrders() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (positionInfo.SelectByIndex(i) &&
            positionInfo.Magic() == InpMagicNumber) {
            double sl = positionInfo.StopLoss();
            if (sl > 0 && !hasRecoveryOrder(positionInfo.Ticket(), sl))
                placeRecoveryOrder(positionInfo.Ticket(),
                                   positionInfo.PositionType(), sl,
                                   positionInfo.Volume());
        }
    }
}
void manageTrailingStop() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (positionInfo.SelectByIndex(i) &&
            positionInfo.Magic() == InpMagicNumber &&
            StringFind(positionInfo.Comment(), "-Grid") < 0) {
            double cur = positionInfo.PriceCurrent();
            double op = positionInfo.PriceOpen();
            double sl = positionInfo.StopLoss();
            double pt = symbolInfo.Point();
            if (positionInfo.PositionType() == POSITION_TYPE_BUY) {
                if (cur - op > TrailingStart * pt) {
                    double nsl = cur - TrailingDist * pt;
                    if (nsl > sl + TrailingStep * pt)
                        trade.PositionModify(positionInfo.Ticket(), nsl,
                                             positionInfo.TakeProfit());
                }
            } else {
                if (op - cur > TrailingStart * pt) {
                    double nsl = cur + TrailingDist * pt;
                    if (nsl < sl - TrailingStep * pt || sl == 0)
                        trade.PositionModify(positionInfo.Ticket(), nsl,
                                             positionInfo.TakeProfit());
                }
            }
        }
    }
}
void placeRecoveryOrder(ulong t, ENUM_POSITION_TYPE p, double pr, double v) {
    double n = verifyVolume(v * SmartRecoveryMultiplier);
    double m = verifyVolume(
        Lot * MathPow(SmartRecoveryMultiplier, SmartRecoveryMultiplierTimes));
    if (n > m) return;
    double sl = StopLoss * symbolInfo.Point();
    string c = "Recovery for " + (string)t;
    if (p == POSITION_TYPE_BUY)
        trade.SellStop(n, pr, Symbol(), pr - sl, 0, ORDER_TIME_GTC, 0, c);
    else
        trade.BuyStop(n, pr, Symbol(), pr + sl, 0, ORDER_TIME_GTC, 0, c);
}
bool hasRecoveryOrder(ulong t, double p) {
    for (int i = OrdersTotal() - 1; i >= 0; i--) {
        if (orderInfo.SelectByIndex(i) &&
            MathAbs(orderInfo.PriceOpen() - p) < symbolInfo.Point() * 2)
            return true;
    }
    return false;
}
double getHighest(datetime s, datetime e) {
    double m = 0;
    MqlRates r[];
    ArraySetAsSeries(r, true);
    if (CopyRates(Symbol(), PERIOD_M1, s, e, r) > 0) {
        m = r[0].high;
        for (int i = 1; i < ArraySize(r); i++)
            if (r[i].high > m) m = r[i].high;
    }
    return m;
}
double getLowest(datetime s, datetime e) {
    double m = 99999;
    MqlRates r[];
    ArraySetAsSeries(r, true);
    if (CopyRates(Symbol(), PERIOD_M1, s, e, r) > 0) {
        m = r[0].low;
        for (int i = 1; i < ArraySize(r); i++)
            if (r[i].low < m) m = r[i].low;
    }
    return m;
}
void closeAllPositions() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (positionInfo.SelectByIndex(i) &&
            positionInfo.Magic() == InpMagicNumber)
            trade.PositionClose(positionInfo.Ticket());
    }
}
void deletePendingOrders() {
    for (int i = OrdersTotal() - 1; i >= 0; i--) {
        if (orderInfo.SelectByIndex(i) && orderInfo.Magic() == InpMagicNumber)
            trade.OrderDelete(orderInfo.Ticket());
    }
}
double verifyVolume(double v) {
    double s = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    if (s > 0) v = s * MathRound(v / s);
    return v;
}
bool hasGridOrder(ENUM_POSITION_TYPE t) {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (positionInfo.SelectByIndex(i) && positionInfo.PositionType() == t &&
            StringFind(positionInfo.Comment(), "-Grid") >= 0)
            return true;
    }
    return false;
}
void checkOCO() { /* 스텔스 모드라 불필요하지만 에러 방지용 빈 함수 */ }
//+------------------------------------------------------------------+