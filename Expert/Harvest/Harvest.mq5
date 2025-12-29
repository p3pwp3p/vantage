//+------------------------------------------------------------------+
//|                                                    Harvest.mq5   |
//|                                  Copyright 2025, p3pwp3p         |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, p3pwp3p"
#property link "https://www.mql5.com"
#property version "1.0"
#property strict

#include <Arrays\ArrayString.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>

//--- Enums & Structures
enum ENUM_TRADE_DIR { DIR_NO_TRADE, DIR_BUY, DIR_SELL, DIR_BOTH };

struct PivotLevels {
    double p, r1, r2, r3, r4, s1, s2, s3, s4;
    double openPrice;
    double rangeR4S4;
    bool success;
    datetime dayStart;
    datetime dayEnd;
};

// --- [Common Settings] ---
input group "=== Common Settings ===";
input int BaseMagicNumber = 202403;
input double AccountMaxLots = 0.15;
input double SpreadLimitPoints = 40.0;
input double MinMarginLevel = 400.0;
input bool EnableSoundAlerts = false;
input bool IsOptimization = false;  // 최적화모드. true 설정 시 시각화 x 속도 up

// --- [Set 1] ---
input group "=== SET 1 Settings ===";
input string Set1_Symbol = "GBPAUD";
input bool Set1_EnableBuy = true;
input bool Set1_EnableSell = true;
input string Set1_SellLots = "0.02,0.02,0.03,0.04,0.05,0.06";
input string Set1_BuyLots = "0.02,0.02,0.03,0.04,0.05,0.06";
input double Set1_GridStep = 400.0;
input int Set1_MaxEntries = 9;
// Gaps
input double Set1_R1Gap = 90.0;
input double Set1_R2Gap = 90.0;
input double Set1_R3Gap = 70.0;
input double Set1_R4Gap = 0.0;
input double Set1_S1Gap = -90.0;
input double Set1_S2Gap = -90.0;
input double Set1_S3Gap = -70.0;
input double Set1_S4Gap = 0.0;
// Directions
input ENUM_TRADE_DIR Set1_Dir_R1 = DIR_SELL;
input ENUM_TRADE_DIR Set1_Dir_R2 = DIR_SELL;
input ENUM_TRADE_DIR Set1_Dir_R3 = DIR_SELL;
input ENUM_TRADE_DIR Set1_Dir_R4 = DIR_SELL;
input ENUM_TRADE_DIR Set1_Dir_S1 = DIR_BUY;
input ENUM_TRADE_DIR Set1_Dir_S2 = DIR_BUY;
input ENUM_TRADE_DIR Set1_Dir_S3 = DIR_BUY;
input ENUM_TRADE_DIR Set1_Dir_S4 = DIR_BUY;
// Close
input double Set1_Close_1st_Points = 200.0;
input double Set1_Close_USD_2 = 7.0;
input double Set1_Close_USD_3 = 12.0;
input double Set1_Close_USD_4 = 17.0;
input double Set1_Close_USD_5 = 23.0;
input double Set1_Close_USD_6 = 29.0;
input double Set1_Close_USD_7 = 35.0;
input double Set1_Close_USD_8 = 35.0;
input double Set1_Close_USD_9 = 35.0;
input double Set1_Close_USD_10 = 35.0;
input double Set1_Close_USD_11Plus = 35.0;
// Daily
input double Set1_DailyMinRange = 4000.0;
input ENUM_TRADE_DIR Set1_Daily_R1 = DIR_NO_TRADE;
input ENUM_TRADE_DIR Set1_Daily_R2 = DIR_SELL;
input ENUM_TRADE_DIR Set1_Daily_R3 = DIR_NO_TRADE;
input ENUM_TRADE_DIR Set1_Daily_R4 = DIR_SELL;
input ENUM_TRADE_DIR Set1_Daily_S1 = DIR_NO_TRADE;
input ENUM_TRADE_DIR Set1_Daily_S2 = DIR_BUY;
input ENUM_TRADE_DIR Set1_Daily_S3 = DIR_NO_TRADE;
input ENUM_TRADE_DIR Set1_Daily_S4 = DIR_BUY;
input double Set1_NextDayGap_Sell = 400.0;
input double Set1_NextDayGap_Buy = -400.0;

