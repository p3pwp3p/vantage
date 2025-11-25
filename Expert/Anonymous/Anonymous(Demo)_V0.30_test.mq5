//+------------------------------------------------------------------+
//|                                   Copyright 2024, Anonymous Ltd. |
//|                                        https://github.com/hayan2 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Anonymous Ltd."
#property link "https://github.com/hayan2"
#property version "1.00"

enum ENUM_ORDER_FILLING {
    Fire_or_kill = 0,
    Immediate_or_cancel = 1,
    Order_filling_return = 2
};

input group "---------- Trade Validation ----------";
input ulong MagicNumber = 2147483647;
input double Lots = 0.01;
input int MartingalePointGap = 1000;
input int TpPoints = 0;
input int SlPoints = 0;
input int TslPoints = 100;
input int TslTriggerPoints = 200;
input int IndicatorStopTime = 3;
input int MinimumBars = 100;
input int Slippage = 10;
input ENUM_ORDER_FILLING OrderFilling = 1;
input group "---------- Moving Average Validation ----------";
input int FastMAPeriod = 50;
input int SlowMAPeriod = 200;
input ENUM_MA_METHOD MAMode = MODE_SMA;
input ENUM_APPLIED_PRICE AppliedPrice = PRICE_CLOSE;

#include <Trade/SymbolInfo.mqh>
#include <Trade/Trade.mqh>

const int CURRENT = 0;
const int PREVIOUS = 1;

class TradeValidator {
   private:
    string symbol;
    double balance, equity;
    double buyLotSize, sellLotSize, minLotSize, maxLotSize;
    double lastBuyPrice, lastSellPrice;
    double point, digits;
    int buyPositionCount, sellPositionCount;
    int totalBars;

    void logValidationInfo(string message);

   public:
    TradeValidator();
    ~TradeValidator() {};

    void refresh();

    bool loadSymbolInfo();
    void loadAccountInfo();
    void notEnoughEquity() { Print("Not enough equity."); }
    void notEnoughBalance() { Print("Not enough balance."); }

    bool checkHistory(int minimumBars);
    bool isInTester() { return MQLInfoInteger(MQL_TESTER) != 0; }

    bool hasOpenPositions() { return PositionsTotal() > 0; }
    bool hasOpenBuyPositions();
    bool hasOpenSellPositions();

    void countBuyPositions();
    void countSellPositions();

    void updateLastBuyPrice(double price);
    void updateLastSellPrice(double price);
    void updateBuyLotSize(bool flag);
    void updateSellLotSize(bool flag);
    void updateTotalBars(int bars);

    double validateStopLoss(ENUM_ORDER_TYPE type, double currentPrice);
    double validateTakeProfit(ENUM_ORDER_TYPE type, double currentPrice);
    void validateTrailingStop();
    bool executeTrade(ENUM_ORDER_TYPE type, double currentPrice, double volume,
                      ulong magic);
    void closePositions(ENUM_ORDER_TYPE type, ENUM_POSITION_TYPE positionType);

    string getSymbol() { return symbol; }
    double getBalance() { return balance; }
    double getEquity() { return equity; }
    double getBuyLotSize() { return buyLotSize; }
    double getSellLotSize() { return sellLotSize; }
    double getLastBuyPrice() { return lastBuyPrice; }
    double getLastSellPrice() { return lastSellPrice; }
    double getPoint() { return point; }
    double getDigits() { return digits; }
    int getTotalBars() { return totalBars; }
    double getCountBuyPositions();
    double getCountSellPositions();

    double getBid() { return SymbolInfoDouble(symbol, SYMBOL_BID); }
    double getAsk() { return SymbolInfoDouble(symbol, SYMBOL_ASK); }
};

TradeValidator::TradeValidator() {
    symbol = _Symbol;
    buyLotSize = Lots;
    sellLotSize = Lots;
    totalBars = iBars(_Symbol, PERIOD_CURRENT);
}

void TradeValidator::refresh() {
    countBuyPositions();
    countSellPositions();
}

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

void TradeValidator::countBuyPositions() {
	int tmp = 0;
    for (int i = 0; i < PositionsTotal(); i++) {
        if (positionInfo.SelectByIndex(i)) {
            ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
            if (ptype == POSITION_TYPE_BUY) tmp++;
        }
    }
	buyPositionCount = tmp;
}

void TradeValidator::countSellPositions() {
	int tmp = 0;
    for (int i = 0; i < PositionsTotal(); i++) {
        if (positionInfo.SelectByIndex(i)) {
            ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
            if (ptype == POSITION_TYPE_SELL) tmp++;
        }
    }
	sellPositionCount = tmp;
}

