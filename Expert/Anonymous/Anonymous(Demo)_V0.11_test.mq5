//+------------------------------------------------------------------+
//|                                   Copyright 2025, Anonymous Ltd. |
//|                                        https://github.com/hayan2 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Anonymous Ltd."
#property link "https://github.com/hayan2"
#property version "0.11"

#define CURRENT 0
#define PREVIOUS 1
#define ONE_HALF 0.5
#define ONE_TENTH 0.1
#define MINIMUM_LOTS 0.01

enum ENUM_ORDER_FILLING {
    Fire_or_kill = 0,
    Immediate_or_cancel = 1,
    Order_filling_return = 2
};

input group "---------- General ----------";
input ulong RangeBuyMagicNumber = 2147483644;
input ulong RangeSellMagicNumber = 2147483635;
input ulong TrendBuyMagicNumber = 2147483646;
input ulong TrendSellMagicNumber = 2147483647;
input ENUM_TIMEFRAMES ChartPeriod = PERIOD_H1;
input ENUM_ORDER_FILLING OrderFilling = 1;
input group "---------- Bollinger Bands variable ----------";
input int BandsPeriod = 14;
input int BandsShift = 0;
input double Deviation = 2.0;
input ENUM_APPLIED_PRICE AppliedPrice = PRICE_CLOSE;
input int SlopePeriod = 3;
input group "---------- Relative Strength Index variable ----------";
input int RsiPeriod = 14;
input group "---------- Moving Average Index variable ----------";
input int FastMAPeriod = 20;
input int SlowMAPeriod = 70;
input group "---------- Pattern variable ----------";
input double RangeBoundAbsSlope = 1.41;
input double RangeBoundBBW = 41.85;

input double TrendPatternBuyUpperValue = 15.16;
input double TrendPatternBuyMiddleValue = 27.35;
input double TrendPatternBuyLowerValue = 0.0;

input double TrendPatternSellUpperValue = 0.0;
input double TrendPatternSellMiddleValue = -27.35;
input double TrendPatternSellLowerValue = -15.16;

input double TrendPatternBBW = 100.0;
input group "---------- Risk and money management ----------";
input double Lots = 0.01;
input bool HedgeMode = false;
input double TakeProfitPercent = 0.05;
input double MarginPercent = 0.1;
input double trueIsBalanceFalseIsEquity = false;
input double StopLoss = 200;
input bool EnableTP = false;
input double TakeProfit = 500;
input int Slippage = 10;
input group "---------- Order management ----------";
input int PointsGap = 0;
input int FirstSellPointsGap = 40;
input int SecondSellPointsGap = 0;
input int ThirdSellPointsGap = 0;
input int FirstBuyPointsGap = 40;
input int SecondBuyPointsGap = 0;
input int ThirdBuyPointsGap = 0;
input int TakeProfitGap = 20;
input int StopLossGap = 20;
input bool EnableSL = false;

#include <Trade/SymbolInfo.mqh>
#include <Trade/Trade.mqh>

struct Slope {
    double upper, middle, lower, absUpper, absMiddle, absLower;
};

class TradeValidator {
   public:
    Slope slope;
    double bbw;
    string symbol;
    //---
    // buy position variable
    bool hasLowerBroken, hasCrossedAboveLower, hasBuyTouchedMiddle,
        hasTouchedUpper;
    bool hasBuyCloseMiddle;
    // sell position variable
    bool hasUpperBroken, hasCrossedBelowUpper, hasSellTouchedMiddle,
        hasTouchedLower;
    bool hasSellCloseMiddle;
    // range or trend trading variable
    bool hasOpenRangeBuyPositions, hasOpenRangeSellPositions,
        hasOpenTrendBuyPositions, hasOpenTrendSellPositions;
	bool hasTradeBuyThisSection, hasTradeSellThisSection;
    //---
    double balance, equity;
    // 10%
    double lotsOneTenth;
    // 50%
    double lotsOneHalf;

    TradeValidator();
    ~TradeValidator() {};