// --- [Set 2] ---
input group "=== SET 2 Settings ===";
input string Set2_Symbol = "";
input bool Set2_EnableBuy = true;
input bool Set2_EnableSell = true;
input string Set2_SellLots = "0.02,0.02,0.03,0.04,0.05,0.06";
input string Set2_BuyLots = "0.02,0.02,0.03,0.04,0.05,0.06";
input double Set2_GridStep = 400.0;
input int Set2_MaxEntries = 9;
// Gaps
input double Set2_R1Gap = 90.0;
input double Set2_R2Gap = 90.0;
input double Set2_R3Gap = 70.0;
input double Set2_R4Gap = 0.0;
input double Set2_S1Gap = -90.0;
input double Set2_S2Gap = -90.0;
input double Set2_S3Gap = -70.0;
input double Set2_S4Gap = 0.0;
// Directions
input ENUM_TRADE_DIR Set2_Dir_R1 = DIR_SELL;
input ENUM_TRADE_DIR Set2_Dir_R2 = DIR_SELL;
input ENUM_TRADE_DIR Set2_Dir_R3 = DIR_SELL;
input ENUM_TRADE_DIR Set2_Dir_R4 = DIR_SELL;
input ENUM_TRADE_DIR Set2_Dir_S1 = DIR_BUY;
input ENUM_TRADE_DIR Set2_Dir_S2 = DIR_BUY;
input ENUM_TRADE_DIR Set2_Dir_S3 = DIR_BUY;
input ENUM_TRADE_DIR Set2_Dir_S4 = DIR_BUY;
// Close
input double Set2_Close_1st_Points = 200.0;
input double Set2_Close_USD_2 = 7.0;
input double Set2_Close_USD_3 = 12.0;
input double Set2_Close_USD_4 = 17.0;
input double Set2_Close_USD_5 = 23.0;
input double Set2_Close_USD_6 = 29.0;
input double Set2_Close_USD_7 = 35.0;
input double Set2_Close_USD_8 = 35.0;
input double Set2_Close_USD_9 = 35.0;
input double Set2_Close_USD_10 = 35.0;
input double Set2_Close_USD_11Plus = 35.0;
// Daily
input double Set2_DailyMinRange = 4000.0;
input ENUM_TRADE_DIR Set2_Daily_R1 = DIR_NO_TRADE;
input ENUM_TRADE_DIR Set2_Daily_R2 = DIR_SELL;
input ENUM_TRADE_DIR Set2_Daily_R3 = DIR_NO_TRADE;
input ENUM_TRADE_DIR Set2_Daily_R4 = DIR_SELL;
input ENUM_TRADE_DIR Set2_Daily_S1 = DIR_NO_TRADE;
input ENUM_TRADE_DIR Set2_Daily_S2 = DIR_BUY;
input ENUM_TRADE_DIR Set2_Daily_S3 = DIR_NO_TRADE;
input ENUM_TRADE_DIR Set2_Daily_S4 = DIR_BUY;
input double Set2_NextDayGap_Sell = 400.0;
input double Set2_NextDayGap_Buy = -400.0;

// --- [Set 3] ---
input group "=== SET 3 Settings ===";
input string Set3_Symbol = "";
input bool Set3_EnableBuy = true;
input bool Set3_EnableSell = true;
input string Set3_SellLots = "0.02,0.02,0.03,0.04,0.05,0.06";
input string Set3_BuyLots = "0.02,0.02,0.03,0.04,0.05,0.06";
input double Set3_GridStep = 400.0;
input int Set3_MaxEntries = 9;
// Gaps
input double Set3_R1Gap = 90.0;
input double Set3_R2Gap = 90.0;
input double Set3_R3Gap = 70.0;
input double Set3_R4Gap = 0.0;
input double Set3_S1Gap = -90.0;
input double Set3_S2Gap = -90.0;
input double Set3_S3Gap = -70.0;
input double Set3_S4Gap = 0.0;
// Directions
input ENUM_TRADE_DIR Set3_Dir_R1 = DIR_SELL;
input ENUM_TRADE_DIR Set3_Dir_R2 = DIR_SELL;
input ENUM_TRADE_DIR Set3_Dir_R3 = DIR_SELL;
input ENUM_TRADE_DIR Set3_Dir_R4 = DIR_SELL;
input ENUM_TRADE_DIR Set3_Dir_S1 = DIR_BUY;
input ENUM_TRADE_DIR Set3_Dir_S2 = DIR_BUY;
input ENUM_TRADE_DIR Set3_Dir_S3 = DIR_BUY;
input ENUM_TRADE_DIR Set3_Dir_S4 = DIR_BUY;
// Close
input double Set3_Close_1st_Points = 200.0;
input double Set3_Close_USD_2 = 7.0;
input double Set3_Close_USD_3 = 12.0;
input double Set3_Close_USD_4 = 17.0;
input double Set3_Close_USD_5 = 23.0;
input double Set3_Close_USD_6 = 29.0;
input double Set3_Close_USD_7 = 35.0;
input double Set3_Close_USD_8 = 35.0;
input double Set3_Close_USD_9 = 35.0;
input double Set3_Close_USD_10 = 35.0;
input double Set3_Close_USD_11Plus = 35.0;
// Daily
input double Set3_DailyMinRange = 4000.0;
input ENUM_TRADE_DIR Set3_Daily_R1 = DIR_NO_TRADE;
input ENUM_TRADE_DIR Set3_Daily_R2 = DIR_SELL;
input ENUM_TRADE_DIR Set3_Daily_R3 = DIR_NO_TRADE;
input ENUM_TRADE_DIR Set3_Daily_R4 = DIR_SELL;
input ENUM_TRADE_DIR Set3_Daily_S1 = DIR_NO_TRADE;
input ENUM_TRADE_DIR Set3_Daily_S2 = DIR_BUY;
input ENUM_TRADE_DIR Set3_Daily_S3 = DIR_NO_TRADE;
input ENUM_TRADE_DIR Set3_Daily_S4 = DIR_BUY;
input double Set3_NextDayGap_Sell = 400.0;
input double Set3_NextDayGap_Buy = -400.0;