double TradeValidator::getCountBuyPositions() {
    countBuyPositions();
    return buyPositionCount;
}

double TradeValidator::getCountSellPositions() {
    countSellPositions();
    return sellPositionCount;
}

void TradeValidator::updateBuyLotSize(bool flag) {
    // trade ?
    if (flag) {
        buyLotSize = hasOpenBuyPositions() ? buyLotSize * 2 : Lots;
    } else {
        buyLotSize = hasOpenBuyPositions() ? buyLotSize : Lots;
    }
}

void TradeValidator::updateSellLotSize(bool flag) {
    if (flag) {
        sellLotSize = hasOpenSellPositions() ? sellLotSize * 2 : Lots;
    } else {
        sellLotSize = hasOpenSellPositions() ? sellLotSize : Lots;
    }
}

void TradeValidator::updateLastBuyPrice(double price) { lastBuyPrice = price; }

void TradeValidator::updateLastSellPrice(double price) {
    lastSellPrice = price;
}

void TradeValidator::updateTotalBars(int bars) { totalBars = bars; }

double TradeValidator::validateStopLoss(ENUM_ORDER_TYPE type,
                                        double currentPrice) {
    if (currentPrice <= 0.0) return 0.0;
    if (SlPoints <= 0.0) return 0.0;

    bool isBuy =
        (type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT ||
         type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT);
    bool isSell =
        (type == ORDER_TYPE_SELL || type == ORDER_TYPE_SELL_LIMIT ||
         type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_SELL_STOP_LIMIT);

    if (isBuy)
        return NormalizeDouble(currentPrice - (double)SlPoints * _Point,
                               _Digits);
    if (isSell)
        return NormalizeDouble(currentPrice + (double)SlPoints * _Point,
                               _Digits);

    return 0.0;
}

double TradeValidator::validateTakeProfit(ENUM_ORDER_TYPE type,
                                          double currentPrice) {
    if (currentPrice <= 0.0) return 0.0;
    if (TpPoints <= 0.0) return 0.0;

    bool isBuy =
        (type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT ||
         type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT);
    bool isSell =
        (type == ORDER_TYPE_SELL || type == ORDER_TYPE_SELL_LIMIT ||
         type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_SELL_STOP_LIMIT);

    if (isBuy)
        return NormalizeDouble(currentPrice + TpPoints * _Point, _Digits);
    if (isSell)
        return NormalizeDouble(currentPrice - TpPoints * _Point, _Digits);

    return 0.0;
}


void TradeValidator::validateTrailingStop() {
    if (hasOpenPositions() && TslPoints > 0.0) {
        if (buyPositionCount == 1) {
            for (int i = 0; i < PositionsTotal(); i++) {
                ulong posTicket = PositionGetTicket(i);
                long posType = PositionGetInteger(POSITION_TYPE);

                if (PositionSelectByTicket(posTicket)) {
                    if (PositionGetString(POSITION_SYMBOL) == symbol &&
                        posType == POSITION_TYPE_BUY) {
                        double posOpenPrice =
                            PositionGetDouble(POSITION_PRICE_OPEN);
                        double posSl = PositionGetDouble(POSITION_SL);
                        double posTp = PositionGetDouble(POSITION_TP);
						
						if (getBid() > posOpenPrice + TslTriggerPoints * point) {
							double sl = getBid() - TslPoints * point;

							if (sl > posSl) {
								if (trade.PositionModify(posTicket, sl, posTp)) {
									Print(__FUNCTION__ " > Position ticket # ", posTicket, " was modified.");
								}
							}
						}
                    }
                }
            }
        }
		else {

		}
        if (sellPositionCount == 1) {
            for (int i = 0; i < PositionsTotal(); i++) {
                ulong posTicket = PositionGetTicket(i);
				long posType = PositionGetInteger(POSITION_TYPE);
				
                if (PositionSelectByTicket(posTicket)) {
                    if (PositionGetString(POSITION_SYMBOL) == symbol && posType == POSITION_TYPE_SELL) {
                        long posType = PositionGetInteger(POSITION_TYPE);
                        double posOpenPrice =
                            PositionGetDouble(POSITION_PRICE_OPEN);
                        double posSl = PositionGetDouble(POSITION_SL);
                        double posTp = PositionGetDouble(POSITION_TP);

						if (getAsk() < posOpenPrice - TslTriggerPoints * point) {
							double sl = getAsk() + TslPoints * point;

							if (sl < posSl || posSl == 0.0) {
								if (trade.PositionModify(posTicket, sl, posTp)) {
									Print(__FUNCTION__ " > Position ticket # ", posTicket, " was modified.");
								}
							}
						}
                    }
                }
            }
        }
		else {
			
		}
    }
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
    } else {
        Print("Trade error : ", result.retcode);
        Print("Description : ", result.comment);
        return false;
    }
}