    void refresh();
    bool loadAccountInfo();
    double calculateLots();
    double calculatePips(double point) { return point * _Point; }
    double calculateTakeProfit(ENUM_ORDER_TYPE type, double currentPrice);
    double calculateStopLoss(ENUM_ORDER_TYPE type, double currentPrice);

    bool checkActiveBuyPosition();
    bool checkActiveSellPosition();

    bool executeRangeTrade(ENUM_ORDER_TYPE type, double currentPrice,
                           double volume, ulong magic);
    bool executeTrendTrade(ENUM_ORDER_TYPE type, double currentPrice,
                           double volume, ulong magic);
    bool closePositionHalf(ENUM_ORDER_TYPE type,
                           ENUM_POSITION_TYPE positionType);
    // close all position
    void closeAllBuyPosition();
    void closeAllSellPosition();

    void notEnoughEquity() { Print("Not enough equity."); }

    double getAccountBalance() { return balance; }
    double getAccountEquity() { return equity; }
    double getSpread() {
        return SymbolInfoDouble(symbol, SYMBOL_ASK) -
               SymbolInfoDouble(symbol, SYMBOL_BID);
    }
    void getCurrentBollingerBandsSlope(double& lowerBand[],
                                       double& middleBand[],
                                       double& upperBand[], int period);
    void getCurrentBollingerBandwidth(double currentLowerBand,
                                      double currentMiddleBand,
                                      double currentUpperBand);
    bool getRangeTradingSignal();
    bool getTrendTradingBuySignal();
    bool getTrendTradingSellSignal();

    void displayBBW() { Print("BBW : ", bbw); }
    void displaySlope() {
        Print("upper slope : ", slope.upper);
        Print("middle slope : ", slope.middle);
        Print("lower slope : ", slope.lower);
    }

    double getBid() { return SymbolInfoDouble(symbol, SYMBOL_BID); }
    double getAsk() { return SymbolInfoDouble(symbol, SYMBOL_ASK); }
};

TradeValidator::TradeValidator() {
    symbol = _Symbol;
    hasLowerBroken = false;
    hasCrossedAboveLower = false;
    hasBuyTouchedMiddle = false;
    hasTouchedUpper = false;
    hasUpperBroken = false;
    hasCrossedBelowUpper = false;
    hasSellTouchedMiddle = false;
    hasTouchedLower = false;
    hasBuyCloseMiddle = false;
    hasSellCloseMiddle = false;
    balance = 0.0;
    equity = 0.0;
    lotsOneTenth = 0.01;
    lotsOneHalf = 0.05;
}

bool TradeValidator::loadAccountInfo() {
    balance = AccountInfoDouble(ACCOUNT_BALANCE);
    equity = AccountInfoDouble(ACCOUNT_EQUITY);

    return true;
}

double TradeValidator::calculateLots() {
    double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    double equityPerContract = equity / contractSize;
    double balancePerContract = balance / contractSize;

    if (trueIsBalanceFalseIsEquity) {
        lotsOneHalf = balancePerContract * ONE_HALF;
        lotsOneTenth = balancePerContract * ONE_TENTH;
    } else {
        lotsOneHalf = equityPerContract * ONE_HALF;
        lotsOneTenth = equityPerContract * ONE_TENTH;
    }

    lotsOneHalf = MathCeil(lotsOneHalf * 100) / 10;
    lotsOneTenth = MathCeil(lotsOneTenth * 100) / 10;

    return lotsOneTenth;
}

double TradeValidator::calculateTakeProfit(ENUM_ORDER_TYPE type,
                                           double currentPrice) {
    if (currentPrice <= 0.0) return 0.0;
    if (TakeProfit <= 0.0) return 0.0;

    bool isBuy =
        (type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT ||
         type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT);
    bool isSell =
        (type == ORDER_TYPE_SELL || type == ORDER_TYPE_SELL_LIMIT ||
         type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_SELL_STOP_LIMIT);

    if (isBuy) return NormalizeDouble(getBid() + TakeProfit * _Point, _Digits);
    if (isSell) return NormalizeDouble(getAsk() - TakeProfit * _Point, _Digits);

    return 0.0;
}

