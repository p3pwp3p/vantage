//+------------------------------------------------------------------+
//|                                   Copyright 2024, Anonymous Ltd. |
//|                                        https://github.com/hayan2 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Anonymous Ltd."
#property link "https://github.com/hayan2"
#property version "0.20"

enum ENUM_ORDER_FILLING {
    Fire_or_kill = 0,
    Immediate_or_cancel = 1,
    Order_filling_return = 2
};

input group "---------- Trade Validation ----------";
input ulong MagicNumber = 2147483647;
input int MinimumBars = 100;
input double TradeMarginPercent = 10;
input ENUM_ORDER_FILLING OrderFilling = 1;
input int StopLoss = 1000;
input int TakeProfit = 0;
input int Slippage = 10;
input group "---------- Bollinger Bands variable ----------";
input int BandsPeriod = 30;
input int BandsShift = 0;
input double Deviation = 2.0;
input ENUM_APPLIED_PRICE AppliedPrice = PRICE_CLOSE;
input group "---------- Relative Strength Index variable ----------";
input int RsiPeriod = 13;
input int SellConditionRsi = 70;
input int BuyConditionRsi = 30;

const int COUNT_BANDS = 3;
const int COUNT_RSI = 3;
const int CURRENT = 0;
const int PREVIOUS = 1;
const double MINIMUM_LOTS = 0.01;

#include <Trade/SymbolInfo.mqh>
#include <Trade/Trade.mqh>

class TradeValidator {
   private:
    double balance;
    double equity;
    string symbol;
    double lots;
    double minLotSize;
    double maxLotSize;
    double point;
    double digits;
    
    void logValidationInfo(string message);

   public:
    TradeValidator();
    ~TradeValidator() {};

    bool loadSymbolInfo();
    void loadAccountInfo();
    void notEnoughEquity() { Print("Not enough equity."); }
    void notEnoughBalance() { Print("Not enough balance."); }

    bool checkHistory(int minimumBars);
    bool isInTester() { return MQLInfoInteger(MQL_TESTER) != 0; }

    bool calculateLots();

    bool hasOpenPositions() { return PositionsTotal() > 0; }
    bool hasOpenBuyPositions();
    bool hasOpenSellPositions();

    bool executeTrade(ENUM_ORDER_TYPE type, double currentPrice, double volume,
                      ulong magic);
	void closePositions(ENUM_ORDER_TYPE type, ENUM_POSITION_TYPE positionType);
    double validateStopLoss(ENUM_ORDER_TYPE type, double currentPrice);
    double validateTakeProfit(ENUM_ORDER_TYPE type, double currentPrice);

    double getBalance() { return balance; }
    double getEquity() { return equity; }
    string getSymbol() { return symbol; }
    double getLots() { return lots; }

    double getBid() { return SymbolInfoDouble(symbol, SYMBOL_BID); }
    double getAsk() { return SymbolInfoDouble(symbol, SYMBOL_ASK); }
};

TradeValidator::TradeValidator() { symbol = _Symbol; }

void TradeValidator::logValidationInfo(string message) {
	Print("[Validator] ", message);
}

bool TradeValidator::loadSymbolInfo() {
    // basic properties
    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    point = SymbolInfoDouble(symbol, SYMBOL_POINT);

    // trading properties
    minLotSize = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    maxLotSize = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

    // Protection against invalid data
    if (minLotSize <= 0) minLotSize = 0.01;
    if (maxLotSize <= 0) maxLotSize = 100.0;

    return true;
}

void TradeValidator::loadAccountInfo() {
    balance = AccountInfoDouble(ACCOUNT_BALANCE);
    equity = AccountInfoDouble(ACCOUNT_EQUITY);
}

bool TradeValidator::checkHistory(int minimumBars) {
    // check if enough bars are available for the current symbol/timeframe
    if (Bars(symbol, PERIOD_CURRENT) < MinimumBars) {
        logValidationInfo("WARNING: Not enough historical data. Required: " +
                          IntegerToString(MinimumBars) + ", Available: " +
                          IntegerToString(Bars(symbol, PERIOD_CURRENT)));
        return false;
    }

    return true;
}

