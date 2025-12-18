//+------------------------------------------------------------------+
//|                                  Quantum Emperor benchmark.mq5   |
//|                                  Copyright 2025, p3pwp3p         |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, p3pwp3p"
#property link "https://www.mql5.com"
#property version "5.01"  // Fix: Missing Inputs Restored
#property strict

#include <Trade\AccountInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\Trade.mqh>

// 리스크 설정 드롭박스
enum ENUM_RISK_MODE {
    RISK_1800_PER_001 = 0,  // $1800 당 0.01 Lot (Standard)
    RISK_3200_PER_001 = 1   // $3200 당 0.01 Lot (Safe)
};

// --- Inputs ---
// [복구됨] 필수 기초 설정
input group "Basic Settings";
input bool Auto = true;              // 자동매매 스위치
input int InpMagicNumber = 777777;   // 매직 넘버
input string EAComment = "QE v7.5";  // 거래 코멘트

input group "Risk Management (Auto Lot)";
input ENUM_RISK_MODE RiskSetting = RISK_1800_PER_001;  // 자금 관리 모드
input double MinLotSize = 0.01;                        // 최소 랏
input int MaxOpenPositions = 30;  // 최대 포지션 수 (7분할 고려)

input group "Time Settings";
input string Box_Start_Time = "02:00";
input int TradeStartHour = 11;
input int TradeEndHour = 23;

input group "Stealth Entry Settings";
input int EntryCooldownSeconds = 3600;  // 1시간 쿨타임
input double EntryBufferPip = 20.0;     // 20포인트 돌파
input double MaxBoxSizePip = 80.0;      // 80핍 제한 (엄격)
input double MinBoxSizePip = 10.0;

input group "7-Split Take Profit (Points)";
input bool UseSpreadCorrection = true;
input double TP_Pos1 = 200.0;
input double TP_Pos2 = 400.0;
input double TP_Pos3 = 600.0;
input double TP_Pos4 = 800.0;
input double TP_Pos5 = 1000.0;
input double TP_Pos6 = 1200.0;
input double TP_Pos7 = 1500.0;

input group "Trailing Stop";
input bool UseTrailingStop = true;
input double TrailingStart = 50.0;
input double TrailingStep = 10.0;
input double TrailingDist = 50.0;

input group "Grid & Recovery";
input bool EnableGrid = true;
input double GridStep = 100.0;
input double GridProfitTarget = 50.0;
input bool SmartRecovery = true;
input double SmartRecoveryMultiplier = 1.6;
input int SmartRecoveryMultiplierTimes = 3;

input group "Filters";
input bool UseDailyTrendFilter = true;
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
bool isPullbackDetected = false;

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
void checkOCO();
double calculateDynamicLot();
void execute7SplitEntry(ENUM_ORDER_TYPE type, double price);

// --- OnInit ---
int OnInit() {
    if (!MQLInfoInteger(MQL_TESTER)) {
        Alert("⛔ This EA is for Backtesting ONLY!");
        return (INIT_FAILED);
    }
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
    checkOCO();

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

    if (dt.hour >= TradeStartHour && dt.hour < TradeEndHour) {
        if (TimeCurrent() - lastEntryTime > EntryCooldownSeconds) {
            if (PositionsTotal() < MaxOpenPositions) {
                checkStealthEntry();
            }
        }
    }
}

// ──────────────────────────────────────────────────────────────────
// 랏 사이즈 자동 계산
// ──────────────────────────────────────────────────────────────────
double calculateDynamicLot() {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskDivisor = (RiskSetting == RISK_1800_PER_001) ? 1800.0 : 3200.0;

    double calculatedLot = MathFloor(balance / riskDivisor) * 0.01;

    if (calculatedLot < MinLotSize) calculatedLot = MinLotSize;
    return verifyVolume(calculatedLot);
}

