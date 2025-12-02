//+------------------------------------------------------------------+
//|                               Quantum Emperor benchmark v3.1     |
//|                               (One Shot One Kill Version)        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, p3pwp3p"
#property link "https://www.mql5.com"
#property version "3.10"
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

input group "Time & Control";
input int Box_Period_Hours = 8;  // 8시간 전 고점/저점 기준
input int TradeStartHour = 10;   // 10시부터 진입 시작
input int TradeEndHour = 16;     // [수정] 16시 이후 진입 금지 (칼퇴근)
input int MaxDailyCycles = 1;    // [수정] 하루 1회만 진입 (절제)

input group "Entry & Exit";
input string Ex_Pend = "23:59";
input double EntryBufferPip = 5.0;
input double MaxBoxSizePip = 150.0;
input double MinBoxSizePip = 5.0;

input group "Take Profit (Dynamic)";
input bool UseSpreadCorrection = true;
input bool UseATR_TP = true;
input double TP1_Ratio = 0.6;
input double TP2_Ratio = 1.2;
input double MinTP_Pips = 20.0;
input double FixedTP1_Points = 300.0;
input double FixedTP2_Points = 600.0;

input group "Trailing Stop";
input bool UseTrailingStop = true;
input double TrailingStart = 100.0;
input double TrailingStep = 12.0;
input double TrailingDist = 50.0;

input group "Grid & Recovery";
input bool EnableGrid = true;
input double GridStep = 100.0;
input double GridProfitTarget = 50.0;
input bool SmartRecovery = true;
input double SmartRecoveryMultiplier = 1.6;
input int SmartRecoveryMultiplierTimes = 3;

input group "Safety (Account Protect)";
input bool UseDailyLossLimit = true;  // [신규] 일일 손실 제한 사용
input double MaxDailyLossUSD = 50.0;  // [신규] 하루 $50 이상 잃으면 매매 중단
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
datetime lastCloseTime = 0;
double initialBalanceOfDay = 0;  // 하루 시작 잔고

// --- Prototypes ---
void updateInfoPanel();
void performDailyReset();
void checkOCO();
void manageGridOrders();
void manageGridExit();
void manageRecoveryOrders();
void manageTrailingStop();
bool hasRecoveryOrder(ulong parentTicket, double price);
void placeRecoveryOrder(ulong parentTicket, ENUM_POSITION_TYPE parentType,
                        double price, double volume);
void checkBoxEntry();
double getHighest(datetime start, datetime end);
double getLowest(datetime start, datetime end);
void closeAllPositions();
void deletePendingOrders();
double verifyVolume(double vol);
bool hasGridOrder(ENUM_POSITION_TYPE type);
int getDailyDealsCount();
bool checkDailyLossLimit();

// --- OnInit ---
int OnInit() {
    if (!symbolInfo.Name(Symbol())) return (INIT_FAILED);
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(Slippage);
    trade.SetTypeFilling(ORDER_FILLING_IOC);
    atrHandle = iATR(Symbol(), PERIOD_D1, 14);

    initialBalanceOfDay =
        AccountInfoDouble(ACCOUNT_BALANCE);  // 초기화 시 잔고 저장

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
    performDailyReset();  // 00:00에 변수 초기화
    checkOCO();

    // 1. 포지션 관리 (최우선)
    if (PositionsTotal() > 0) {
        manageGridExit();
        if (EnableGrid) manageGridOrders();
        if (SmartRecovery) manageRecoveryOrders();
        if (UseTrailingStop) manageTrailingStop();
        return;
    }

    // 2. 신규 진입 필터링

    // [필터 1] 시간 제한 (10:00 ~ 16:00)
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    if (dt.hour < TradeStartHour || dt.hour >= TradeEndHour) return;

    // [필터 2] 1일 N회 제한
    int dailyTrades = getDailyDealsCount();
    if (dailyTrades >= MaxDailyCycles) return;

    // [필터 3] 일일 손실 한도 체크
    if (UseDailyLossLimit && !checkDailyLossLimit()) return;

    // [필터 4] 중복 주문 방지
    if (OrdersTotal() > 0) return;

    // 3. 진입 실행
    checkBoxEntry();
}

