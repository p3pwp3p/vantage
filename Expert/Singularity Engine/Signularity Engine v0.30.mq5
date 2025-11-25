#property copyright "Copyright 2025, p3pwp3p"
#property link "https://github.com/hayan2"
#property version "0.30"

const string GVersion = "0.30";

#include <Trade/Trade.mqh>

input group "--- General Settings ---";
input ulong MagicNumber = 20251021;
input double LotSize = 0.01;

input group "--- Bollinger Bands Settings ---";
input int BandsPeriod = 20;
input double BandsDeviation = 2.0;

input group "--- ADX Settings ---";
input int AdxPeriod = 14;
input int AdxTrendingThreshold = 25;
input int AdxRangingThreshold = 20;

input group "--- Risk Management ---";
input int StopLossPoints = 200;
input int TakeProfitPoints = 400;

enum ENUM_MARKET_REGIME { REGIME_TRENDING, REGIME_RANGING, REGIME_UNCERTAIN };
enum ENUM_MARKET_BIAS { BIAS_BUY, BIAS_SELL, BIAS_NEUTRAL };

class CSingularityEngine {
  private:
    ulong magicNumber;
    double lotSize;
    int bandsPeriod;
    double bandsDeviation;
    int adxPeriod;
    int adxTrendingThreshold;
    int adxRangingThreshold;
    int stopLossPoints;
    int takeProfitPoints;

    int bbHandle;
    int adxHandle;

    ENUM_MARKET_BIAS currentBias;
    ENUM_MARKET_REGIME currentRegime;

    CTrade trade;
    string symbol;
    ENUM_TIMEFRAMES period;
    double point;
    int digits;

    ENUM_MARKET_BIAS getMarketBias();
    ENUM_MARKET_REGIME getMarketRegime();
    void checkSingularityBreakout(ENUM_ORDER_TYPE orderType);
    void checkWallBounce(ENUM_ORDER_TYPE orderType);
    void executeOrder(ENUM_ORDER_TYPE orderType);

  public:
    CSingularityEngine();
    ~CSingularityEngine();

    bool init(string sym, ENUM_TIMEFRAMES per, ulong magic, double lot, int bPeriod, double bDev, int aPeriod,
              int aTrendTh, int aRangeTh, int slPoints, int tpPoints);
    void drawIndicatorsToChart(long chartID);
    void run();
};

CSingularityEngine::CSingularityEngine() {
    bbHandle = INVALID_HANDLE;
    adxHandle = INVALID_HANDLE;
}

CSingularityEngine::~CSingularityEngine() {
    if (bbHandle != INVALID_HANDLE)
        IndicatorRelease(bbHandle);
    if (adxHandle != INVALID_HANDLE)
        IndicatorRelease(adxHandle);
}

bool CSingularityEngine::init(string sym, ENUM_TIMEFRAMES per, ulong magic, double lot, int bPeriod, double bDev,
                              int aPeriod, int aTrendTh, int aRangeTh, int slPoints, int tpPoints) {
    symbol = sym;
    period = per;

    magicNumber = magic;
    lotSize = lot;
    bandsPeriod = bPeriod;
    bandsDeviation = bDev;
    adxPeriod = aPeriod;
    adxTrendingThreshold = aTrendTh;
    adxRangingThreshold = aRangeTh;
    stopLossPoints = slPoints;
    takeProfitPoints = tpPoints;

    point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

    trade.SetExpertMagicNumber(magicNumber);

    bbHandle = iBands(symbol, period, bandsPeriod, 0, bandsDeviation, PRICE_CLOSE);
    adxHandle = iADX(symbol, period, adxPeriod);

    if (bbHandle == INVALID_HANDLE || adxHandle == INVALID_HANDLE) {
        Print("Error creating indicator handles - error:", GetLastError());
        return (false);
    }
    return true;
}

