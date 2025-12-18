//+------------------------------------------------------------------+
//|                                  Quantum Emperor benchmark.mq5   |
//|                                  Copyright 2025, p3pwp3p         |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, p3pwp3p"
#property link "https://www.mql5.com"
#property version "4.30"  // Pullback Logic Added
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
input string Box_Start_Time = "02:00";
input int TradeStartHour = 11;
input int TradeEndHour = 23;

input group "Stealth Entry Settings";
input int EntryCooldownSeconds = 3600;  // 1시간 쿨타임
input double EntryBufferPip = 20.0;
input double MaxBoxSizePip = 80.0;
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
bool isPullbackDetected = false;  // [신규] 눌림목 감지 플래그

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
void checkStealthEntry();
double getHighest(datetime start, datetime end);
double getLowest(datetime start, datetime end);
void closeAllPositions();
void deletePendingOrders();
double verifyVolume(double vol);
bool hasGridOrder(ENUM_POSITION_TYPE type);
int getDailyLockedDirection();
void checkOCO();  // [추가]

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

    // 1. 포지션 관리
    if (PositionsTotal() > 0) {
        manageGridExit();
        if (EnableGrid) manageGridOrders();
        if (SmartRecovery) manageRecoveryOrders();
        if (UseTrailingStop) manageTrailingStop();
    }

    // 2. 스텔스 진입 감시
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);

    // [핵심 수정] '>=' 가 아니라 '>' 를 사용
    // TradeStartHour가 12라면, 12시 59분까지는 대기하고 13시 00분부터 진입
    if (dt.hour > TradeStartHour && dt.hour < TradeEndHour) {
        if (TimeCurrent() - lastEntryTime > EntryCooldownSeconds) {
            if (PositionsTotal() < MaxOpenPositions) {
                checkStealthEntry();  // 여기서 박스 계산도 +1시간 해서 수행함
            }
        }
    }
}

// ──────────────────────────────────────────────────────────────────
// [수정] 스텔스 진입 (Pullback & Re-Breakout 적용)
// ──────────────────────────────────────────────────────────────────
void checkStealthEntry() {
    datetime currentTime = TimeCurrent();
    string dateStr = TimeToString(currentTime, TIME_DATE);

    datetime startTime = StringToTime(dateStr + " " + Box_Start_Time);

    // [핵심 수정] 박스 끝나는 시간을 '설정시간 + 1시간'으로 변경
    // 예: 12시 설정 -> 13:00까지의 고점/저점 계산 (12시 캔들 포함됨)
    datetime boxEndTime =
        StringToTime(StringFormat("%s %02d:00", dateStr, TradeStartHour)) +
        3600;

    // 아직 박스 마감 시간(13:00)이 안 됐으면 리턴
    if (currentTime < boxEndTime) return;

    // 1. 박스 계산 (02:00 ~ 13:00)
    if (dailyHigh == 0 || dailyLow == 0) {
        dailyHigh = getHighest(startTime, boxEndTime);
        dailyLow = getLowest(startTime, boxEndTime);
        if (dailyHigh == 0 || dailyLow == 0) return;

        double boxSize = (dailyHigh - dailyLow) / symbolInfo.Point() / 10.0;
        if (boxSize > MaxBoxSizePip || boxSize < MinBoxSizePip) {
            dailyHigh = -1;  // 필터 걸림
            return;
        }
    }

    if (dailyHigh == -1) return;

    int lockedDir = getDailyLockedDirection();
    double ask = symbolInfo.Ask();
    double bid = symbolInfo.Bid();
    double buffer = EntryBufferPip * 10 * symbolInfo.Point();

    // --- [재진입 눌림목 로직 유지] ---
    if (lockedDir != 0) {
        if (!isPullbackDetected) {
            if (lockedDir == 1 && bid < dailyHigh)
                isPullbackDetected = true;
            else if (lockedDir == -1 && ask > dailyLow)
                isPullbackDetected = true;
            return;
        }
    }

    // --- 진입 실행 ---
    if (ask > dailyHigh + buffer) {
        if (lockedDir != -1) executeEntry(ORDER_TYPE_BUY, ask);
    } else if (bid < dailyLow - buffer) {
        if (lockedDir != 1) executeEntry(ORDER_TYPE_SELL, bid);
    }
}

// 진입 실행
void executeEntry(ENUM_ORDER_TYPE type, double price) {
    double sl_base = StopLoss * symbolInfo.Point();
    double spread = (UseSpreadCorrection)
                        ? (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) *
                              symbolInfo.Point()
                        : 0;

    double sl_real = sl_base + spread;
    double tp1_real = (FixedTP1_Points * symbolInfo.Point()) - spread;
    double tp2_real = (FixedTP2_Points * symbolInfo.Point()) - spread;

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

    lastEntryTime = TimeCurrent();
}

// ──────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────
void performDailyReset() {
    datetime today = iTime(Symbol(), PERIOD_D1, 0);
    static datetime lastDay = 0;
    if (lastDay != today) {
        lastDay = today;
        dailyHigh = 0;
        dailyLow = 0;
        isPullbackDetected = false;  // [초기화] 새 날엔 리셋
        deletePendingOrders();
    }
}

int getDailyLockedDirection() {
    datetime startOfDay = iTime(Symbol(), PERIOD_D1, 0);
    datetime now = TimeCurrent();
    if (HistorySelect(startOfDay, now)) {
        int total = HistoryDealsTotal();
        for (int i = 0; i < total; i++) {
            ulong ticket = HistoryDealGetTicket(i);
            if (HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber &&
                HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN) {
                long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
                if (dealType == DEAL_TYPE_BUY) return 1;
                if (dealType == DEAL_TYPE_SELL) return -1;
            }
        }
    }
    return 0;
}

// (나머지 Grid, Recovery, Helper 함수들은 기존과 100% 동일하므로 생략하지 않고
// 모두 포함)
void updateInfoPanel() {
    if (!MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
    int dir = getDailyLockedDirection();
    string dirStr = (dir == 0) ? "None" : (dir == 1 ? "Buy Only" : "Sell Only");
    string pbStr = (isPullbackDetected ? "YES" : "No");
    string info = StringFormat(
        "── [ QE v4.3 Pullback ] ──\nLocked Dir: %s\nPullback Ready: "
        "%s\nPositions: %d",
        dirStr, pbStr, PositionsTotal());
    Comment(info);
}
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
            string comment = positionInfo.Comment();
            if (StringFind(comment, "-Grid") >= 0 ||
                StringFind(comment, "Recovery") >= 0)
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