// ──────────────────────────────────────────────────────────────────
// [수정] 박스 진입 (안전제일)
// ──────────────────────────────────────────────────────────────────
void checkBoxEntry() {
    datetime currentTime = TimeCurrent();
    string dateStr = TimeToString(currentTime, TIME_DATE);

    // Rolling Window: 8시간 전 ~ 현재
    datetime endTime = currentTime;
    datetime startTime = currentTime - (Box_Period_Hours * 3600);

    double high = getHighest(startTime, endTime);
    double low = getLowest(startTime, endTime);

    if (high == 0 || low == 0) return;

    double boxSizePip = (high - low) / symbolInfo.Point() / 10.0;

    if (boxSizePip > MaxBoxSizePip || boxSizePip < MinBoxSizePip) return;

    // TP/SL
    double dailyATR = 0;
    double atrBuffer[];
    ArraySetAsSeries(atrBuffer, true);
    if (CopyBuffer(atrHandle, 0, 1, 1, atrBuffer) > 0) dailyATR = atrBuffer[0];
    displayATR = dailyATR / symbolInfo.Point() / 10.0;

    double tp1_pts = (UseATR_TP) ? (dailyATR * TP1_Ratio)
                                 : (FixedTP1_Points * symbolInfo.Point());
    double tp2_pts = (UseATR_TP) ? (dailyATR * TP2_Ratio)
                                 : (FixedTP2_Points * symbolInfo.Point());

    double minTP = MinTP_Pips * 10 * symbolInfo.Point();
    if (tp1_pts < minTP) tp1_pts = minTP;
    if (tp2_pts < minTP) tp2_pts = minTP;

    double buffer = EntryBufferPip * 10 * symbolInfo.Point();
    double sl_base = StopLoss * symbolInfo.Point();

    double spread = 0;
    if (UseSpreadCorrection)
        spread = (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) *
                 symbolInfo.Point();

    double sl_real = sl_base + spread;
    double tp1_real = tp1_pts - spread;
    double tp2_real = tp2_pts - spread;

    double buyLvl = high + buffer;
    double sellLvl = low - buffer;

    Print("✅ 1-Day 1-Trade Entry! Box:", boxSizePip);

    // Buy Stop
    trade.BuyStop(Lot, buyLvl, Symbol(), buyLvl - sl_real, buyLvl + tp1_real,
                  ORDER_TIME_SPECIFIED, StringToTime(dateStr + " " + Ex_Pend),
                  EAComment + "-TP1");
    trade.BuyStop(Lot, buyLvl, Symbol(), buyLvl - sl_real, buyLvl + tp2_real,
                  ORDER_TIME_SPECIFIED, StringToTime(dateStr + " " + Ex_Pend),
                  EAComment + "-TP2");
    trade.BuyStop(Lot, buyLvl, Symbol(), buyLvl - sl_real, 0,
                  ORDER_TIME_SPECIFIED, StringToTime(dateStr + " " + Ex_Pend),
                  EAComment + "-Main");

    // Sell Stop
    trade.SellStop(Lot, sellLvl, Symbol(), sellLvl + sl_real,
                   sellLvl - tp1_real, ORDER_TIME_SPECIFIED,
                   StringToTime(dateStr + " " + Ex_Pend), EAComment + "-TP1");
    trade.SellStop(Lot, sellLvl, Symbol(), sellLvl + sl_real,
                   sellLvl - tp2_real, ORDER_TIME_SPECIFIED,
                   StringToTime(dateStr + " " + Ex_Pend), EAComment + "-TP2");
    trade.SellStop(Lot, sellLvl, Symbol(), sellLvl + sl_real, 0,
                   ORDER_TIME_SPECIFIED, StringToTime(dateStr + " " + Ex_Pend),
                   EAComment + "-Main");
}

// ──────────────────────────────────────────────────────────────────
// [NEW] 일일 손실 한도 체크
// ──────────────────────────────────────────────────────────────────
bool checkDailyLossLimit() {
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    // 오늘 시작 잔고보다 MaxDailyLossUSD 이상 까였으면 거래 중단
    if (currentBalance < initialBalanceOfDay - MaxDailyLossUSD) {
        return false;  // 거래 금지
    }
    return true;  // 거래 허용
}