void CSingularityEngine::run() {
    static datetime lastBarTime = 0;
    datetime currentBarTime = (datetime)SeriesInfoInteger(symbol, period, SERIES_LASTBAR_DATE);
    if (lastBarTime >= currentBarTime)
        return;
    lastBarTime = currentBarTime;

    if (!PositionSelect(symbol)) {
        currentBias = getMarketBias();
        if (currentBias == BIAS_NEUTRAL)
            return;

        currentRegime = getMarketRegime();
        if (currentRegime == REGIME_UNCERTAIN)
            return;

        if (currentBias == BIAS_BUY) {
            if (currentRegime == REGIME_TRENDING)
                checkSingularityBreakout(ORDER_TYPE_BUY);
            else
                checkWallBounce(ORDER_TYPE_BUY);
        } else {
            if (currentRegime == REGIME_TRENDING)
                checkSingularityBreakout(ORDER_TYPE_SELL);
            else
                checkWallBounce(ORDER_TYPE_SELL);
        }
    }
}

ENUM_MARKET_BIAS CSingularityEngine::getMarketBias() {
    double plusDI[1];
    double minusDI[1];

    if (CopyBuffer(adxHandle, 1, 1, 1, plusDI) < 1 || CopyBuffer(adxHandle, 2, 1, 1, minusDI) < 1) {
        Print("Error copying ADX DI buffers");
        return BIAS_NEUTRAL;
    }

    if (plusDI[0] > minusDI[0])
        return BIAS_BUY;
    else if (minusDI[0] > plusDI[0])
        return BIAS_SELL;

    return BIAS_NEUTRAL;
}

ENUM_MARKET_REGIME CSingularityEngine::getMarketRegime() {
    double adxValue[1];

    if (CopyBuffer(adxHandle, 0, 1, 1, adxValue) < 1) {
        Print("Error copying ADX Main buffer");
        return REGIME_UNCERTAIN;
    }

    if (adxValue[0] > adxTrendingThreshold) {
        Comment("Market Regime: TRENDING (ADX: " + (string)adxValue[0] + ")");
        return REGIME_TRENDING;
    } else if (adxValue[0] < adxRangingThreshold) {
        Comment("Market Regime: RANGING (ADX: " + (string)adxValue[0] + ")");
        return REGIME_RANGING;
    }

    return REGIME_UNCERTAIN;
}

void CSingularityEngine::checkSingularityBreakout(ENUM_ORDER_TYPE orderType) {
    MqlRates rates[2];
    if (CopyRates(symbol, period, 1, 2, rates) < 2)
        return;

    double barLow = rates[0].low;
    double barHigh = rates[0].high;
    double barClose = rates[0].close;

    double bbMiddle[1];
    if (CopyBuffer(bbHandle, 0, 1, 1, bbMiddle) < 1)
        return;

    if (orderType == ORDER_TYPE_BUY) {
        if (barLow <= bbMiddle[0] && barClose > bbMiddle[0]) {
            executeOrder(ORDER_TYPE_BUY);
        }
    } else if (orderType == ORDER_TYPE_SELL) {
        if (barHigh >= bbMiddle[0] && barClose < bbMiddle[0]) {
            executeOrder(ORDER_TYPE_SELL);
        }
    }
}

void CSingularityEngine::checkWallBounce(ENUM_ORDER_TYPE orderType) {
    MqlRates rates[2];

    if (CopyRates(symbol, period, 1, 2, rates) < 2)
        return;

    double barLow = rates[0].low;
    double barHigh = rates[0].high;
    double barClose = rates[0].close;

    double bbUpper[1];
    double bbLower[1];
    if (CopyBuffer(bbHandle, 1, 1, 1, bbUpper) < 1 || CopyBuffer(bbHandle, 2, 1, 1, bbLower) < 1)
        return;

    if (orderType == ORDER_TYPE_BUY) {
        if (barLow <= bbLower[0] && barClose > bbLower[0]) {
            executeOrder(ORDER_TYPE_BUY);
        }
    } else if (orderType == ORDER_TYPE_SELL) {
        if (barHigh >= bbUpper[0] && barClose < bbUpper[0]) {
            executeOrder(ORDER_TYPE_SELL);
        }
    }
}

