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
input ulong RangeBuyMagicNumber = 2147483647;
input ENUM_TIMEFRAMES ChartPeriod = PERIOD_H1;
input ENUM_ORDER_FILLING OrderFilling = 1;
input group "---------- Bollinger bands variable ----------";
input int BandsPeriod = 20;
input int BandsShift = 0;
input double Deviation = 2.0;
input ENUM_APPLIED_PRICE AppliedPrice = PRICE_CLOSE;
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
input int FirstSellPointsGap = 150;
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

class TradeValidator {
   public:
    string symbol;
    //---
    // buy position variable
    bool hasLowerBroken, hasCrossedAboveLower, hasBuyTouchedMiddle, hasTouchedUpper;
    bool hasBuyCloseMiddle;
    // sell position variable
    bool hasUpperBroken, hasCrossedBelowUpper, hasSellTouchedMiddle,
        hasTouchedLower;
    bool hasSellCloseMiddle;
    //---
    double balance;
    double equity;
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

    bool checkActiveBuyPosition();
    bool checkActiveSellPosition();

    bool executeTrade(ENUM_ORDER_TYPE type, double currentPrice, double volume);
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

bool TradeValidator::executeTrade(ENUM_ORDER_TYPE type, double currentPrice,
                                  double volume) {
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
    request.magic = RangeBuyMagicNumber;
    request.comment = "";

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
    for (int i = PositionsTotal(); i >= 0; i--) {
        if (positionInfo.SelectByIndex(i)) {
            ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
            if (ptype == positionType) {
                double volume =
                    MathCeil(positionInfo.Volume() / 2.0 * 100) / 100;
                Print("info volume : ", positionInfo.Volume());
                Print("volume : ", volume);
                if (positionInfo.Symbol() == symbol &&
                    positionInfo.Magic() == RangeBuyMagicNumber) {
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
                    trade.PositionClosePartial(positionInfo.Ticket(), volume,
                                               0);
                }
            }
        }
    }

    hasLowerBroken = hasCrossedAboveLower = hasBuyTouchedMiddle = hasTouchedUpper =
        hasBuyCloseMiddle = false;
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
                    positionInfo.Magic() == RangeBuyMagicNumber) {
                    trade.PositionClosePartial(positionInfo.Ticket(), volume,
                                               0);
                }
            }
        }
    }
    hasUpperBroken = hasCrossedBelowUpper = hasSellTouchedMiddle = hasTouchedLower =
        hasSellCloseMiddle = false;
}

CTrade trade;
CSymbolInfo symbolInfo;
CPositionInfo positionInfo;
CHistoryOrderInfo historyOrderInfo;
CDealInfo dealInfo;

TradeValidator validator;

double upperBand[], middleBand[], lowerBand[];
int handleBand;