bool TradeValidator::calculateLots() {
    double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    lots = MathCeil(balance / contractSize * (TradeMarginPercent / 100) * 100) / 100 - 0.01;
    if (lots < minLotSize) return false;
    return true;
}

bool TradeValidator::hasOpenBuyPositions() {
	for (int i = 0; i < PositionsTotal(); i++) {
		if (positionInfo.SelectByIndex(i)) {
			ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
			if (ptype == POSITION_TYPE_BUY) return true;
		}
	}
	return false;
}

bool TradeValidator::hasOpenSellPositions() {
	for (int i = 0; i < PositionsTotal(); i++) {
		if (positionInfo.SelectByIndex(i)) {
			ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
			if (ptype == POSITION_TYPE_SELL) return true;
		}
	}
	return false;
}

double TradeValidator::validateStopLoss(ENUM_ORDER_TYPE type, double currentPrice) {
	if (currentPrice <= 0.0) return 0.0;
    if (StopLoss <= 0.0) return 0.0;

    bool isBuy =
        (type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT ||
         type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT);
    bool isSell =
        (type == ORDER_TYPE_SELL || type == ORDER_TYPE_SELL_LIMIT ||
         type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_SELL_STOP_LIMIT);
	
    if (isBuy) return NormalizeDouble(currentPrice - (double)StopLoss * _Point, _Digits);
    if (isSell) return NormalizeDouble(currentPrice + (double)StopLoss * _Point, _Digits);

    return 0.0;
}

double TradeValidator::validateTakeProfit(ENUM_ORDER_TYPE type, double currentPrice) {
	if (currentPrice <= 0.0) return 0.0;
    if (TakeProfit <= 0.0) return 0.0;

    bool isBuy =
        (type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT ||
         type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT);
    bool isSell =
        (type == ORDER_TYPE_SELL || type == ORDER_TYPE_SELL_LIMIT ||
         type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_SELL_STOP_LIMIT);

    if (isBuy) return NormalizeDouble(currentPrice + TakeProfit * _Point, _Digits);
    if (isSell) return NormalizeDouble(currentPrice - TakeProfit * _Point, _Digits);

    return 0.0;
}

bool TradeValidator::executeTrade(ENUM_ORDER_TYPE type, double currentPrice,
                                  double volume, ulong magic) {
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

	request.action = TRADE_ACTION_DEAL;
    request.type = type;
	request.volume = volume;
	request.symbol = symbol;
	request.price = currentPrice;
    request.sl = validateStopLoss(type, currentPrice);
	request.tp = validateTakeProfit(type, currentPrice);

	if (OrderFilling == 0)
        request.type_filling = ORDER_FILLING_FOK;
    else if (OrderFilling == 1)
        request.type_filling = ORDER_FILLING_IOC;
    else if (OrderFilling == 2)
        request.type_filling = ORDER_FILLING_RETURN;

	request.deviation = Slippage;
	request.magic = magic;
	request.comment = "";

	bool success = OrderSend(request, result);

	if (success && result.retcode == TRADE_RETCODE_DONE) {
		Print("Trade successfully executed. Ticket : ", result.order);
		return true;
	}
	else {
		Print("Trade error : ", result.retcode);
		Print("Description : ", result.comment);
		return false;
	}
}

void TradeValidator::closePositions(ENUM_ORDER_TYPE type, ENUM_POSITION_TYPE positionType) {
	Print("close");
	for (int i = 0; i < PositionsTotal(); i++)  {
		ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
		if (ptype == positionType && positionInfo.Symbol() == symbol && positionInfo.Magic() == MagicNumber) {
			trade.PositionClose(positionInfo.Ticket(), 0);
		}
	}
}

CTrade trade;
CSymbolInfo symbolInfo;
CPositionInfo positionInfo;
CHistoryOrderInfo historyOrderInfo;
CDealInfo dealInfo;

TradeValidator validator;
int handleBand, handleRsi;
double upperBand[], middleBand[], lowerBand[], rsi[];