// ──────────────────────────────────────────────────────────────────
// 스텔스 진입 (7분할 + Pullback)
// ──────────────────────────────────────────────────────────────────
void checkStealthEntry() {
    datetime currentTime = TimeCurrent();
    string dateStr = TimeToString(currentTime, TIME_DATE);

    datetime startTime = StringToTime(dateStr + " " + Box_Start_Time);
    datetime endTime =
        StringToTime(StringFormat("%s %02d:00", dateStr, TradeStartHour)) +
        3600;

    // 1. 박스 계산
    if (currentTime >= endTime) {
        if (dailyHigh == 0 || dailyLow == 0) {
            dailyHigh = getHighest(startTime, endTime);
            dailyLow = getLowest(startTime, endTime);
            if (dailyHigh == 0 || dailyLow == 0) return;

            double boxSize = (dailyHigh - dailyLow) / symbolInfo.Point() / 10.0;
            if (boxSize > MaxBoxSizePip || boxSize < MinBoxSizePip) {
                dailyHigh = -1;
                Print("⛔ Box Filter: Skipped. Size: ", boxSize);
                return;
            }
        }
    } else {
        return;
    }

    if (dailyHigh == -1) return;

    int lockedDir = getDailyLockedDirection();
    double ask = symbolInfo.Ask();
    double bid = symbolInfo.Bid();
    double buffer = EntryBufferPip * 10 * symbolInfo.Point();

    // 눌림목 로직
    if (lockedDir != 0) {
        if (!isPullbackDetected) {
            if (lockedDir == 1 && bid < dailyHigh)
                isPullbackDetected = true;
            else if (lockedDir == -1 && ask > dailyLow)
                isPullbackDetected = true;
            return;
        }
    }

    // 진입 실행
    if (ask > dailyHigh + buffer) {
        if (lockedDir != -1) {
            execute7SplitEntry(ORDER_TYPE_BUY, ask);
            isPullbackDetected = false;
        }
    } else if (bid < dailyLow - buffer) {
        if (lockedDir != 1) {
            execute7SplitEntry(ORDER_TYPE_SELL, bid);
            isPullbackDetected = false;
        }
    }
}

// 7분할 진입 실행
void execute7SplitEntry(ENUM_ORDER_TYPE type, double price) {
    double sl_base = StopLoss * symbolInfo.Point();
    double spread = (UseSpreadCorrection)
                        ? (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) *
                              symbolInfo.Point()
                        : 0;
    double sl_real = sl_base + spread;

    double lot = calculateDynamicLot();

    double tp_points[] = {TP_Pos1, TP_Pos2, TP_Pos3, TP_Pos4,
                          TP_Pos5, TP_Pos6, TP_Pos7};

    for (int i = 0; i < 7; i++) {
        double tp_val = tp_points[i] * symbolInfo.Point();
        double tp_real = tp_val - spread;
        if (tp_real < 50 * symbolInfo.Point())
            tp_real = 50 * symbolInfo.Point();

        string comment = StringFormat("%s-Pos%d", EAComment, i + 1);

        if (type == ORDER_TYPE_BUY) {
            trade.Buy(lot, Symbol(), price, price - sl_real, price + tp_real,
                      comment);
        } else {
            trade.Sell(lot, Symbol(), price, price + sl_real, price - tp_real,
                       comment);
        }
    }

    lastEntryTime = TimeCurrent();
    Print("🚀 7-Split Entry Executed! Lot: ", lot);
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
        isPullbackDetected = false;
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

void updateInfoPanel() {
    if (!MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
    int dir = getDailyLockedDirection();
    string dirStr = (dir == 0) ? "None" : (dir == 1 ? "Buy Only" : "Sell Only");
    string pbStr = (isPullbackDetected ? "YES" : "No");
    double nextLot = calculateDynamicLot();
    string info = StringFormat(
        "── [ QE v5.01 Fixed ] ──\nDir Lock: %s\nPullback: %s\nNext Lot: %.2f",
        dirStr, pbStr, nextLot);
    Comment(info);
}

// (하단 필수 함수들)
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
                    trade.Buy(calculateDynamicLot(), Symbol(), cur, cur - sl, 0,
                              EAComment + "-Grid");
                }
            } else if (type == POSITION_TYPE_SELL &&
                       cur >= entry + (GridStep * symbolInfo.Point())) {
                if (!hasGridOrder(type)) {
                    double sl = StopLoss * symbolInfo.Point();
                    trade.Sell(calculateDynamicLot(), Symbol(), cur, cur + sl,
                               0, EAComment + "-Grid");
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
            string c = positionInfo.Comment();
            if (StringFind(c, "-Grid") >= 0 || StringFind(c, "Recovery") >= 0)
                g = true;
            vol += positionInfo.Volume();
            wp += positionInfo.PriceOpen() * positionInfo.Volume();
            if (positionInfo.PositionType() == POSITION_TYPE_BUY)
                b++;
            else
                s++;
        }
    }
    if (!g && PositionsTotal() <= 7) return;
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
        calculateDynamicLot() *
        MathPow(SmartRecoveryMultiplier, SmartRecoveryMultiplierTimes));
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
void checkOCO() { /* Empty */ }
//+------------------------------------------------------------------+