// --- Internal Structures ---
struct StrategySetting {
    string symbol;
    int magic;
    bool enBuy, enSell;
    double gridStep;
    int maxEntries;

    double gaps[8];
    ENUM_TRADE_DIR dirs[8];
    ENUM_TRADE_DIR dailyDirs[8];

    double close1stPoints;
    double dailyMinRange;
    double nextDayGapSell;
    double nextDayGapBuy;

    bool active;
};

struct StrategyState {
    double sellLots[];
    double buyLots[];
    double closeTargets[20];

    PivotLevels cachedPivots;
    int lastCalcDayOfYear;
    double lastBid;

    string prefix;
};

StrategySetting settings[3];
StrategyState states[3];
CTrade trade;
CPositionInfo posInfo;
const int SET_COUNT = 3;

// 전역 알림 관리 변수
const string GLOBAL_OBJ_NAME = "GlobalProfitInfo";

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // 전략 테스터가 아니면 실행 중단
    if (!MQLInfoInteger(MQL_TESTER)) {
        Alert(
            "이 EA는 전략 테스터(Backtest) 전용입니다. 라이브 차트에서는 "
            "실행할 수 없습니다.");
        return (INIT_FAILED);
    }
    // Load Set 1
    LoadSettings(0, Set1_Symbol, BaseMagicNumber, Set1_EnableBuy,
                 Set1_EnableSell, Set1_GridStep, Set1_MaxEntries, Set1_R1Gap,
                 Set1_R2Gap, Set1_R3Gap, Set1_R4Gap, Set1_S1Gap, Set1_S2Gap,
                 Set1_S3Gap, Set1_S4Gap, Set1_Dir_R1, Set1_Dir_R2, Set1_Dir_R3,
                 Set1_Dir_R4, Set1_Dir_S1, Set1_Dir_S2, Set1_Dir_S3,
                 Set1_Dir_S4, Set1_Close_1st_Points, Set1_DailyMinRange,
                 Set1_NextDayGap_Sell, Set1_NextDayGap_Buy, Set1_Daily_R1,
                 Set1_Daily_R2, Set1_Daily_R3, Set1_Daily_R4, Set1_Daily_S1,
                 Set1_Daily_S2, Set1_Daily_S3, Set1_Daily_S4);
    LoadState(0, Set1_SellLots, Set1_BuyLots, Set1_Close_USD_2,
              Set1_Close_USD_3, Set1_Close_USD_4, Set1_Close_USD_5,
              Set1_Close_USD_6, Set1_Close_USD_7, Set1_Close_USD_8,
              Set1_Close_USD_9, Set1_Close_USD_10, Set1_Close_USD_11Plus);

    // Load Set 2
    LoadSettings(1, Set2_Symbol, BaseMagicNumber + 1, Set2_EnableBuy,
                 Set2_EnableSell, Set2_GridStep, Set2_MaxEntries, Set2_R1Gap,
                 Set2_R2Gap, Set2_R3Gap, Set2_R4Gap, Set2_S1Gap, Set2_S2Gap,
                 Set2_S3Gap, Set2_S4Gap, Set2_Dir_R1, Set2_Dir_R2, Set2_Dir_R3,
                 Set2_Dir_R4, Set2_Dir_S1, Set2_Dir_S2, Set2_Dir_S3,
                 Set2_Dir_S4, Set2_Close_1st_Points, Set2_DailyMinRange,
                 Set2_NextDayGap_Sell, Set2_NextDayGap_Buy, Set2_Daily_R1,
                 Set2_Daily_R2, Set2_Daily_R3, Set2_Daily_R4, Set2_Daily_S1,
                 Set2_Daily_S2, Set2_Daily_S3, Set2_Daily_S4);
    LoadState(1, Set2_SellLots, Set2_BuyLots, Set2_Close_USD_2,
              Set2_Close_USD_3, Set2_Close_USD_4, Set2_Close_USD_5,
              Set2_Close_USD_6, Set2_Close_USD_7, Set2_Close_USD_8,
              Set2_Close_USD_9, Set2_Close_USD_10, Set2_Close_USD_11Plus);

    // Load Set 3
    LoadSettings(2, Set3_Symbol, BaseMagicNumber + 2, Set3_EnableBuy,
                 Set3_EnableSell, Set3_GridStep, Set3_MaxEntries, Set3_R1Gap,
                 Set3_R2Gap, Set3_R3Gap, Set3_R4Gap, Set3_S1Gap, Set3_S2Gap,
                 Set3_S3Gap, Set3_S4Gap, Set3_Dir_R1, Set3_Dir_R2, Set3_Dir_R3,
                 Set3_Dir_R4, Set3_Dir_S1, Set3_Dir_S2, Set3_Dir_S3,
                 Set3_Dir_S4, Set3_Close_1st_Points, Set3_DailyMinRange,
                 Set3_NextDayGap_Sell, Set3_NextDayGap_Buy, Set3_Daily_R1,
                 Set3_Daily_R2, Set3_Daily_R3, Set3_Daily_R4, Set3_Daily_S1,
                 Set3_Daily_S2, Set3_Daily_S3, Set3_Daily_S4);
    LoadState(2, Set3_SellLots, Set3_BuyLots, Set3_Close_USD_2,
              Set3_Close_USD_3, Set3_Close_USD_4, Set3_Close_USD_5,
              Set3_Close_USD_6, Set3_Close_USD_7, Set3_Close_USD_8,
              Set3_Close_USD_9, Set3_Close_USD_10, Set3_Close_USD_11Plus);

    // Pre-calc
    for (int i = 0; i < SET_COUNT; i++) {
        if (settings[i].active) CalculatePivotsForce(i);
    }
    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    for (int i = 0; i < SET_COUNT; i++) {
        if (settings[i].active) ObjectsDeleteAll(0, states[i].prefix);
    }
    // 전역 알림 삭제
    ObjectDelete(0, GLOBAL_OBJ_NAME);
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Main Loop                                                        |
//+------------------------------------------------------------------+
void OnTick() {
    if (MinMarginLevel > 0) {
        double currentMargin = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
        if (currentMargin > 0 && currentMargin < MinMarginLevel) return;
    }

    for (int i = 0; i < SET_COUNT; i++) {
        if (!settings[i].active) continue;

        double currentBid = SymbolInfoDouble(settings[i].symbol, SYMBOL_BID);
        double point = SymbolInfoDouble(settings[i].symbol, SYMBOL_POINT);

        if (MathAbs(currentBid - states[i].lastBid) < point) continue;
        states[i].lastBid = currentBid;

        trade.SetExpertMagicNumber(settings[i].magic);
        RunStrategy(i);
    }
}