double TradeValidator::calculateStopLoss(ENUM_ORDER_TYPE type,
                                         double currentPrice) {
    if (currentPrice <= 0.0) return 0.0;
    if (TakeProfit <= 0.0) return 0.0;

    bool isBuy =
        (type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT ||
         type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT);
    bool isSell =
        (type == ORDER_TYPE_SELL || type == ORDER_TYPE_SELL_LIMIT ||
         type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_SELL_STOP_LIMIT);

    if (isBuy) return NormalizeDouble(getBid() - StopLoss * _Point, _Digits);
    if (isSell) return NormalizeDouble(getAsk() + StopLoss * _Point, _Digits);

    return 0.0;
}

// returns true if there are no open buy position
bool TradeValidator::checkActiveBuyPosition() {
    return !(hasLowerBroken || hasCrossedAboveLower || hasBuyTouchedMiddle ||
             hasTouchedUpper);
}

// returns true if there are no open sell position
bool TradeValidator::checkActiveSellPosition() {
    return !(hasUpperBroken || hasCrossedBelowUpper || hasSellTouchedMiddle ||
             hasTouchedLower);
}

bool TradeValidator::executeRangeTrade(ENUM_ORDER_TYPE type,
                                       double currentPrice, double volume,
                                       ulong magic) {
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = symbol;
    request.volume = volume;
    request.type = type;

    if (OrderFilling == 0)
        request.type_filling = ORDER_FILLING_FOK;
    else if (OrderFilling == 1)
        request.type_filling = ORDER_FILLING_IOC;
    else if (OrderFilling == 2)
        request.type_filling = ORDER_FILLING_RETURN;

    if (type == ORDER_TYPE_BUY)
        request.price = validator.getAsk();
    else if (type == ORDER_TYPE_SELL)
        request.price = validator.getBid();

    if (EnableSL && EnableTP) {
        request.sl = StopLoss;
        request.tp = TakeProfit;
    }
    request.deviation = Slippage;
    request.magic = magic;
    request.comment = "";

    displayBBW();
    displaySlope();

    bool success = OrderSend(request, result);

    if (success && result.retcode == TRADE_RETCODE_DONE) {
        Print("Trade successfully executed. Ticket : ", result.order);
        return true;
    } else {
        Print("Trade error : ", result.retcode);
        Print("Description : ", result.comment);
        return false;
    }
}

bool TradeValidator::executeTrendTrade(ENUM_ORDER_TYPE type,
                                       double currentPrice, double volume,
                                       ulong magic) {
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = symbol;
    request.volume = volume;
    request.type = type;

    if (OrderFilling == 0)
        request.type_filling = ORDER_FILLING_FOK;
    else if (OrderFilling == 1)
        request.type_filling = ORDER_FILLING_IOC;
    else if (OrderFilling == 2)
        request.type_filling = ORDER_FILLING_RETURN;

    if (type == ORDER_TYPE_BUY)
        request.price = validator.getAsk();
    else if (type == ORDER_TYPE_SELL)
        request.price = validator.getBid();

    request.sl = calculateStopLoss(type, currentPrice);
    request.tp = calculateTakeProfit(type, currentPrice);

    request.deviation = Slippage;
    request.magic = magic;
    request.comment = "";

    displayBBW();
    displaySlope();

    bool success = OrderSend(request, result);

    if (success && result.retcode == TRADE_RETCODE_DONE) {
        Print("Trade successfully executed. Ticket : ", result.order);
        return true;
    } else {
        Print("Trade error : ", result.retcode);
        Print("Description : ", result.comment);
        return false;
    }
}

bool TradeValidator::closePositionHalf(ENUM_ORDER_TYPE type,
                                       ENUM_POSITION_TYPE positionType) {
    // POSITION_TYPE_BUY  == 0
    // POSITION_TYPE_SELL == 1
    ulong orderMagicNumber =
        (type == ORDER_TYPE_BUY) ? RangeBuyMagicNumber : RangeSellMagicNumber;
    for (int i = PositionsTotal(); i >= 0; i--) {
        if (positionInfo.SelectByIndex(i)) {
            ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
            if (ptype == positionType) {
                double volume =
                    MathCeil(positionInfo.Volume() / 2.0 * 100) / 100;
                if (positionInfo.Symbol() == symbol &&
                    positionInfo.Magic() == orderMagicNumber) {
                    trade.PositionClosePartial(positionInfo.Ticket(), volume,
                                               0);
                }
            }
        }
    }

    return true;
}