int OnInit() {
    // load indicators
    handleBand = iBands(_Symbol, PERIOD_CURRENT, BandsPeriod, BandsShift,
                        Deviation, AppliedPrice);
    handleRsi = iRSI(_Symbol, PERIOD_CURRENT, RsiPeriod, AppliedPrice);
	
    ArraySetAsSeries(upperBand, true);
    ArraySetAsSeries(middleBand, true);
    ArraySetAsSeries(lowerBand, true);
    ArraySetAsSeries(rsi, true);

    if (handleBand == INVALID_HANDLE || handleRsi == INVALID_HANDLE) {
        Print("Error loading indicators : ", GetLastError());
        return INIT_FAILED;
    }

    // check if enough historical data is available
    if (!validator.checkHistory(handleBand + handleRsi)) {
        Print("Not enough historical data for indicator calculation.");
        // continue in validation mode, otherwise fail
        // if (!validator.isInTester()) return INIT_FAILED;
    }

    Print("Mean Reversion Trend EA initialized. Symbol: ", _Symbol,
          ", Timeframe: ", EnumToString(Period()));

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {}

void OnTick() {
    if (CopyBuffer(handleBand, BASE_LINE, 0, COUNT_BANDS, middleBand) <
            COUNT_BANDS ||
        CopyBuffer(handleBand, LOWER_BAND, 0, COUNT_BANDS, lowerBand) <
            COUNT_BANDS ||
        CopyBuffer(handleBand, UPPER_BAND, 0, COUNT_BANDS, upperBand) <
            COUNT_BANDS ||
        CopyBuffer(handleRsi, 0, 0, COUNT_RSI, rsi) < COUNT_RSI) {
        Print("Error copying indicators values : ", GetLastError());
        return;
    }
	
	validator.loadAccountInfo();
    if (!validator.calculateLots()) validator.notEnoughBalance();

    double currentMiddleBand = middleBand[CURRENT];
    double currentUpperBand = upperBand[CURRENT];
    double currentLowerBand = lowerBand[CURRENT];
    double currentRSI = rsi[CURRENT];

    double prevMiddleBand = middleBand[PREVIOUS];
    double prevUpperBand = upperBand[PREVIOUS];
    double prevLowerBand = lowerBand[PREVIOUS];
    double prevRsi = rsi[PREVIOUS];

    double currentPrice = (validator.getAsk() + validator.getBid()) / 2;

    double prevClosePrice =
        iClose(validator.getSymbol(), PERIOD_CURRENT, PREVIOUS);
    double prevOpenPrice =
        iOpen(validator.getSymbol(), PERIOD_CURRENT, PREVIOUS);
    double prevHighPrice =
        iHigh(validator.getSymbol(), PERIOD_CURRENT, PREVIOUS);
    double prevLowPrice = iLow(validator.getSymbol(), PERIOD_CURRENT, PREVIOUS);

    bool buySignal =
        prevLowerBand > prevClosePrice && prevRsi < BuyConditionRsi;
    bool sellSignal =
        prevUpperBand < prevClosePrice && prevRsi > SellConditionRsi;


	if (!validator.hasOpenPositions()) {
		if (buySignal) {
			validator.executeTrade(ORDER_TYPE_BUY, validator.getBid(), validator.getLots(), MagicNumber);
		}
		if (sellSignal) {
			validator.executeTrade(ORDER_TYPE_SELL, validator.getAsk(), validator.getLots(), MagicNumber);
		}
	}
	
	if (validator.hasOpenBuyPositions()) {
		if (prevClosePrice > prevUpperBand && currentPrice < currentUpperBand) {
			validator.closePositions(ORDER_TYPE_CLOSE_BY, POSITION_TYPE_BUY);
		}
	}
	if (validator.hasOpenSellPositions()) {
		if (prevClosePrice < prevLowerBand && currentPrice > currentLowerBand) {
			validator.closePositions(ORDER_TYPE_CLOSE_BY, POSITION_TYPE_SELL);
		}
	}
	
}

/*

Bollinger Bands(30) + RSI(13)

*/