// --- Helpers ---
void performDailyReset() {
    datetime today = iTime(Symbol(), PERIOD_D1, 0);
    static datetime lastDay = 0;
    if (lastDay != today) {
        lastDay = today;
        deletePendingOrders();
        lastCloseTime = 0;
        initialBalanceOfDay =
            AccountInfoDouble(ACCOUNT_BALANCE);  // 하루 시작 잔고 갱신
        Print("🔄 New Day! Balance Reset: ", initialBalanceOfDay);
    }
}
// (이하 기존 v3.0과 동일한 헬퍼 함수들 - checkOCO, manageGrid, manageRecovery
// 등) 코드가 너무 길어 생략된 부분은 v3.0의 하단 함수들을 그대로 사용하시면
// 됩니다. 핵심 변경 사항은 위쪽 Logic에 다 들어있습니다.

void checkOCO() {
    bool hasBuy = false;
    bool hasSell = false;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (positionInfo.SelectByIndex(i) &&
            positionInfo.Magic() == InpMagicNumber &&
            StringFind(positionInfo.Comment(), "Recovery") < 0) {
            if (positionInfo.PositionType() == POSITION_TYPE_BUY) hasBuy = true;
            if (positionInfo.PositionType() == POSITION_TYPE_SELL)
                hasSell = true;
        }
    }
    for (int i = OrdersTotal() - 1; i >= 0; i--) {
        if (orderInfo.SelectByIndex(i) && orderInfo.Magic() == InpMagicNumber &&
            StringFind(orderInfo.Comment(), "Recovery") < 0) {
            if (hasBuy && orderInfo.OrderType() == ORDER_TYPE_SELL_STOP)
                trade.OrderDelete(orderInfo.Ticket());
            if (hasSell && orderInfo.OrderType() == ORDER_TYPE_BUY_STOP)
                trade.OrderDelete(orderInfo.Ticket());
        }
    }
}
void updateInfoPanel() {
    if (!MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
    string info = StringFormat(
        "── [ QE Benchmark v3.1 (Safe) ] ──\nDaily Cycles: %d / %d\nLoss "
        "Limit: %s",
        getDailyDealsCount(), MaxDailyCycles,
        (checkDailyLossLimit() ? "OK" : "STOP"));
    Comment(info);
}
int getDailyDealsCount() {
    datetime startOfDay = iTime(Symbol(), PERIOD_D1, 0);
    datetime now = TimeCurrent();
    int count = 0;
    datetime lastTime = 0;
    if (HistorySelect(startOfDay, now)) {
        for (int i = 0; i < HistoryDealsTotal(); i++) {
            ulong ticket = HistoryDealGetTicket(i);
            if (HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber &&
                HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) {
                datetime dealTime =
                    (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
                if (dealTime > lastTime + 60) {
                    count++;
                    lastTime = dealTime;
                }
                if (dealTime > lastCloseTime) lastCloseTime = dealTime;
            }
        }
    }
    return count;
}
void manageGridOrders() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (positionInfo.SelectByIndex(i) &&
            positionInfo.Magic() == InpMagicNumber) {
            if (StringFind(positionInfo.Comment(), "Recovery") >= 0) continue;
            double entryPrice = positionInfo.PriceOpen();
            double currentPrice = positionInfo.PriceCurrent();
            ENUM_POSITION_TYPE type = positionInfo.PositionType();
            if (type == POSITION_TYPE_BUY) {
                if (currentPrice <=
                    entryPrice - (GridStep * symbolInfo.Point())) {
                    if (!hasGridOrder(type)) {
                        double sl = StopLoss * symbolInfo.Point();
                        trade.Buy(Lot, Symbol(), currentPrice,
                                  currentPrice - sl, 0, EAComment + "-Grid");
                    }
                }
            } else if (type == POSITION_TYPE_SELL) {
                if (currentPrice >=
                    entryPrice + (GridStep * symbolInfo.Point())) {
                    if (!hasGridOrder(type)) {
                        double sl = StopLoss * symbolInfo.Point();
                        trade.Sell(Lot, Symbol(), currentPrice,
                                   currentPrice + sl, 0, EAComment + "-Grid");
                    }
                }
            }
        }
    }
}
void manageGridExit() {
    if (PositionsTotal() < 2) return;
    double totalVolume = 0;
    double weightedPrice = 0;
    int buyCount = 0;
    int sellCount = 0;
    bool isRealGridSituation = false;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (positionInfo.SelectByIndex(i) &&
            positionInfo.Magic() == InpMagicNumber) {
            string comment = positionInfo.Comment();
            if (StringFind(comment, "-Grid") >= 0 ||
                StringFind(comment, "Recovery") >= 0)
                isRealGridSituation = true;
            totalVolume += positionInfo.Volume();
            weightedPrice += (positionInfo.PriceOpen() * positionInfo.Volume());
            if (positionInfo.PositionType() == POSITION_TYPE_BUY) buyCount++;
            if (positionInfo.PositionType() == POSITION_TYPE_SELL) sellCount++;
        }
    }
    if (!isRealGridSituation && PositionsTotal() <= 3) return;
    if (totalVolume == 0) return;
    double avgPrice = weightedPrice / totalVolume;
    double targetPoints = GridProfitTarget * symbolInfo.Point();
    if (buyCount > 0 && symbolInfo.Ask() >= avgPrice + targetPoints)
        closeAllPositions();
    if (sellCount > 0 && symbolInfo.Bid() <= avgPrice - targetPoints)
        closeAllPositions();
}
void manageRecoveryOrders() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (positionInfo.SelectByIndex(i) &&
            positionInfo.Magic() == InpMagicNumber) {
            double slPrice = positionInfo.StopLoss();
            if (slPrice > 0 &&
                !hasRecoveryOrder(positionInfo.Ticket(), slPrice))
                placeRecoveryOrder(positionInfo.Ticket(),
                                   positionInfo.PositionType(), slPrice,
                                   positionInfo.Volume());
        }
    }
}
void manageTrailingStop() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (positionInfo.SelectByIndex(i) &&
            positionInfo.Magic() == InpMagicNumber) {
            if (StringFind(positionInfo.Comment(), "-Grid") >= 0) continue;
            double currentPrice = positionInfo.PriceCurrent();
            double openPrice = positionInfo.PriceOpen();
            double currentSL = positionInfo.StopLoss();
            double point = symbolInfo.Point();
            if (positionInfo.PositionType() == POSITION_TYPE_BUY) {
                if (currentPrice - openPrice > TrailingStart * point) {
                    double newSL = currentPrice - (TrailingDist * point);
                    if (newSL > currentSL + (TrailingStep * point))
                        trade.PositionModify(positionInfo.Ticket(), newSL,
                                             positionInfo.TakeProfit());
                }
            } else if (positionInfo.PositionType() == POSITION_TYPE_SELL) {
                if (openPrice - currentPrice > TrailingStart * point) {
                    double newSL = currentPrice + (TrailingDist * point);
                    if (newSL < currentSL - (TrailingStep * point) ||
                        currentSL == 0)
                        trade.PositionModify(positionInfo.Ticket(), newSL,
                                             positionInfo.TakeProfit());
                }
            }
        }
    }
}
void placeRecoveryOrder(ulong t, ENUM_POSITION_TYPE p, double pr, double v) {
    double newLot = verifyVolume(v * SmartRecoveryMultiplier);
    double maxLot = verifyVolume(
        Lot * MathPow(SmartRecoveryMultiplier, SmartRecoveryMultiplierTimes));
    if (newLot > maxLot) return;
    double sl = StopLoss * symbolInfo.Point();
    string c = "Recovery for #" + (string)t;
    if (p == POSITION_TYPE_BUY)
        trade.SellStop(newLot, pr, Symbol(), pr - sl, 0, ORDER_TIME_GTC, 0, c);
    else
        trade.BuyStop(newLot, pr, Symbol(), pr + sl, 0, ORDER_TIME_GTC, 0, c);
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
//+------------------------------------------------------------------+