void TradeValidator::closeAllBuyPosition() {
    for (int i = PositionsTotal(); i >= 0; i--) {
        if (positionInfo.SelectByIndex(i)) {
            ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
            if (ptype == POSITION_TYPE_BUY) {
                double volume = positionInfo.Volume();
                Print("info volume : ", positionInfo.Volume());
                Print("volume : ", volume);
                if (positionInfo.Symbol() == symbol &&
                    positionInfo.Magic() == RangeBuyMagicNumber) {
                    trade.PositionClose(positionInfo.Ticket(), 0);
                }
            }
        }
    }

    hasLowerBroken = hasCrossedAboveLower = hasBuyTouchedMiddle =
        hasTouchedUpper = hasBuyCloseMiddle = false;
}

void TradeValidator::closeAllSellPosition() {
    for (int i = PositionsTotal(); i >= 0; i--) {
        if (positionInfo.SelectByIndex(i)) {
            ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
            if (ptype == POSITION_TYPE_SELL) {
                double volume = positionInfo.Volume();
                Print("info volume : ", positionInfo.Volume());
                Print("volume : ", volume);
                if (positionInfo.Symbol() == symbol &&
                    positionInfo.Magic() == RangeSellMagicNumber) {
                    trade.PositionClose(positionInfo.Ticket(), 0);
                }
            }
        }
    }
    hasUpperBroken = hasCrossedBelowUpper = hasSellTouchedMiddle =
        hasTouchedLower = hasSellCloseMiddle = false;
}

void TradeValidator::getCurrentBollingerBandsSlope(double& lowerBand[],
                                                   double& middleBand[],
                                                   double& upperBand[],
                                                   int period) {
    slope.lower =
        ((lowerBand[0] - lowerBand[period - 1]) / (period - 1)) * 10000;
    slope.middle =
        ((middleBand[0] - middleBand[period - 1]) / (period - 1)) * 10000;
    slope.upper =
        ((upperBand[0] - upperBand[period - 1]) / (period - 1)) * 10000;

    slope.absLower = MathAbs(slope.lower);
    slope.absMiddle = MathAbs(slope.middle);
    slope.absUpper = MathAbs(slope.upper);
}

void TradeValidator::getCurrentBollingerBandwidth(double currentLowerBand,
                                                  double currentMiddleBand,
                                                  double currentUpperBand) {
    bbw = ((currentUpperBand - currentLowerBand) / currentMiddleBand) * 10000;
}

bool TradeValidator::getRangeTradingSignal() {
    return (slope.absUpper < RangeBoundAbsSlope &&
            slope.absMiddle < RangeBoundAbsSlope &&
            slope.absLower < RangeBoundAbsSlope);
}

bool TradeValidator::getTrendTradingBuySignal() {
    // x < 21.51, y < 32.71
    // upper middle lower slope > 2.85
    return (
        slope.upper > 0 && (bbw / slope.upper) < TrendPatternBuyUpperValue &&
        slope.middle > 0 && (bbw / slope.middle) < TrendPatternBuyMiddleValue);
}

bool TradeValidator::getTrendTradingSellSignal() {
    // y < -27.35 && z < -15.16
    // upper middle lower slope < -2.85
    return (slope.middle < 0 &&
            (bbw / slope.middle) > TrendPatternSellMiddleValue &&
            slope.lower < 0 &&
            (bbw / slope.lower) > TrendPatternSellLowerValue);
}

CTrade trade;
CSymbolInfo symbolInfo;
CPositionInfo positionInfo;
CHistoryOrderInfo historyOrderInfo;
CDealInfo dealInfo;

TradeValidator validator;
int handleBand, handleRsi, handleSlowMa, handleFastMa;

