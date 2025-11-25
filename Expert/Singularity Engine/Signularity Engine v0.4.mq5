#property copyright "Copyright 2025, p3pwp3p"
#property link "https://github.com/hayan2"
#property version "0.40"

const string GVersion = "0.40";

#include <Trade/PositionInfo.mqh>
#include <Trade/Trade.mqh>

enum ENUM_MARKET_REGIME { REGIME_TRENDING, REGIME_RANGING, REGIME_UNCERTAIN };
enum ENUM_MARKET_BIAS { BIAS_BUY, BIAS_SELL, BIAS_NEUTRAL };
enum ENUM_TRADE_DIRECTION { BUY_ONLY, SELL_ONLY, BOTH };

input group "--- General Settings ---";
input ulong MagicNumber = 20251021;
input double LotSize = 0.01;

input group "--- Master Trend Filter ---";
input ENUM_TRADE_DIRECTION TradeDirection = BOTH;
input ENUM_TIMEFRAMES MasterMaTimeframe = PERIOD_D1;
input int MasterMaPeriod = 200;

input group "--- Bollinger Bands Settings ---";
input int BandsPeriod = 20;
input double BandsDeviation = 2.0;

input group "--- ADX Settings ---";
input int AdxPeriod = 14;
input int AdxTrendingThreshold = 25;
input int AdxRangingThreshold = 20;

input group "--- Grid Management ---";
input string GridDistances = "177, 198, 223, 238, 238, 238, 238";
input int GridDistancePoints = 150;
input int GridDistanceIncrease = 50;
input int GridMaxTrades = 7;
input double BasketProfitUSD = 10.0;
input double BasketProfitSingle = 3.5;
input double BasketProfitGridAdd = 7.25;

input group "--- Risk Management ---";
input int StopLossPoints = 0;
input int TakeProfitPoints = 0;

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

    string gridDistances;
    int gridDistanceArray[100];
    int gridDistancesCount;
    int gridMaxTrades;
    double basketProfitSingle;
    double basketProfitGridAdd;

    int gridDistancePoints;
    int gridDistanceIncrease;
    double basketProfitUSD;

    int masterMaHandle;
    int bbHandle;
    int adxHandle;

    ENUM_MARKET_BIAS currentBias;
    ENUM_MARKET_REGIME currentRegime;
    ENUM_TRADE_DIRECTION tradeDirection;

    CTrade trade;
    CPositionInfo positionInfo;
    string symbol;
    ENUM_TIMEFRAMES period;

    ENUM_TIMEFRAMES masterMaTimeframe;
    int masterMaPeriod;

    double point;
    int digits;

    ENUM_MARKET_BIAS getMarketBias();
    ENUM_MARKET_REGIME getMarketRegime();
    void checkSingularityBreakout(ENUM_ORDER_TYPE orderType);
    void checkWallBounce(ENUM_ORDER_TYPE orderType);
    void executeOrder(ENUM_ORDER_TYPE orderType, double tradeLotSize);
    void checkGridLogic();
    void closeAllPositions(string comment);
    void parseGridDistances();

  public:
    CSingularityEngine();
    ~CSingularityEngine();

    bool init(string sym, ENUM_TIMEFRAMES per, ulong magic, double lot, int bPeriod, double bDev, int aPeriod,
              int aTrendTh, int aRangeTh, int slPoints, int tpPoints, ENUM_TIMEFRAMES mastMaTf, int mastMaPer,
              ENUM_TRADE_DIRECTION tradeDir, string gridDistStr, int gridMax, double basketSingle,
              double basketGridAdd);
    void drawIndicatorsToChart(long chartID);
    void run();
};

CSingularityEngine::CSingularityEngine() {
    bbHandle = INVALID_HANDLE;
    adxHandle = INVALID_HANDLE;
    masterMaHandle = INVALID_HANDLE;
}

CSingularityEngine::~CSingularityEngine() {
    if (bbHandle != INVALID_HANDLE)
        IndicatorRelease(bbHandle);
    if (adxHandle != INVALID_HANDLE)
        IndicatorRelease(adxHandle);
    if (masterMaHandle != INVALID_HANDLE)
        IndicatorRelease(masterMaHandle);
}

bool CSingularityEngine::init(string sym, ENUM_TIMEFRAMES per, ulong magic, double lot, int bPeriod, double bDev,
                              int aPeriod, int aTrendTh, int aRangeTh, int slPoints, int tpPoints,
                              ENUM_TIMEFRAMES mastMaTf, int mastMaPer, ENUM_TRADE_DIRECTION tradeDir,
                              string gridDistStr, int gridMax, double basketSingle, double basketGridAdd) {
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

    gridDistances = gridDistStr;
    gridMaxTrades = gridMax;
    basketProfitSingle = basketSingle;
    basketProfitGridAdd = basketGridAdd;

    tradeDirection = tradeDir;

    masterMaTimeframe = mastMaTf;
    masterMaPeriod = mastMaPer;

    point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

    trade.SetExpertMagicNumber(magicNumber);
    // positionInfo.Symbol(symbol);

    parseGridDistances();

    bbHandle = iBands(symbol, period, bandsPeriod, 0, bandsDeviation, PRICE_CLOSE);
    adxHandle = iADX(symbol, period, adxPeriod);
    masterMaHandle = iMA(symbol, masterMaTimeframe, masterMaPeriod, 0, MODE_SMA, PRICE_CLOSE);

    if (bbHandle == INVALID_HANDLE || adxHandle == INVALID_HANDLE || masterMaHandle == INVALID_HANDLE) {
        Print("Error creating indicator handles - error:", GetLastError());
        return (false);
    }
    return true;
}

