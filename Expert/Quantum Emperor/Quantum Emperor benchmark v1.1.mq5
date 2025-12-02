//+------------------------------------------------------------------+
//|                                  Quantum Emperor benchmark.mq5   |
//|                                  Copyright 2025, p3pwp3p         |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, p3pwp3p"
#property link "https://www.mql5.com"
#property version "1.1"
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

input group "Time & Rolling Box Settings";
input string Box_Start = "02:00";  // [수정] 윈도우 시작 기준 시간 (기간 계산용)
input int TradeStartHour =
    10;  // 진입 허용 시작 (이 시간 - Box_Start = 윈도우 크기)
input int TradeEndHour = 23;  // 진입 허용 종료
input bool UseDailyTrendFilter = false;

input group "Box Breakout Settings";
input string Ex_Pend = "23:59";
input double EntryBufferPip = 5.0;
input double MaxBoxSizePip = 150.0;
input double MinBoxSizePip = 5.0;

input group "Take Profit (Spread Corrected)";
input bool UseSpreadCorrection = true;
input bool UseATR_TP = true;
input double TP1_Ratio = 0.6;
input double TP2_Ratio = 1.2;
input double MinTP_Pips = 20.0;
input double FixedTP1_Points = 300.0;
input double FixedTP2_Points = 600.0;

input group "Trailing Stop Settings";
input bool UseTrailingStop = true;
input double TrailingStart = 100.0;
input double TrailingStep = 12.0;
input double TrailingDist = 50.0;

input group "Grid & Recovery Settings";
input bool EnableGrid = true;
input double GridStep = 100.0;
input double GridProfitTarget = 50.0;
input bool SmartRecovery = true;
input double SmartRecoveryMultiplier = 1.6;
input int SmartRecoveryMultiplierTimes = 3;

input group "Filters & Management";
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
datetime lastAnalysisTime = 0;
datetime lastEntryTime = 0; // 마지막 진입 시간 기록용

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
bool checkTimeFilters();
double getHighest(datetime start, datetime end);
double getLowest(datetime start, datetime end);
void closeAllPositions();
void deletePendingOrders();
double verifyVolume(double vol);
bool hasGridOrder(ENUM_POSITION_TYPE type);
int getWindowSeconds();  // [NEW] 윈도우 크기 계산 함수

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
    checkOCO();

    if (PositionsTotal() > 0) {
        manageGridExit();
        if (EnableGrid) manageGridOrders();
        if (SmartRecovery) manageRecoveryOrders();
        if (UseTrailingStop) manageTrailingStop();
    }

    // 재진입 (Rolling Box)
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);

    if (OrdersTotal() == 0 && PositionsTotal() == 0) {
        if (dt.hour >= TradeStartHour && dt.hour < TradeEndHour) {
            checkBoxEntry();
        }
    }
}

// ──────────────────────────────────────────────────────────────────
// [수정] Rolling Box Entry (이동 평균선처럼 이동하는 박스)
// ──────────────────────────────────────────────────────────────────
void checkBoxEntry() {
    if(TimeCurrent() < lastEntryTime + 3600) return;
    datetime currentTime = TimeCurrent();
    string dateStr = TimeToString(currentTime, TIME_DATE);

    // 1. 윈도우 크기 계산 (예: 10시 - 2시 = 8시간)
    int windowSeconds = getWindowSeconds();

    // 2. 박스 구간 설정 (현재 - 윈도우 ~ 현재)
    datetime startTime = currentTime - windowSeconds;
    datetime endTime = currentTime;

    // 3. 방향 필터
    int trendDirection = 0;
    if (UseDailyTrendFilter) {
        if (iClose(Symbol(), PERIOD_D1, 1) > iOpen(Symbol(), PERIOD_D1, 1))
            trendDirection = 1;
        else
            trendDirection = -1;
    }

    // 4. High/Low 계산 (최근 N시간)
    // 시간이 흐르면 과거의 높은 고점이 범위 밖으로 밀려나면서
    // 새로운 고점(Buy 타점)이 낮아질 수 있음 -> 사용자의 관찰과 일치!
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

    // 주문 전송
    if (trendDirection >= 0) {
        double buyLvl = high + buffer;
        trade.BuyStop(Lot, buyLvl, Symbol(), buyLvl - sl_real,
                      buyLvl + tp1_real, ORDER_TIME_SPECIFIED,
                      StringToTime(dateStr + " " + Ex_Pend),
                      EAComment + "-TP1");
        trade.BuyStop(Lot, buyLvl, Symbol(), buyLvl - sl_real,
                      buyLvl + tp2_real, ORDER_TIME_SPECIFIED,
                      StringToTime(dateStr + " " + Ex_Pend),
                      EAComment + "-TP2");
        trade.BuyStop(
            Lot, buyLvl, Symbol(), buyLvl - sl_real, 0, ORDER_TIME_SPECIFIED,
            StringToTime(dateStr + " " + Ex_Pend), EAComment + "-Main");
    }

    if (trendDirection <= 0) {
        double sellLvl = low - buffer;
        trade.SellStop(Lot, sellLvl, Symbol(), sellLvl + sl_real,
                       sellLvl - tp1_real, ORDER_TIME_SPECIFIED,
                       StringToTime(dateStr + " " + Ex_Pend),
                       EAComment + "-TP1");
        trade.SellStop(Lot, sellLvl, Symbol(), sellLvl + sl_real,
                       sellLvl - tp2_real, ORDER_TIME_SPECIFIED,
                       StringToTime(dateStr + " " + Ex_Pend),
                       EAComment + "-TP2");
        trade.SellStop(
            Lot, sellLvl, Symbol(), sellLvl + sl_real, 0, ORDER_TIME_SPECIFIED,
            StringToTime(dateStr + " " + Ex_Pend), EAComment + "-Main");
    }
}

// 윈도우 크기(초) 계산 헬퍼
int getWindowSeconds() {
    // 예: TradeStart(10) - BoxStart("02:00") = 8시간
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);  // 날짜만 가져오기용

    // TradeStart 시간
    datetime tradeStartTime = StringToTime(StringFormat(
        "%d.%02d.%02d %02d:00", dt.year, dt.mon, dt.day, TradeStartHour));

    // BoxStart 시간
    datetime boxStartTime = StringToTime(
        StringFormat("%d.%02d.%02d %s", dt.year, dt.mon, dt.day, Box_Start));

    // 차이 계산 (초 단위)
    long diff = tradeStartTime - boxStartTime;
    if (diff <= 0) diff = 3600 * 4;  // 기본값 4시간 (오류 방지)

    return (int)diff;
}

// --- Helpers (나머지 동일) ---
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
void manageGridExit() {
    if (PositionsTotal() < 2) return;
    double totalVolume = 0;
    double weightedPrice = 0;
    double totalProfit = 0;
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
            totalProfit += positionInfo.Profit() + positionInfo.Commission() +
                           positionInfo.Swap();
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
void performDailyReset() {
    if (lastAnalysisTime != iTime(Symbol(), PERIOD_D1, 0)) {
        lastAnalysisTime = iTime(Symbol(), PERIOD_D1, 0);
        deletePendingOrders();
    }
}
void updateInfoPanel() {
    if (!MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
    string info = StringFormat(
        "── [ QE Benchmark v1.7 (Rolling) ] ──\nPositions: %d\nWindow: %d "
        "hours",
        PositionsTotal(), (int)(getWindowSeconds() / 3600));
    Comment(info);
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