int OnInit() {
    handleBand = iBands(_Symbol, ChartPeriod, BandsPeriod, BandsShift,
                        Deviation, AppliedPrice);
    handleRsi = iRSI(_Symbol, ChartPeriod, RsiPeriod, AppliedPrice);
    handleSlowMa =
        iMA(_Symbol, ChartPeriod, SlowMAPeriod, 0, MODE_SMA, AppliedPrice);
    handleFastMa =
        iMA(_Symbol, ChartPeriod, FastMAPeriod, 0, MODE_SMA, AppliedPrice);

    if (handleBand == INVALID_HANDLE) {
        Print("Failed to create Bollinger Bands");
        return INIT_FAILED;
    }

    if (handleRsi == INVALID_HANDLE) {
        Print("Failed to create RSI");
        return INIT_FAILED;
    }

    if (handleSlowMa == INVALID_HANDLE || handleFastMa == INVALID_HANDLE) {
        Print("Failed to create MA");
        return INIT_FAILED;
    }

    //---
    if (HedgeMode) trade.SetMarginMode();
    trade.SetExpertMagicNumber(RangeBuyMagicNumber);

    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {}

void OnTick() {
    // get bollinger bands middle, lower, upper line.
    double upperBand[], middleBand[], lowerBand[];
    double rsi[];
    double fastMa[], slowMa[];

    ArraySetAsSeries(middleBand, true);
    ArraySetAsSeries(lowerBand, true);
    ArraySetAsSeries(upperBand, true);
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(fastMa, true);
    ArraySetAsSeries(slowMa, true);

    if (CopyBuffer(handleBand, BASE_LINE, 0, 5, middleBand) < 5 ||
        CopyBuffer(handleBand, LOWER_BAND, 0, 5, lowerBand) < 5 ||
        CopyBuffer(handleBand, UPPER_BAND, 0, 5, upperBand) < 5 ||
        CopyBuffer(handleRsi, 0, 0, 5, rsi) < 5 ||
        CopyBuffer(handleFastMa, 0, 0, 5, fastMa) < 5 ||
        CopyBuffer(handleSlowMa, 0, 0, 5, slowMa) < 5) {
        Print("Error copying indicator values : ", GetLastError());
        return;
    }

    validator.loadAccountInfo();
    if (validator.calculateLots() < MINIMUM_LOTS) {
        validator.notEnoughEquity();
        return;
    }

    // bollinger bands values
    double currentUpperBand = upperBand[CURRENT];
    double currentMiddleBand = middleBand[CURRENT];
    double currentLowerBand = lowerBand[CURRENT];
    double prevUpperBand = upperBand[PREVIOUS];
    double prevMiddleBand = middleBand[PREVIOUS];
    double prevLowerBand = lowerBand[PREVIOUS];

    // rsi values
    double currentRsi = rsi[CURRENT];
    double prevRsi = rsi[PREVIOUS];

    // ma values
    double currentSlowMa = slowMa[CURRENT];
    double currentFastMa = fastMa[CURRENT];

    // previous candle info
    double prevClosePrice = iClose(_Symbol, ChartPeriod, PREVIOUS);
    double prevOpenPrice = iOpen(_Symbol, ChartPeriod, PREVIOUS);
    double prevHighPrice = iHigh(_Symbol, ChartPeriod, PREVIOUS);
    double prevLowPrice = iLow(_Symbol, ChartPeriod, PREVIOUS);

    // current ask and bid price and mean price values
    double bidPrice = validator.getBid();
    double askPrice = validator.getAsk();
    double currentPrice = (validator.getAsk() + validator.getBid()) / 2.0;

    validator.getCurrentBollingerBandsSlope(lowerBand, middleBand, upperBand,
                                            SlopePeriod);
    validator.getCurrentBollingerBandwidth(currentLowerBand, currentMiddleBand,
                                           currentUpperBand);

    bool rangeTradingSignal = validator.getRangeTradingSignal();
    bool trendTradingBuySignal = validator.getTrendTradingBuySignal();
    bool trendTradingSellSignal = validator.getTrendTradingSellSignal();

    
    bool flagTrendBuy = false;
    bool flagTrendSell = false;
    // check if trend positions are already open for this symbol
    for (int i = PositionsTotal(); i >= 0; i--) {
        if (positionInfo.SelectByIndex(i)) {
            double volume = positionInfo.Volume();
            if (positionInfo.Symbol() == validator.symbol &&
                positionInfo.Magic() == TrendBuyMagicNumber) {
                flagTrendBuy = true;
            }
            if (positionInfo.Symbol() == validator.symbol &&
                positionInfo.Magic() == TrendSellMagicNumber) {
                flagTrendSell = true;
            }
        }
    }
    validator.hasOpenTrendBuyPositions = flagTrendBuy;
    validator.hasOpenTrendSellPositions = flagTrendSell;
	
	validator.hasTradeBuyThisSection = trendTradingSellSignal ? false : validator.hasTradeBuyThisSection;
	validator.hasTradeSellThisSection = trendTradingBuySignal ? false : validator.hasTradeSellThisSection;

    //--- trend trading section
    if (!validator.hasOpenRangeBuyPositions && !validator.hasOpenRangeSellPositions) {
		//--- trend buy
        if (currentSlowMa < currentFastMa && trendTradingBuySignal &&
            !validator.hasOpenTrendBuyPositions &&
            !validator.hasOpenTrendSellPositions && !validator.hasTradeBuyThisSection) {
            validator.executeTrendTrade(ORDER_TYPE_BUY, validator.getBid(),
                                        validator.lotsOneHalf,
                                        TrendBuyMagicNumber);
            validator.hasOpenTrendBuyPositions = true;
			validator.hasTradeBuyThisSection = true;
        }
        //--- trend sell
        if (currentSlowMa > currentFastMa && trendTradingSellSignal &&
            !validator.hasOpenTrendSellPositions &&
            !validator.hasOpenTrendBuyPositions && !validator.hasTradeSellThisSection) {
            validator.executeTrendTrade(ORDER_TYPE_SELL, validator.getAsk(),
                                        validator.lotsOneHalf,
                                        TrendSellMagicNumber);
            validator.hasOpenTrendSellPositions = true;
			validator.hasTradeSellThisSection = true;
        }
    }

    bool flagRangeBuyBound = false;
    bool flagRangeSellBound = false;
    // check if trend positions are already open for this symbol
    for (int i = PositionsTotal(); i >= 0; i--) {
        if (positionInfo.SelectByIndex(i)) {
            double volume = positionInfo.Volume();
            if (positionInfo.Symbol() == validator.symbol &&
                positionInfo.Magic() == RangeBuyMagicNumber) {
                flagRangeBuyBound = true;
            }
            if (positionInfo.Symbol() == validator.symbol &&
                positionInfo.Magic() == RangeSellMagicNumber) {
                flagRangeSellBound = true;
            }
        }
    }

    validator.hasOpenRangeBuyPositions = flagRangeBuyBound;
    validator.hasOpenRangeSellPositions = flagRangeSellBound;

    //--- range-bound trading section
    //--- order buy and sell
    if ((rangeTradingSignal && !validator.hasOpenTrendBuyPositions &&
         !validator.hasOpenTrendSellPositions) ||
        validator.hasOpenRangeBuyPositions ||
        validator.hasOpenRangeSellPositions) {
        //--- buy order section
        // first buy
        if (!validator.hasOpenRangeSellPositions && rangeTradingSignal) {
            if (prevClosePrice < prevLowerBand &&
                currentPrice < currentLowerBand -
                                   validator.calculatePips(FirstBuyPointsGap) &&
                validator.checkActiveBuyPosition()) {
                validator.executeRangeTrade(ORDER_TYPE_BUY, currentPrice,
                                            validator.lotsOneTenth,
                                            RangeBuyMagicNumber);
                validator.hasLowerBroken = true;
                validator.hasOpenRangeBuyPositions = true;
            }
            // second buy
            if (!validator.hasBuyCloseMiddle && validator.hasLowerBroken &&
                !validator.hasCrossedAboveLower &&
                !validator.hasBuyTouchedMiddle &&
                currentPrice > currentLowerBand) {
                validator.executeRangeTrade(ORDER_TYPE_BUY, currentPrice,
                                            validator.lotsOneHalf,
                                            RangeBuyMagicNumber);
                validator.hasCrossedAboveLower = true;
            }
            // thrid buy
            if (validator.hasBuyCloseMiddle && !validator.hasBuyTouchedMiddle &&
                !validator.hasTouchedUpper &&
                currentPrice >= currentMiddleBand) {
                validator.executeRangeTrade(ORDER_TYPE_BUY, currentPrice,
                                            validator.lotsOneHalf,
                                            RangeBuyMagicNumber);
                validator.hasBuyTouchedMiddle = true;
            }
        }

        //--- take profit and stop loss
        // close buy 50%
        if (validator.hasLowerBroken && validator.hasCrossedAboveLower &&
            currentPrice + validator.calculatePips(TakeProfitGap) >=
                currentMiddleBand) {
            validator.closePositionHalf(ORDER_TYPE_CLOSE_BY, POSITION_TYPE_BUY);
            validator.hasLowerBroken = false;
            validator.hasCrossedAboveLower = false;
            validator.hasBuyCloseMiddle = true;
        }
        // close all buy positions
        if (validator.hasBuyTouchedMiddle && validator.hasBuyCloseMiddle &&
            prevClosePrice > prevUpperBand && currentPrice < currentUpperBand) {
            validator.closeAllBuyPosition();
        }
        // buy positions all close -> touched middle and cross below middle
        // line?
        if (validator.hasBuyCloseMiddle && prevClosePrice > prevMiddleBand &&
            currentPrice <
                currentMiddleBand - validator.calculatePips(StopLossGap)) {
            validator.closeAllBuyPosition();
        }
        
		//--- sell order section
        if (!validator.hasOpenRangeBuyPositions && rangeTradingSignal) {
            // first sell
            if (prevClosePrice > prevUpperBand &&
                currentPrice > currentUpperBand + validator.calculatePips(
                                                      FirstSellPointsGap) &&
                validator.checkActiveSellPosition()) {
                validator.executeRangeTrade(ORDER_TYPE_SELL, currentPrice,
                                            validator.lotsOneTenth,
                                            RangeSellMagicNumber);
                validator.hasUpperBroken = true;
                validator.hasOpenRangeSellPositions = true;
            }
            // second sell
            if (!validator.hasSellCloseMiddle && validator.hasUpperBroken &&
                !validator.hasCrossedBelowUpper &&
                !validator.hasSellTouchedMiddle &&
                currentPrice < currentUpperBand) {
                validator.executeRangeTrade(ORDER_TYPE_SELL, currentPrice,
                                            validator.lotsOneHalf,
                                            RangeSellMagicNumber);
                validator.hasCrossedBelowUpper = true;
            }
            // thrid sell
            if (validator.hasSellCloseMiddle &&
                !validator.hasSellTouchedMiddle &&
                currentPrice <= currentMiddleBand) {
                validator.executeRangeTrade(ORDER_TYPE_SELL, currentPrice,
                                            validator.lotsOneHalf,
                                            RangeSellMagicNumber);
                validator.hasSellTouchedMiddle = true;
            }
            //---
        }
        //--- take profit and stop loss
        // close sell 50%
        if (validator.hasUpperBroken && validator.hasCrossedBelowUpper &&
            currentPrice <=
                currentMiddleBand + validator.calculatePips(TakeProfitGap)) {
            validator.closePositionHalf(ORDER_TYPE_CLOSE_BY,
                                        POSITION_TYPE_SELL);
            validator.hasUpperBroken = false;
            validator.hasCrossedBelowUpper = false;
            validator.hasSellCloseMiddle = true;
        }
        // close all sell positions
        if (validator.hasSellTouchedMiddle && validator.hasSellCloseMiddle &&
            prevClosePrice < prevLowerBand && currentPrice > currentLowerBand) {
            validator.closeAllSellPosition();
        }
        // sell positions all close -> touched middle and cross above middle
        // line ?
        if (validator.hasSellCloseMiddle && prevClosePrice < prevMiddleBand &&
            currentPrice >
                currentMiddleBand + validator.calculatePips(StopLossGap)) {
            validator.closeAllSellPosition();
        }
		
    }
}

/*

What's added in 0.11v

sell positions all close -> touched middle and cross above middle line ?
buy positions all close -> touched middle and cross below middle line ?

*/