void CSingularityEngine::run() {
    static datetime lastBarTime = 0;
    datetime currentBarTime = (datetime)SeriesInfoInteger(symbol, period, SERIES_LASTBAR_DATE);

    bool isNewBar = false;
    if (lastBarTime < currentBarTime) {
        lastBarTime = currentBarTime;
        isNewBar = true;
    }

    if (!PositionSelect(symbol)) {
        if (!isNewBar)
            return;

        currentBias = getMarketBias();
        if (currentBias == BIAS_NEUTRAL)
            return;

        currentRegime = getMarketRegime();
        if (currentRegime == REGIME_UNCERTAIN)
            return;

        if (currentBias == BIAS_BUY) {
            if (currentRegime == REGIME_TRENDING) {
                double plusDI[1], minusDI[1];
                if (CopyBuffer(adxHandle, 1, 1, 1, plusDI) < 1 || CopyBuffer(adxHandle, 2, 1, 1, minusDI) < 1)
                    return;

                if (plusDI[0] > minusDI[0]) {
                    checkSingularityBreakout(ORDER_TYPE_BUY);
                }
            } else {
                checkWallBounce(ORDER_TYPE_BUY);
            }
        } else {

            if (currentRegime == REGIME_TRENDING) {
                double plusDI[1], minusDI[1];
                if (CopyBuffer(adxHandle, 1, 1, 1, plusDI) < 1 || CopyBuffer(adxHandle, 2, 1, 1, minusDI) < 1)
                    return;

                if (minusDI[0] > plusDI[0]) {
                    checkSingularityBreakout(ORDER_TYPE_SELL);
                }
            } else {
                checkWallBounce(ORDER_TYPE_SELL);
            }
        }
    } else {
        checkGridLogic();
    }
}

ENUM_MARKET_BIAS CSingularityEngine::getMarketBias() {
    if (tradeDirection == BUY_ONLY)
        return BIAS_BUY;
    if (tradeDirection == SELL_ONLY)
        return BIAS_SELL;

    double maValue[1];
    if (CopyBuffer(masterMaHandle, 0, 1, 1, maValue) < 1) {
        Print("Error copying Master MA buffer");
        return BIAS_NEUTRAL;
    }
    double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
    if (currentPrice == 0)
        return BIAS_NEUTRAL;

    if (currentPrice > maValue[0])
        return BIAS_BUY;
    else if (currentPrice < maValue[0])
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

    double prevBarLow = rates[0].low;
    double prevBarHigh = rates[0].high;
    double prevBarClose = rates[0].close;

    double currentPriceBuy = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double currentPriceSell = SymbolInfoDouble(symbol, SYMBOL_BID);

    double bbMiddle[1];
    if (CopyBuffer(bbHandle, 0, 1, 1, bbMiddle) < 1)
        return;

    if (orderType == ORDER_TYPE_BUY) {
        if (prevBarHigh <= bbMiddle[0] && currentPriceBuy < bbMiddle[0]) {
            executeOrder(ORDER_TYPE_BUY, lotSize);
        }
    } else if (orderType == ORDER_TYPE_SELL) {
        if (prevBarLow >= bbMiddle[0] && currentPriceSell > bbMiddle[0]) {
            executeOrder(ORDER_TYPE_SELL, lotSize);
        }
    }
}

void CSingularityEngine::checkWallBounce(ENUM_ORDER_TYPE orderType) {
    MqlRates rates[3];
    if (CopyRates(symbol, period, 1, 3, rates) < 3)
        return;

    double barClose = rates[0].close;
    double prevBarClose = rates[1].close;

    double bbUpper[2];
    double bbLower[2];
    double bbMiddle[1];
    if (CopyBuffer(bbHandle, 1, 1, 2, bbUpper) < 2 || CopyBuffer(bbHandle, 2, 1, 2, bbLower) < 2 ||
        CopyBuffer(bbHandle, 0, 1, 1, bbMiddle) < 1)
        return;

    double barLowerBand = bbLower[0];
    double prevBarLowerBand = bbLower[1];
    double barUpperBand = bbUpper[0];
    double prevBarUpperBand = bbUpper[1];

    if (orderType == ORDER_TYPE_BUY) {
        if (prevBarClose < prevBarLowerBand && barClose > barLowerBand && barClose > bbMiddle[0]) {
            executeOrder(ORDER_TYPE_BUY, lotSize);
        }
    } else if (orderType == ORDER_TYPE_SELL) {
        if (prevBarClose > prevBarUpperBand && barClose < barUpperBand && barClose < bbMiddle[0]) {
            executeOrder(ORDER_TYPE_SELL, lotSize);
        }
    }
}