//+------------------------------------------------------------------+
//| Core Logic                                                       |
//+------------------------------------------------------------------+
void RunStrategy(int idx) {
    string symbol = settings[idx].symbol;
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    if (point == 0) return;

    datetime currentTime = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(currentTime, dt);

    if (dt.day_of_year != states[idx].lastCalcDayOfYear ||
        !states[idx].cachedPivots.success) {
        PivotLevels newPivots = getPivotLevels(symbol, point);
        if (newPivots.success) {
            states[idx].cachedPivots = newPivots;
            states[idx].lastCalcDayOfYear = dt.day_of_year;
            if (symbol == _Symbol)
                updateChartGraphics(idx, states[idx].cachedPivots, true);
        } else {
            return;
        }
    }
    if (!states[idx].cachedPivots.success) return;

    bool isDailyMode =
        (states[idx].cachedPivots.rangeR4S4 >= settings[idx].dailyMinRange);

    if (symbol == _Symbol)
        updateChartGraphics(idx, states[idx].cachedPivots, false, isDailyMode);

    checkCloseLogic(idx);

    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    if (ask > 0 && bid > 0) {
        checkEntry(idx, states[idx].cachedPivots, isDailyMode, ask, bid, point);
    }
}

//+------------------------------------------------------------------+
//| Helpers for Loading                                              |
//+------------------------------------------------------------------+
void LoadSettings(int i, string sym, int magic, bool enBuy, bool enSell,
                  double step, int maxE, double r1g, double r2g, double r3g,
                  double r4g, double s1g, double s2g, double s3g, double s4g,
                  ENUM_TRADE_DIR dr1, ENUM_TRADE_DIR dr2, ENUM_TRADE_DIR dr3,
                  ENUM_TRADE_DIR dr4, ENUM_TRADE_DIR ds1, ENUM_TRADE_DIR ds2,
                  ENUM_TRADE_DIR ds3, ENUM_TRADE_DIR ds4, double close1st,
                  double dailyMin, double gapSell, double gapBuy,
                  ENUM_TRADE_DIR d_r1, ENUM_TRADE_DIR d_r2, ENUM_TRADE_DIR d_r3,
                  ENUM_TRADE_DIR d_r4, ENUM_TRADE_DIR d_s1, ENUM_TRADE_DIR d_s2,
                  ENUM_TRADE_DIR d_s3, ENUM_TRADE_DIR d_s4) {
    settings[i].symbol = sym;
    settings[i].active = (sym != "" && sym != NULL);
    settings[i].magic = magic;
    settings[i].enBuy = enBuy;
    settings[i].enSell = enSell;
    settings[i].gridStep = step;
    settings[i].maxEntries = maxE;

    settings[i].gaps[0] = r1g;
    settings[i].gaps[1] = r2g;
    settings[i].gaps[2] = r3g;
    settings[i].gaps[3] = r4g;
    settings[i].gaps[4] = s1g;
    settings[i].gaps[5] = s2g;
    settings[i].gaps[6] = s3g;
    settings[i].gaps[7] = s4g;

    settings[i].dirs[0] = dr1;
    settings[i].dirs[1] = dr2;
    settings[i].dirs[2] = dr3;
    settings[i].dirs[3] = dr4;
    settings[i].dirs[4] = ds1;
    settings[i].dirs[5] = ds2;
    settings[i].dirs[6] = ds3;
    settings[i].dirs[7] = ds4;

    settings[i].close1stPoints = close1st;
    settings[i].dailyMinRange = dailyMin;
    settings[i].nextDayGapSell = gapSell;
    settings[i].nextDayGapBuy = gapBuy;

    settings[i].dailyDirs[0] = d_r1;
    settings[i].dailyDirs[1] = d_r2;
    settings[i].dailyDirs[2] = d_r3;
    settings[i].dailyDirs[3] = d_r4;
    settings[i].dailyDirs[4] = d_s1;
    settings[i].dailyDirs[5] = d_s2;
    settings[i].dailyDirs[6] = d_s3;
    settings[i].dailyDirs[7] = d_s4;
}