void CSingularityEngine::executeOrder(ENUM_ORDER_TYPE orderType) {
    double price = 0;
    double sl = 0;
    double tp = 0;

    if (orderType == ORDER_TYPE_BUY) {
        price = SymbolInfoDouble(symbol, SYMBOL_ASK);
        sl = (stopLossPoints > 0) ? price - stopLossPoints * point : 0;
        tp = (takeProfitPoints > 0) ? price + takeProfitPoints * point : 0;

        trade.Buy(lotSize, symbol, price, sl, tp, "Singularity Engine Buy");
    } else if (orderType == ORDER_TYPE_SELL) {
        price = SymbolInfoDouble(symbol, SYMBOL_BID);
        sl = (stopLossPoints > 0) ? price + stopLossPoints * point : 0;
        tp = (takeProfitPoints > 0) ? price - takeProfitPoints * point : 0;

        trade.Sell(lotSize, symbol, price, sl, tp, "Singularity Engine Sell");
    }
}

void CSingularityEngine::drawIndicatorsToChart(long chartID) {
    if (!ChartIndicatorAdd(chartID, 0, bbHandle)) {
        Print("Failed to add BB to chart!");
        return;
    }
    if (!ChartIndicatorAdd(chartID, 1, adxHandle)) {
        Print("Failed to add ADX to chart!");
        return;
    }

    string bbName = ChartIndicatorName(chartID, 0, 0);
    string adxName = ChartIndicatorName(chartID, 1, 0);

    if (bbName == "" || adxName == "") {
        Print("Failed to get indicator object names on chart!");
        return;
    }

    ObjectSetInteger(chartID, bbName, OBJPROP_COLOR, 0, clrWhite);
    ObjectSetInteger(chartID, bbName, OBJPROP_COLOR, 1, clrWhite);
    ObjectSetInteger(chartID, bbName, OBJPROP_COLOR, 2, clrWhite);

    ObjectSetInteger(chartID, adxName, OBJPROP_COLOR, 0, clrDeepSkyBlue);
    ObjectSetInteger(chartID, adxName, OBJPROP_COLOR, 1, clrLime);
    ObjectSetInteger(chartID, adxName, OBJPROP_COLOR, 2, clrGold);

    ObjectSetInteger(chartID, adxName, OBJPROP_LEVELS, 2);

    ObjectSetDouble(chartID, adxName, OBJPROP_LEVELVALUE, 0, adxTrendingThreshold);
    ObjectSetInteger(chartID, adxName, OBJPROP_LEVELCOLOR, 0, clrGray);
    ObjectSetInteger(chartID, adxName, OBJPROP_LEVELSTYLE, 0, STYLE_DOT);

    ObjectSetDouble(chartID, adxName, OBJPROP_LEVELVALUE, 1, adxRangingThreshold);
    ObjectSetInteger(chartID, adxName, OBJPROP_LEVELCOLOR, 1, clrGray);
    ObjectSetInteger(chartID, adxName, OBJPROP_LEVELSTYLE, 1, STYLE_DOT);

    ChartRedraw(chartID);
}

CSingularityEngine GEngine;

int OnInit() {
    if (MQLInfoInteger(MQL_VISUAL_MODE)) {
        // TesterHideIndicators(true);
        // GEngine.drawIndicatorsToChart(0);
    }

    if (!GEngine.init(_Symbol, _Period, MagicNumber, LotSize, BandsPeriod, BandsDeviation, AdxPeriod,
                      AdxTrendingThreshold, AdxRangingThreshold, StopLossPoints, TakeProfitPoints)) {
        Print("Engine initialization failed.");
        return (INIT_FAILED);
    }

    Print("Singularity Engine v", GVersion, " initialized successfully.");
    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    Print("Singularity Engine deinitialized.");
}

void OnTick() {
    GEngine.run();
}