void CSingularityEngine::executeOrder(ENUM_ORDER_TYPE orderType, double tradeLotSize) {
    double price = 0;
    double sl = 0;
    double tp = 0;

    if (orderType == ORDER_TYPE_BUY) {
        price = SymbolInfoDouble(symbol, SYMBOL_ASK);
        // sl = (stopLossPoints > 0) ? price - stopLossPoints * point : 0;
        // tp = (takeProfitPoints > 0) ? price + takeProfitPoints * point : 0;
        trade.Buy(tradeLotSize, symbol, price, sl, tp, "Singularity Engine Buy");
    } else if (orderType == ORDER_TYPE_SELL) {
        price = SymbolInfoDouble(symbol, SYMBOL_BID);
        // sl = (stopLossPoints > 0) ? price + stopLossPoints * point : 0;
        // tp = (takeProfitPoints > 0) ? price - takeProfitPoints * point : 0;
        trade.Sell(tradeLotSize, symbol, price, sl, tp, "Singularity Engine Sell");
    }
}

void CSingularityEngine::checkGridLogic() {
    double totalProfit = 0;
    int totalPositions = 0;
    double lastPrice = 0;
    ulong lastTicket = 0;
    ENUM_POSITION_TYPE positionType = POSITION_TYPE_BUY;

    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (positionInfo.SelectByIndex(i)) {
            if (positionInfo.Symbol() == symbol && positionInfo.Magic() == magicNumber) {
                totalPositions++;
                totalProfit += positionInfo.Profit() + positionInfo.Swap();
                positionType = positionInfo.PositionType();

                if (positionInfo.Ticket() > lastTicket) {
                    lastTicket = positionInfo.Ticket();
                    lastPrice = positionInfo.PriceOpen();
                }
            }
        }
    }

    if (totalPositions == 0)
        return;

    double currentTargetProfit = 0;
    if (totalPositions == 1)
        currentTargetProfit = basketProfitSingle;
    else if (totalPositions > 1)
        currentTargetProfit = basketProfitSingle + (basketProfitGridAdd * (totalPositions - 1));

    // 합계 익절
    if (totalProfit >= currentTargetProfit) {
        closeAllPositions(StringFormat("Basket TP Hit ($%.2f)", totalProfit));
        return;
    }

    if (totalPositions >= gridMaxTrades)
        return;

    if (totalPositions - 1 >= gridDistancesCount)
        return;

    int currentGridDistance = gridDistanceArray[totalPositions - 1];

    // 추가 진입 간격 체크
    double currentPrice = (positionType == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID)
                                                              : SymbolInfoDouble(symbol, SYMBOL_ASK);
    bool distanceReached = false;

    if (positionType == POSITION_TYPE_BUY) {
        if (currentPrice <= lastPrice - currentGridDistance * point) {
            distanceReached = true;
        }
    } else {
        if (currentPrice >= lastPrice + currentGridDistance * point) {
            distanceReached = true;
        }
    }

    if (distanceReached) {
        double nextLotSize = lotSize;
        double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        if (nextLotSize > maxLot)
            nextLotSize = maxLot;
        ENUM_ORDER_TYPE orderType = (positionType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        executeOrder(orderType, nextLotSize);
    }
}

void CSingularityEngine::closeAllPositions(string comment) {
    Print("Closing all positions: ", comment);
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (positionInfo.SelectByIndex(i)) {
            if (positionInfo.Symbol() == symbol && positionInfo.Magic() == magicNumber) {
                trade.PositionClose(positionInfo.Ticket());
            }
        }
    }
}

void CSingularityEngine::parseGridDistances() {
    ArrayInitialize(gridDistanceArray, 0);
    gridDistancesCount = 0;

    ushort separator = (ushort)',';
    string str = gridDistances;

    string currentValue;
    for (int i = 0; i < StringLen(str); i++) {
        ushort charCode = StringGetCharacter(str, i);
        if (charCode == separator) {
            if (gridDistancesCount < 100)
            {
                gridDistanceArray[gridDistancesCount] = (int)StringToInteger(currentValue);
                gridDistancesCount++;
                currentValue = "";
            }
        } else {
            currentValue += StringFormat("%c", charCode);
        }
    }
    if (currentValue != "" && gridDistancesCount < 100) {
        gridDistanceArray[gridDistancesCount] = (int)StringToInteger(currentValue);
        gridDistancesCount++;
    }

    Print("Grid distances parsed. Total levels: ", gridDistancesCount);
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
                      AdxTrendingThreshold, AdxRangingThreshold, StopLossPoints, TakeProfitPoints, MasterMaTimeframe,
                      MasterMaPeriod, TradeDirection, GridDistances, GridMaxTrades, BasketProfitSingle,
                      BasketProfitGridAdd)) {
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