void LoadState(int i, string sLots, string bLots, double c2, double c3,
               double c4, double c5, double c6, double c7, double c8, double c9,
               double c10, double c11) {
    parseStringToArray(sLots, states[i].sellLots);
    parseStringToArray(bLots, states[i].buyLots);

    states[i].closeTargets[0] = 0;
    states[i].closeTargets[1] = 0;
    states[i].closeTargets[2] = c2;
    states[i].closeTargets[3] = c3;
    states[i].closeTargets[4] = c4;
    states[i].closeTargets[5] = c5;
    states[i].closeTargets[6] = c6;
    states[i].closeTargets[7] = c7;
    states[i].closeTargets[8] = c8;
    states[i].closeTargets[9] = c9;
    states[i].closeTargets[10] = c10;
    for (int k = 11; k < 20; k++) states[i].closeTargets[k] = c11;

    states[i].lastCalcDayOfYear = -1;
    states[i].lastBid = 0;
    states[i].prefix = "FP_S" + IntegerToString(i + 1) + "_";
}

void parseStringToArray(string str, double& dst[]) {
    string elements[];
    int total = StringSplit(str, ',', elements);
    ArrayResize(dst, total);
    for (int i = 0; i < total; i++) dst[i] = StringToDouble(elements[i]);
}

//+------------------------------------------------------------------+
//| Core Logic Functions                                             |
//+------------------------------------------------------------------+
void checkEntry(int idx, PivotLevels& pv, bool isDailyMode, double ask,
                double bid, double point) {
    int buyCount = countPositions(idx, POSITION_TYPE_BUY);
    int sellCount = countPositions(idx, POSITION_TYPE_SELL);

    if (buyCount >= settings[idx].maxEntries &&
        sellCount >= settings[idx].maxEntries)
        return;

    for (int k = 0; k < 4; k++) {
        double level = (k == 0)   ? pv.r1
                       : (k == 1) ? pv.r2
                       : (k == 2) ? pv.r3
                                  : pv.r4;
        ENUM_TRADE_DIR d =
            isDailyMode ? settings[idx].dailyDirs[k] : settings[idx].dirs[k];
        processLevel(idx, level, settings[idx].gaps[k], point, d, buyCount,
                     sellCount, ask, bid);
    }
    for (int k = 4; k < 8; k++) {
        double level = (k == 4)   ? pv.s1
                       : (k == 5) ? pv.s2
                       : (k == 6) ? pv.s3
                                  : pv.s4;
        ENUM_TRADE_DIR d =
            isDailyMode ? settings[idx].dailyDirs[k] : settings[idx].dirs[k];
        processLevel(idx, level, settings[idx].gaps[k], point, d, buyCount,
                     sellCount, ask, bid);
    }
}