int OnInit() {
    handleBand = iBands(_Symbol, ChartPeriod, BandsPeriod, BandsShift,
                        Deviation, AppliedPrice);
	
	ArraySetAsSeries(middleBand, true);
	ArraySetAsSeries(lowerBand, true);
	ArraySetAsSeries(upperBand, true);
	
    if (handleBand == INVALID_HANDLE) {
        Print("Failed to create Bollinger Bands");
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

    if (CopyBuffer(handleBand, BASE_LINE, 0, 3, middleBand) < 3 ||
        CopyBuffer(handleBand, LOWER_BAND, 0, 3, lowerBand) < 3 ||
        CopyBuffer(handleBand, UPPER_BAND, 0, 3, upperBand) < 3) {
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

    // previous candle info
    double prevClosePrice = iClose(_Symbol, ChartPeriod, PREVIOUS);
    double prevOpenPrice = iOpen(_Symbol, ChartPeriod, PREVIOUS);
    double prevHighPrice = iHigh(_Symbol, ChartPeriod, PREVIOUS);
    double prevLowPrice = iLow(_Symbol, ChartPeriod, PREVIOUS);

    // current ask and bid price and mean price values
    double bidPrice = validator.getBid();
    double askPrice = validator.getAsk();
    double currentPrice = (validator.getAsk() + validator.getBid()) / 2.0;
	
    //--- order buy and sell
    //--- buy order section
    // first buy
    if (!validator.hasBuyCloseMiddle && prevClosePrice < prevLowerBand &&
        currentPrice <
            currentLowerBand - validator.calculatePips(FirstBuyPointsGap) &&
        validator.checkActiveBuyPosition()) {
        validator.executeTrade(ORDER_TYPE_BUY, currentPrice,
                               validator.lotsOneTenth);
        validator.hasLowerBroken = true;
    }
    // second buy
    if (!validator.hasBuyCloseMiddle && validator.hasLowerBroken &&
        !validator.hasCrossedAboveLower && !validator.hasBuyTouchedMiddle &&
        !validator.hasTouchedUpper && currentPrice > currentLowerBand) {
        validator.executeTrade(ORDER_TYPE_BUY, currentPrice,
                               validator.lotsOneHalf);
        validator.hasCrossedAboveLower = true;
    }
    // thrid buy
    if (validator.hasBuyCloseMiddle && !validator.hasBuyTouchedMiddle &&
        !validator.hasTouchedUpper && currentPrice >= currentMiddleBand) {
        validator.executeTrade(ORDER_TYPE_BUY, currentPrice,
                               validator.lotsOneHalf);
        validator.hasBuyTouchedMiddle = true;
    }
    //--- sell order section
    // first sell
    if (!validator.hasSellCloseMiddle && prevClosePrice > prevUpperBand &&
        currentPrice >
            currentUpperBand + validator.calculatePips(FirstSellPointsGap) &&
        validator.checkActiveSellPosition()) {
        validator.executeTrade(ORDER_TYPE_SELL, currentPrice,
                               validator.lotsOneTenth);
        validator.hasUpperBroken = true;
    }
    // second sell
    if (!validator.hasSellCloseMiddle && validator.hasUpperBroken &&
        !validator.hasCrossedBelowUpper && !validator.hasSellTouchedMiddle &&
        !validator.hasTouchedLower && currentPrice < currentUpperBand) {
        validator.executeTrade(ORDER_TYPE_SELL, currentPrice,
                               validator.lotsOneHalf);
        validator.hasCrossedBelowUpper = true;
    }
    // thrid sell
    if (validator.hasUpperBroken && validator.hasCrossedBelowUpper &&
        !validator.hasSellTouchedMiddle && !validator.hasTouchedLower &&
        currentPrice <= currentMiddleBand) {
        validator.executeTrade(ORDER_TYPE_SELL, currentPrice,
                               validator.lotsOneHalf);
        validator.hasSellTouchedMiddle = true;
    }
    //---

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
    // buy positions all close -> touched middle and cross below middle line ?
    if (validator.hasBuyCloseMiddle && prevClosePrice > prevMiddleBand &&
        currentPrice <
            currentMiddleBand - validator.calculatePips(StopLossGap)) {
        validator.closeAllBuyPosition();
    }

    // close sell 50%
    if (validator.hasUpperBroken && validator.hasCrossedBelowUpper &&
        currentPrice <=
            currentMiddleBand + validator.calculatePips(TakeProfitGap)) {
        validator.closePositionHalf(ORDER_TYPE_CLOSE_BY, POSITION_TYPE_SELL);
        validator.hasUpperBroken = false;
        validator.hasCrossedBelowUpper = false;
        validator.hasSellCloseMiddle = true;
    }
    // close all sell positions
    if (validator.hasSellTouchedMiddle && validator.hasSellCloseMiddle &&
        prevClosePrice < prevLowerBand && currentPrice > currentLowerBand) {
        validator.closeAllSellPosition();
    }
    // sell positions all close -> touched middle and cross above middle line ?
    if (validator.hasSellCloseMiddle && prevClosePrice < prevMiddleBand &&
        currentPrice >
            currentMiddleBand + validator.calculatePips(StopLossGap)) {
        validator.closeAllSellPosition();
    }
}

/*

What's added in 0.11v

sell positions all close -> touched middle and cross above middle line ?
buy positions all close -> touched middle and cross below middle line ?

*/