void TradeValidator::closePositions(ENUM_ORDER_TYPE type,
                                    ENUM_POSITION_TYPE positionType) {
    for (int i = 0; i < PositionsTotal(); i++) {
        ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
        if (ptype == positionType && positionInfo.Symbol() == symbol &&
            positionInfo.Magic() == MagicNumber) {
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
int totalBars;
int handleFastMA, handleSlowMA;
double fastMA[], slowMA[];

int OnInit() {
    handleFastMA =
        iMA(_Symbol, PERIOD_CURRENT, FastMAPeriod, 0, MAMode, AppliedPrice);
    handleSlowMA =
        iMA(_Symbol, PERIOD_CURRENT, SlowMAPeriod, 0, MAMode, AppliedPrice);

    if (handleFastMA == INVALID_HANDLE || handleSlowMA == INVALID_HANDLE) {
        Print("Failed to create MA.", GetLastError());
        return INIT_FAILED;
    }

    validator.loadSymbolInfo();

    ArraySetAsSeries(fastMA, true);
    ArraySetAsSeries(slowMA, true);

    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {}

void OnTick() {
    validator.loadAccountInfo();
	validator.validateTrailingStop();
    int currentBars = iBars(_Symbol, PERIOD_CURRENT);
    double bid = validator.getBid();
    double ask = validator.getAsk();
    bool hasOpenBuyPositions = validator.hasOpenBuyPositions(),
         hasOpenSellPositions = validator.hasOpenSellPositions();
    int totalBuyPositions = 0, totalSellPositions = 0;

    if (currentBars != validator.getTotalBars()) {
        validator.refresh();
        validator.updateBuyLotSize(false);
        validator.updateSellLotSize(false);
        validator.updateTotalBars(currentBars);

        if (CopyBuffer(handleFastMA, 0, 1, IndicatorStopTime, fastMA) <
                IndicatorStopTime ||
            CopyBuffer(handleSlowMA, 0, 1, IndicatorStopTime, slowMA) <
                IndicatorStopTime) {
            Print("Failed copying indicator values. ", GetLastError());
            return;
        }

        bool buySignal = fastMA[PREVIOUS] < slowMA[PREVIOUS] &&
                         fastMA[CURRENT] > slowMA[CURRENT];
        bool sellSignal = fastMA[PREVIOUS] > slowMA[PREVIOUS] &&
                          fastMA[CURRENT] < slowMA[CURRENT];

        if (sellSignal) {
            // sell signal
            if (hasOpenSellPositions &&
                validator.getLastSellPrice() <
                    ask - MartingalePointGap * validator.getPoint()) {
                double volume = validator.getSellLotSize();
                validator.executeTrade(ORDER_TYPE_SELL, ask, volume,
                                       MagicNumber);
                validator.updateLastSellPrice(ask);
                validator.updateSellLotSize(true);
            } else if (!hasOpenSellPositions) {
                double volume = validator.getSellLotSize();
                validator.executeTrade(ORDER_TYPE_SELL, ask, volume,
                                       MagicNumber);
                validator.updateLastSellPrice(ask);
                validator.updateSellLotSize(true);
            }
        }
        if (buySignal) {
            // buy signal
            if (hasOpenBuyPositions && validator.getLastBuyPrice() >
                                           bid + MartingalePointGap * _Point) {
                double volume = validator.getBuyLotSize();
                validator.executeTrade(ORDER_TYPE_BUY, bid, volume,
                                       MagicNumber);
                validator.updateLastBuyPrice(bid);
                validator.updateBuyLotSize(true);
            } else if (!hasOpenBuyPositions) {
                double volume = validator.getBuyLotSize();
                validator.executeTrade(ORDER_TYPE_BUY, bid, volume,
                                       MagicNumber);
                validator.updateLastBuyPrice(bid);
                validator.updateBuyLotSize(true);
            }
        }
    }
}

/*

        Simple Fast MA(50) + Simple Slow MA(200), Martingale trading strategy.
        Use Trailing stop.

*/