void processLevel(int idx, double levelPrice, double alphaPoint, double point,
                  ENUM_TRADE_DIR dirConfig, int bCnt, int sCnt, double ask,
                  double bid) {
    if (dirConfig == DIR_NO_TRADE) return;
    double targetPrice = levelPrice + (alphaPoint * point);

    if (MathAbs(ask - targetPrice) < SpreadLimitPoints * point ||
        MathAbs(bid - targetPrice) < SpreadLimitPoints * point) {
        // BUY
        if ((dirConfig == DIR_BUY || dirConfig == DIR_BOTH) &&
            settings[idx].enBuy && bCnt < settings[idx].maxEntries) {
            if (bCnt > 0 && !checkGridDistance(idx, POSITION_TYPE_BUY, ask,
                                               settings[idx].gridStep * point))
                return;
            if (!checkNextDayGap(idx, POSITION_TYPE_BUY, ask, point)) return;
            double lot = getLotSize(idx, bCnt, POSITION_TYPE_BUY);
            trade.Buy(lot, settings[idx].symbol, 0, 0, 0,
                      "PG_S" + IntegerToString(idx + 1));
            if (EnableSoundAlerts) PlaySound("ok.wav");
        }
        // SELL
        if ((dirConfig == DIR_SELL || dirConfig == DIR_BOTH) &&
            settings[idx].enSell && sCnt < settings[idx].maxEntries) {
            if (sCnt > 0 && !checkGridDistance(idx, POSITION_TYPE_SELL, bid,
                                               settings[idx].gridStep * point))
                return;
            if (!checkNextDayGap(idx, POSITION_TYPE_SELL, bid, point)) return;
            double lot = getLotSize(idx, sCnt, POSITION_TYPE_SELL);
            trade.Sell(lot, settings[idx].symbol, 0, 0, 0,
                       "PG_S" + IntegerToString(idx + 1));
            if (EnableSoundAlerts) PlaySound("ok.wav");
        }
    }
}

//+------------------------------------------------------------------+
//| Position Management                                              |
//+------------------------------------------------------------------+
void checkCloseLogic(int idx) {
    double totalBuyProfit = 0, totalSellProfit = 0;
    int bCnt = 0, sCnt = 0;
    string sym = settings[idx].symbol;
    int mag = settings[idx].magic;
    double point = SymbolInfoDouble(sym, SYMBOL_POINT);
    double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
    double bid = SymbolInfoDouble(sym, SYMBOL_BID);

    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (posInfo.SelectByIndex(i)) {
            if (posInfo.Symbol() == sym && posInfo.Magic() == mag) {
                double profit =
                    posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
                if (posInfo.PositionType() == POSITION_TYPE_BUY) {
                    totalBuyProfit += profit;
                    bCnt++;
                } else {
                    totalSellProfit += profit;
                    sCnt++;
                }
            }
        }
    }

    // Buy Close
    if (bCnt == 1) {
        if (settings[idx].close1stPoints > 0) {
            for (int i = PositionsTotal() - 1; i >= 0; i--) {
                if (posInfo.SelectByIndex(i) && posInfo.Symbol() == sym &&
                    posInfo.Magic() == mag &&
                    posInfo.PositionType() == POSITION_TYPE_BUY) {
                    if (bid >= posInfo.PriceOpen() +
                                   (settings[idx].close1stPoints * point)) {
                        displayProfitMessage(idx, "BUY", bCnt,
                                             posInfo.Profit() + posInfo.Swap() +
                                                 posInfo.Commission());
                        trade.PositionClose(posInfo.Ticket());
                        if (EnableSoundAlerts) PlaySound("expert.wav");
                    }
                    break;
                }
            }
        }
    } else if (bCnt >= 2) {
        double target = states[idx].closeTargets[bCnt < 20 ? bCnt : 19];
        if (totalBuyProfit >= target) {
            displayProfitMessage(idx, "BUY", bCnt, totalBuyProfit);
            closeAllPositions(idx, POSITION_TYPE_BUY);
        }
    }

    // Sell Close
    if (sCnt == 1) {
        if (settings[idx].close1stPoints > 0) {
            for (int i = PositionsTotal() - 1; i >= 0; i--) {
                if (posInfo.SelectByIndex(i) && posInfo.Symbol() == sym &&
                    posInfo.Magic() == mag &&
                    posInfo.PositionType() == POSITION_TYPE_SELL) {
                    if (ask <= posInfo.PriceOpen() -
                                   (settings[idx].close1stPoints * point)) {
                        displayProfitMessage(idx, "SELL", sCnt,
                                             posInfo.Profit() + posInfo.Swap() +
                                                 posInfo.Commission());
                        trade.PositionClose(posInfo.Ticket());
                        if (EnableSoundAlerts) PlaySound("expert.wav");
                    }
                    break;
                }
            }
        }
    } else if (sCnt >= 2) {
        double target = states[idx].closeTargets[sCnt < 20 ? sCnt : 19];
        if (totalSellProfit >= target) {
            displayProfitMessage(idx, "SELL", sCnt, totalSellProfit);
            closeAllPositions(idx, POSITION_TYPE_SELL);
        }
    }
}

void closeAllPositions(int idx, ENUM_POSITION_TYPE type) {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (posInfo.SelectByIndex(i)) {
            if (posInfo.Symbol() == settings[idx].symbol &&
                posInfo.Magic() == settings[idx].magic &&
                posInfo.PositionType() == type) {
                trade.PositionClose(posInfo.Ticket());
            }
        }
    }
    if (EnableSoundAlerts) PlaySound("expert.wav");
}

int countPositions(int idx, ENUM_POSITION_TYPE type) {
    int cnt = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (posInfo.SelectByIndex(i)) {
            if (posInfo.Symbol() == settings[idx].symbol &&
                posInfo.Magic() == settings[idx].magic &&
                posInfo.PositionType() == type)
                cnt++;
        }
    }
    return cnt;
}

double getLotSize(int idx, int stepIdx, ENUM_POSITION_TYPE type) {
    if (type == POSITION_TYPE_BUY)
        return (stepIdx < ArraySize(states[idx].buyLots))
                   ? states[idx].buyLots[stepIdx]
                   : states[idx].buyLots[ArraySize(states[idx].buyLots) - 1];
    else
        return (stepIdx < ArraySize(states[idx].sellLots))
                   ? states[idx].sellLots[stepIdx]
                   : states[idx].sellLots[ArraySize(states[idx].sellLots) - 1];
}

bool checkGridDistance(int idx, ENUM_POSITION_TYPE type, double currentPrice,
                       double minDist) {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (posInfo.SelectByIndex(i)) {
            if (posInfo.Symbol() == settings[idx].symbol &&
                posInfo.Magic() == settings[idx].magic &&
                posInfo.PositionType() == type) {
                if (MathAbs(currentPrice - posInfo.PriceOpen()) < minDist)
                    return false;
            }
        }
    }
    return true;
}

bool checkNextDayGap(int idx, ENUM_POSITION_TYPE type, double currentPrice,
                     double point) {
    double lastEntryPrice = 0.0;
    datetime lastEntryTime = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (posInfo.SelectByIndex(i)) {
            if (posInfo.Symbol() == settings[idx].symbol &&
                posInfo.Magic() == settings[idx].magic &&
                posInfo.PositionType() == type) {
                if (posInfo.Time() > lastEntryTime) {
                    lastEntryTime = posInfo.Time();
                    lastEntryPrice = posInfo.PriceOpen();
                }
            }
        }
    }
    if (lastEntryPrice == 0.0) return true;
    double diffPoints = (currentPrice - lastEntryPrice) / point;
    if (type == POSITION_TYPE_BUY && diffPoints < settings[idx].nextDayGapBuy)
        return false;
    if (type == POSITION_TYPE_SELL && diffPoints < settings[idx].nextDayGapSell)
        return false;
    return true;
}

//+------------------------------------------------------------------+
//| Data & Graphics                                                  |
//+------------------------------------------------------------------+
void CalculatePivotsForce(int idx) {
    string symbol = settings[idx].symbol;
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    if (point == 0) return;
    states[idx].cachedPivots = getPivotLevels(symbol, point);
    if (states[idx].cachedPivots.success) {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        states[idx].lastCalcDayOfYear = dt.day_of_year;
    }
}

PivotLevels getPivotLevels(string symbol, double point) {
    PivotLevels pv;
    pv.success = false;
    double open[], high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open, true);

    ResetLastError();
    if (CopyHigh(symbol, PERIOD_D1, 1, 1, high) < 1) return pv;
    if (CopyLow(symbol, PERIOD_D1, 1, 1, low) < 1) return pv;
    if (CopyClose(symbol, PERIOD_D1, 1, 1, close) < 1) return pv;
    if (CopyOpen(symbol, PERIOD_D1, 0, 1, open) < 1) return pv;
    datetime times[];
    ArraySetAsSeries(times, true);
    if (CopyTime(symbol, PERIOD_D1, 0, 1, times) < 1) return pv;

    pv.openPrice = open[0];
    pv.dayStart = times[0];
    pv.dayEnd = times[0] + PeriodSeconds(PERIOD_D1);
    double H = high[0];
    double L = low[0];
    double C = close[0];
    pv.p = (H + L + C) / 3.0;
    pv.r1 = (2 * pv.p) - L;
    pv.s1 = (2 * pv.p) - H;
    pv.r2 = pv.p + (H - L);
    pv.s2 = pv.p - (H - L);
    pv.r3 = H + 2 * (pv.p - L);
    pv.s3 = L - 2 * (H - pv.p);
    pv.r4 = H + 3 * (pv.p - L);
    pv.s4 = L - 3 * (H - pv.p);
    pv.rangeR4S4 = (pv.r4 - pv.s4) / point;
    pv.success = true;
    return pv;
}

// [수정] 전역 알림 (이전 메시지 덮어쓰기 & 유지)
void displayProfitMessage(int idx, string type, int count, double amount) {
    if (MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
    if (IsOptimization) return;

    string msg = StringFormat("[Set %d] %s 익절완료 (%d개) : +$%.2f", idx + 1,
                              type, count, amount);
    string name = GLOBAL_OBJ_NAME;

    if (ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    }

    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 20);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 20);
    ObjectSetString(0, name, OBJPROP_TEXT, msg);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clrLime);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);

    ChartRedraw();
}

void updateChartGraphics(int idx, PivotLevels& pv, bool force,
                         bool dailyMode = false) {
    if (IsOptimization) return;
    if (MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;

    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if (!force && currentBarTime == lastBarTime) return;
    lastBarTime = currentBarTime;

    string p = states[idx].prefix;
    int digits = (int)SymbolInfoInteger(settings[idx].symbol, SYMBOL_DIGITS);

    createDailyLine(p + "R4", pv.dayStart, pv.dayEnd, pv.r4, clrDodgerBlue);
    createDailyLine(p + "R3", pv.dayStart, pv.dayEnd, pv.r3, clrDodgerBlue);
    createDailyLine(p + "R2", pv.dayStart, pv.dayEnd, pv.r2, clrDodgerBlue);
    createDailyLine(p + "R1", pv.dayStart, pv.dayEnd, pv.r1, clrDodgerBlue);
    createDailyLine(p + "OP", pv.dayStart, pv.dayEnd, pv.openPrice, clrYellow,
                    STYLE_SOLID, 2);
    createDailyLine(p + "S1", pv.dayStart, pv.dayEnd, pv.s1, clrRed);
    createDailyLine(p + "S2", pv.dayStart, pv.dayEnd, pv.s2, clrRed);
    createDailyLine(p + "S3", pv.dayStart, pv.dayEnd, pv.s3, clrRed);
    createDailyLine(p + "S4", pv.dayStart, pv.dayEnd, pv.s4, clrRed);

    datetime txtPos = pv.dayEnd;
    createLineLabel(p + "Txt_R4", txtPos, pv.r4,
                    "R4: " + DoubleToString(pv.r4, digits),
                    settings[idx].gaps[3], clrDodgerBlue);
    createLineLabel(p + "Txt_R3", txtPos, pv.r3,
                    "R3: " + DoubleToString(pv.r3, digits),
                    settings[idx].gaps[2], clrDodgerBlue);
    createLineLabel(p + "Txt_R2", txtPos, pv.r2,
                    "R2: " + DoubleToString(pv.r2, digits),
                    settings[idx].gaps[1], clrDodgerBlue);
    createLineLabel(p + "Txt_R1", txtPos, pv.r1,
                    "R1: " + DoubleToString(pv.r1, digits),
                    settings[idx].gaps[0], clrDodgerBlue);

    createLineLabel(p + "Txt_OP", txtPos, pv.openPrice,
                    "OP: " + DoubleToString(pv.openPrice, digits), 0, clrWhite,
                    true);

    createLineLabel(p + "Txt_S1", txtPos, pv.s1,
                    "S1: " + DoubleToString(pv.s1, digits),
                    settings[idx].gaps[4], clrRed);
    createLineLabel(p + "Txt_S2", txtPos, pv.s2,
                    "S2: " + DoubleToString(pv.s2, digits),
                    settings[idx].gaps[5], clrRed);
    createLineLabel(p + "Txt_S3", txtPos, pv.s3,
                    "S3: " + DoubleToString(pv.s3, digits),
                    settings[idx].gaps[6], clrRed);
    createLineLabel(p + "Txt_S4", txtPos, pv.s4,
                    "S4: " + DoubleToString(pv.s4, digits),
                    settings[idx].gaps[7], clrRed);

    color infoColor = dailyMode ? clrRed : clrYellow;
    createLabel(
        p + "InfRange", 250, 20 + (idx * 60),
        settings[idx].symbol + " Range: " + DoubleToString(pv.rangeR4S4, 0),
        infoColor);
    ChartRedraw();
}

void createDailyLine(string name, datetime t1, datetime t2, double price,
                     color col, ENUM_LINE_STYLE style = STYLE_DOT,
                     int width = 1) {
    if (ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
        ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
    }
    ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
    ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price);
    ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
    ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_STYLE, style);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
}

void createLineLabel(string name, datetime time, double price, string baseText,
                     double gap, color col, bool noGap = false) {
    string fullText = baseText;
    if (!noGap) {
        string gapStr =
            (gap >= 0) ? "+" + DoubleToString(gap, 0) : DoubleToString(gap, 0);
        fullText += " (" + gapStr + ")";
    }
    if (ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_TEXT, 0, time, price);
        ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
    }
    ObjectSetString(0, name, OBJPROP_TEXT, fullText);
    ObjectSetDouble(0, name, OBJPROP_PRICE, price);
    ObjectSetInteger(0, name, OBJPROP_TIME, time);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
}

void createLabel(string name, int x, int y, string text, color col) {
    if (ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    }
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
}
//+------------------------------------------------------------------+