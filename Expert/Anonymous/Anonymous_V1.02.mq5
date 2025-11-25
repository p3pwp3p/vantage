//+------------------------------------------------------------------+
//|                                   Copyright 2024, Anonymous Ltd. |
//|                                        https://github.com/hayan2 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Anonymous Ltd."
#property link "https://github.com/hayan2"
#property version "1.02"

enum ENUM_ORDER_FILLING {
    Fire_or_kill = 0,
    Immediate_or_cancel = 1,
    Order_filling_return = 2
};

input group "---------- Section1 ----------";
input string EURUSD_SYMBOL = "EURUSD";			// EURUSD Symbol name
input string GBPAUD_SYMBOL = "GBPAUD";			// GBPAUD Symbol name

const ulong MagicNumber = 2147483647;
const double Lots = 0.01;
const double EURUSDTradeMarginPercent = 170;
const int EURUSDMartingalePointGap = 1000;
const double EURUSDLotsMultiple = 2.33;
const int TpPoints = 0;
const int SlPoints = 0;
const int TslPoints = 100;
const int TslTriggerPoints = 200;
const int IndicatorStopTime = 3;
const int MinimumBars = 100;
const int Slippage = 10;
const ENUM_ORDER_FILLING OrderFilling = 1;
const int FastMAPeriod = 50;
const int SlowMAPeriod = 200;
const ENUM_MA_METHOD MAMode = MODE_SMA;
const ENUM_APPLIED_PRICE AppliedPrice = PRICE_CLOSE;

const double GBPAUDTradeMarginPercent = 120;
const int GBPAUDMartingalePointGap = 1000;
const double GBPAUDLotsMultiple = 2.33;


#include <Trade/SymbolInfo.mqh>
#include <Trade/Trade.mqh>

const int CURRENT = 0;
const int PREVIOUS = 1;

class EURUSDTradeValidator {
   private:
    string symbol;
    double balance, equity;
    double buyLotSize, sellLotSize, minLotSize, maxLotSize, marginPerLotSize;
    double lastBuyPrice, lastSellPrice;
    double point, digits;
    int buyPositionCount, sellPositionCount;
    int totalBars;

    void logValidationInfo(string message);

   public:
    EURUSDTradeValidator();
    ~EURUSDTradeValidator() {};

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

    bool validateLotSize();
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

class GBPAUDTradeValidator {
   private:
    string symbol;
    double balance, equity;
    double buyLotSize, sellLotSize, minLotSize, maxLotSize, marginPerLotSize;
    double lastBuyPrice, lastSellPrice;
    double point, digits;
    int buyPositionCount, sellPositionCount;
    int totalBars;

    void logValidationInfo(string message);

   public:
    GBPAUDTradeValidator();
    ~GBPAUDTradeValidator() {};

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

    bool validateLotSize();
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

EURUSDTradeValidator::EURUSDTradeValidator() {
    symbol = EURUSD_SYMBOL;
    buyLotSize = Lots;
    sellLotSize = Lots;
    totalBars = iBars(EURUSD_SYMBOL, PERIOD_CURRENT);
}

void EURUSDTradeValidator::refresh() {
    countBuyPositions();
    countSellPositions();
}

void EURUSDTradeValidator::logValidationInfo(string message) {
    Print("[Validator] ", message);
}

bool EURUSDTradeValidator::loadSymbolInfo() {
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

void EURUSDTradeValidator::loadAccountInfo() {
    balance = AccountInfoDouble(ACCOUNT_BALANCE);
    equity = AccountInfoDouble(ACCOUNT_EQUITY);
}

bool EURUSDTradeValidator::checkHistory(int minimumBars) {
    // check if enough bars are available for the current symbol/timeframe
    if (Bars(symbol, PERIOD_CURRENT) < MinimumBars) {
        logValidationInfo("WARNING: Not enough historical data. Required: " +
                          IntegerToString(MinimumBars) + ", Available: " +
                          IntegerToString(Bars(symbol, PERIOD_CURRENT)));
        return false;
    }

    return true;
}

bool EURUSDTradeValidator::hasOpenBuyPositions() {
    for (int i = 0; i < PositionsTotal(); i++) {
        if (positionInfo.SelectByIndex(i)) {
            if (symbol == positionInfo.Symbol()) {
                ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
                if (ptype == POSITION_TYPE_BUY) return true;
            }
        }
    }
    return false;
}

bool EURUSDTradeValidator::hasOpenSellPositions() {
    for (int i = 0; i < PositionsTotal(); i++) {
        if (positionInfo.SelectByIndex(i)) {
            if (symbol == positionInfo.Symbol()) {
                ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
                if (ptype == POSITION_TYPE_SELL) return true;
            }
        }
    }
    return false;
}

void EURUSDTradeValidator::countBuyPositions() {
    int tmp = 0;
    for (int i = 0; i < PositionsTotal(); i++) {
        if (positionInfo.SelectByIndex(i)) {
            if (symbol == positionInfo.Symbol()) {
                ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
                if (ptype == POSITION_TYPE_BUY) tmp++;
            }
        }
    }
    buyPositionCount = tmp;
}

void EURUSDTradeValidator::countSellPositions() {
    int tmp = 0;
    for (int i = 0; i < PositionsTotal(); i++) {
        if (positionInfo.SelectByIndex(i)) {
            if (symbol == positionInfo.Symbol()) {
                ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
                if (ptype == POSITION_TYPE_SELL) tmp++;
            }
        }
    }
    sellPositionCount = tmp;
}

double EURUSDTradeValidator::getCountBuyPositions() {
    countBuyPositions();
    return buyPositionCount;
}

double EURUSDTradeValidator::getCountSellPositions() {
    countSellPositions();
    return sellPositionCount;
}

void EURUSDTradeValidator::updateBuyLotSize(bool flag) {
    // trade ?
    if (flag) {
        buyLotSize = hasOpenBuyPositions()
                         ? NormalizeDouble(buyLotSize * EURUSDLotsMultiple, 2)
                         : marginPerLotSize;
    } else {
        buyLotSize = hasOpenBuyPositions() ? buyLotSize : marginPerLotSize;
    }
}

void EURUSDTradeValidator::updateSellLotSize(bool flag) {
    if (flag) {
        sellLotSize = hasOpenSellPositions()
                          ? NormalizeDouble(sellLotSize * EURUSDLotsMultiple, 2)
                          : marginPerLotSize;
    } else {
        sellLotSize = hasOpenSellPositions() ? sellLotSize : marginPerLotSize;
    }
}

void EURUSDTradeValidator::updateLastBuyPrice(double price) {
    lastBuyPrice = price;
}

void EURUSDTradeValidator::updateLastSellPrice(double price) {
    lastSellPrice = price;
}

void EURUSDTradeValidator::updateTotalBars(int bars) { totalBars = bars; }

bool EURUSDTradeValidator::validateLotSize() {
    double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    marginPerLotSize =
        MathCeil(balance / contractSize * (EURUSDTradeMarginPercent / 100) * 100) /
            100 -
        0.01;
    if (marginPerLotSize < minLotSize) return false;
    return true;
}

double EURUSDTradeValidator::validateStopLoss(ENUM_ORDER_TYPE type,
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

double EURUSDTradeValidator::validateTakeProfit(ENUM_ORDER_TYPE type,
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

void EURUSDTradeValidator::validateTrailingStop() {
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

                        if (getBid() >
                            posOpenPrice + TslTriggerPoints * point) {
                            double sl = NormalizeDouble(
                                getBid() - TslPoints * point, digits);

                            if (sl > posSl) {
                                if (trade.PositionModify(posTicket, sl,
                                                         posTp)) {
                                    Print(__FUNCTION__ " > Position ticket # ",
                                          posTicket, " was modified.");
                                }
                            }
                        }
                    }
                }
            }
        } else if (buyPositionCount > 1) {
            double positionValue = 0.0, positionLots = 0.0, tsl = 0.0;

            for (int i = 0; i < PositionsTotal(); i++) {
                ulong posTicket = PositionGetTicket(i);
                long posType = PositionGetInteger(POSITION_TYPE);

                if (PositionSelectByTicket(posTicket)) {
                    if (PositionGetString(POSITION_SYMBOL) == symbol &&
                        posType == POSITION_TYPE_BUY) {
                        positionValue +=
                            PositionGetDouble(POSITION_PRICE_OPEN) *
                            PositionGetDouble(POSITION_VOLUME);
                        positionLots += PositionGetDouble(POSITION_VOLUME);
                    }
                }
            }

            tsl = positionValue / positionLots;

            if (getBid() > tsl + TslTriggerPoints * point) {
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

                            double sl = NormalizeDouble(
                                getBid() - TslPoints * point, digits);
                            if (sl > posSl) {
                                if (trade.PositionModify(posTicket, sl,
                                                         posTp)) {
                                    Print(__FUNCTION__ " > Position ticket # ",
                                          posTicket,
                                          " was modified by multiple trailing "
                                          "stop.");
                                }
                            }
                        }
                    }
                }
            }
        }
        if (sellPositionCount == 1) {
            for (int i = 0; i < PositionsTotal(); i++) {
                ulong posTicket = PositionGetTicket(i);
                long posType = PositionGetInteger(POSITION_TYPE);

                if (PositionSelectByTicket(posTicket)) {
                    if (PositionGetString(POSITION_SYMBOL) == symbol &&
                        posType == POSITION_TYPE_SELL) {
                        double posOpenPrice =
                            PositionGetDouble(POSITION_PRICE_OPEN);
                        double posSl = PositionGetDouble(POSITION_SL);
                        double posTp = PositionGetDouble(POSITION_TP);

                        if (getAsk() <
                            posOpenPrice - TslTriggerPoints * point) {
                            double sl = NormalizeDouble(
                                getAsk() + TslPoints * point, digits);

                            if ((sl < posSl || posSl == 0.0) && sl != posSl) {
                                if (trade.PositionModify(posTicket, sl,
                                                         posTp)) {
                                    Print(__FUNCTION__ " > Position ticket # ",
                                          posTicket, " was modified.");
                                }
                            }
                        }
                    }
                }
            }
        } else if (sellPositionCount > 1) {
            double positionValue = 0.0, positionLots = 0.0, tsl = 0.0;

            for (int i = 0; i < PositionsTotal(); i++) {
                ulong posTicket = PositionGetTicket(i);
                long posType = PositionGetInteger(POSITION_TYPE);

                if (PositionSelectByTicket(posTicket)) {
                    if (PositionGetString(POSITION_SYMBOL) == symbol &&
                        posType == POSITION_TYPE_SELL) {
                        positionValue +=
                            PositionGetDouble(POSITION_PRICE_OPEN) *
                            PositionGetDouble(POSITION_VOLUME);
                        positionLots += PositionGetDouble(POSITION_VOLUME);
                    }
                }
            }

            tsl = positionValue / positionLots;

            if (getAsk() < tsl - TslTriggerPoints * point) {
                for (int i = 0; i < PositionsTotal(); i++) {
                    ulong posTicket = PositionGetTicket(i);
                    long posType = PositionGetInteger(POSITION_TYPE);

                    if (PositionSelectByTicket(posTicket)) {
                        if (PositionGetString(POSITION_SYMBOL) == symbol &&
                            posType == POSITION_TYPE_SELL) {
                            double posOpenPrice =
                                PositionGetDouble(POSITION_PRICE_OPEN);
                            double posSl = PositionGetDouble(POSITION_SL);
                            double posTp = PositionGetDouble(POSITION_TP);

                            double sl = NormalizeDouble(
                                getAsk() + TslPoints * point, digits);
                            if ((sl < posSl || posSl == 0.0) && sl != posSl) {
                                if (trade.PositionModify(posTicket, sl,
                                                         posTp)) {
                                    Print(__FUNCTION__ " > Position ticket # ",
                                          posTicket,
                                          " was modified by multiple trailing "
                                          "stop.");
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

bool EURUSDTradeValidator::executeTrade(ENUM_ORDER_TYPE type,
                                        double currentPrice, double volume,
                                        ulong magic) {
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

void EURUSDTradeValidator::closePositions(ENUM_ORDER_TYPE type,
                                          ENUM_POSITION_TYPE positionType) {
    for (int i = 0; i < PositionsTotal(); i++) {
        ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
        if (ptype == positionType && positionInfo.Symbol() == symbol &&
            positionInfo.Magic() == MagicNumber) {
            trade.PositionClose(positionInfo.Ticket(), 0);
        }
    }
}

GBPAUDTradeValidator::GBPAUDTradeValidator() {
    symbol = GBPAUD_SYMBOL;
    buyLotSize = Lots;
    sellLotSize = Lots;
    totalBars = iBars(GBPAUD_SYMBOL, PERIOD_CURRENT);
}

void GBPAUDTradeValidator::refresh() {
    countBuyPositions();
    countSellPositions();
}

void GBPAUDTradeValidator::logValidationInfo(string message) {
    Print("[Validator] ", message);
}

bool GBPAUDTradeValidator::loadSymbolInfo() {
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

void GBPAUDTradeValidator::loadAccountInfo() {
    balance = AccountInfoDouble(ACCOUNT_BALANCE);
    equity = AccountInfoDouble(ACCOUNT_EQUITY);
}

bool GBPAUDTradeValidator::checkHistory(int minimumBars) {
    // check if enough bars are available for the current symbol/timeframe
    if (Bars(symbol, PERIOD_CURRENT) < MinimumBars) {
        logValidationInfo("WARNING: Not enough historical data. Required: " +
                          IntegerToString(MinimumBars) + ", Available: " +
                          IntegerToString(Bars(symbol, PERIOD_CURRENT)));
        return false;
    }

    return true;
}

bool GBPAUDTradeValidator::hasOpenBuyPositions() {
    for (int i = 0; i < PositionsTotal(); i++) {
        if (positionInfo.SelectByIndex(i)) {
            if (symbol == positionInfo.Symbol()) {
                ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
                if (ptype == POSITION_TYPE_BUY) return true;
            }
        }
    }
    return false;
}

bool GBPAUDTradeValidator::hasOpenSellPositions() {
    for (int i = 0; i < PositionsTotal(); i++) {
        if (positionInfo.SelectByIndex(i)) {
            if (symbol == positionInfo.Symbol()) {
                ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
                if (ptype == POSITION_TYPE_SELL) return true;
            }
        }
    }
    return false;
}

void GBPAUDTradeValidator::countBuyPositions() {
    int tmp = 0;
    for (int i = 0; i < PositionsTotal(); i++) {
        if (positionInfo.SelectByIndex(i)) {
            if (symbol == positionInfo.Symbol()) {
                ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
                if (ptype == POSITION_TYPE_BUY) tmp++;
            }
        }
    }
    buyPositionCount = tmp;
}

void GBPAUDTradeValidator::countSellPositions() {
    int tmp = 0;
    for (int i = 0; i < PositionsTotal(); i++) {
        if (positionInfo.SelectByIndex(i)) {
            if (symbol == positionInfo.Symbol()) {
                ENUM_POSITION_TYPE ptype = positionInfo.PositionType();
                if (ptype == POSITION_TYPE_SELL) tmp++;
            }
        }
    }
    sellPositionCount = tmp;
}

double GBPAUDTradeValidator::getCountBuyPositions() {
    countBuyPositions();
    return buyPositionCount;
}

double GBPAUDTradeValidator::getCountSellPositions() {
    countSellPositions();
    return sellPositionCount;
}

void GBPAUDTradeValidator::updateBuyLotSize(bool flag) {
    // trade ?
    if (flag) {
        buyLotSize = hasOpenBuyPositions()
                         ? NormalizeDouble(buyLotSize * GBPAUDLotsMultiple, 2)
                         : marginPerLotSize;
    } else {
        buyLotSize = hasOpenBuyPositions() ? buyLotSize : marginPerLotSize;
    }
}

void GBPAUDTradeValidator::updateSellLotSize(bool flag) {
    if (flag) {
        sellLotSize = hasOpenSellPositions()
                          ? NormalizeDouble(sellLotSize * GBPAUDLotsMultiple, 2)
                          : marginPerLotSize;
    } else {
        sellLotSize = hasOpenSellPositions() ? sellLotSize : marginPerLotSize;
    }
}

void GBPAUDTradeValidator::updateLastBuyPrice(double price) {
    lastBuyPrice = price;
}

void GBPAUDTradeValidator::updateLastSellPrice(double price) {
    lastSellPrice = price;
}

void GBPAUDTradeValidator::updateTotalBars(int bars) { totalBars = bars; }

bool GBPAUDTradeValidator::validateLotSize() {
    double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    marginPerLotSize =
        MathCeil(balance / contractSize * (GBPAUDTradeMarginPercent / 100) * 100) /
            100 -
        0.01;
    if (marginPerLotSize < minLotSize) return false;
    return true;
}

double GBPAUDTradeValidator::validateStopLoss(ENUM_ORDER_TYPE type,
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

double GBPAUDTradeValidator::validateTakeProfit(ENUM_ORDER_TYPE type,
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

void GBPAUDTradeValidator::validateTrailingStop() {
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

                        if (getBid() >
                            posOpenPrice + TslTriggerPoints * point) {
                            double sl = NormalizeDouble(
                                getBid() - TslPoints * point, digits);

                            if (sl > posSl) {
                                if (trade.PositionModify(posTicket, sl,
                                                         posTp)) {
                                    Print(__FUNCTION__ " > Position ticket # ",
                                          posTicket, " was modified.");
                                }
                            }
                        }
                    }
                }
            }
        } else if (buyPositionCount > 1) {
            double positionValue = 0.0, positionLots = 0.0, tsl = 0.0;

            for (int i = 0; i < PositionsTotal(); i++) {
                ulong posTicket = PositionGetTicket(i);
                long posType = PositionGetInteger(POSITION_TYPE);

                if (PositionSelectByTicket(posTicket)) {
                    if (PositionGetString(POSITION_SYMBOL) == symbol &&
                        posType == POSITION_TYPE_BUY) {
                        positionValue +=
                            PositionGetDouble(POSITION_PRICE_OPEN) *
                            PositionGetDouble(POSITION_VOLUME);
                        positionLots += PositionGetDouble(POSITION_VOLUME);
                    }
                }
            }

            tsl = positionValue / positionLots;

            if (getBid() > tsl + TslTriggerPoints * point) {
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

                            double sl = NormalizeDouble(
                                getBid() - TslPoints * point, digits);
                            if (sl > posSl) {
                                if (trade.PositionModify(posTicket, sl,
                                                         posTp)) {
                                    Print(__FUNCTION__ " > Position ticket # ",
                                          posTicket,
                                          " was modified by multiple trailing "
                                          "stop.");
                                }
                            }
                        }
                    }
                }
            }
        }
        if (sellPositionCount == 1) {
            for (int i = 0; i < PositionsTotal(); i++) {
                ulong posTicket = PositionGetTicket(i);
                long posType = PositionGetInteger(POSITION_TYPE);

                if (PositionSelectByTicket(posTicket)) {
                    if (PositionGetString(POSITION_SYMBOL) == symbol &&
                        posType == POSITION_TYPE_SELL) {
                        double posOpenPrice =
                            PositionGetDouble(POSITION_PRICE_OPEN);
                        double posSl = PositionGetDouble(POSITION_SL);
                        double posTp = PositionGetDouble(POSITION_TP);

                        if (getAsk() <
                            posOpenPrice - TslTriggerPoints * point) {
                            double sl = NormalizeDouble(
                                getAsk() + TslPoints * point, digits);

                            if ((sl < posSl || posSl == 0.0) && sl != posSl) {
                                if (trade.PositionModify(posTicket, sl,
                                                         posTp)) {
                                    Print(__FUNCTION__ " > Position ticket # ",
                                          posTicket, " was modified.");
                                }
                            }
                        }
                    }
                }
            }
        } else if (sellPositionCount > 1) {
            double positionValue = 0.0, positionLots = 0.0, tsl = 0.0;

            for (int i = 0; i < PositionsTotal(); i++) {
                ulong posTicket = PositionGetTicket(i);
                long posType = PositionGetInteger(POSITION_TYPE);

                if (PositionSelectByTicket(posTicket)) {
                    if (PositionGetString(POSITION_SYMBOL) == symbol &&
                        posType == POSITION_TYPE_SELL) {
                        positionValue +=
                            PositionGetDouble(POSITION_PRICE_OPEN) *
                            PositionGetDouble(POSITION_VOLUME);
                        positionLots += PositionGetDouble(POSITION_VOLUME);
                    }
                }
            }

            tsl = positionValue / positionLots;

            if (getAsk() < tsl - TslTriggerPoints * point) {
                for (int i = 0; i < PositionsTotal(); i++) {
                    ulong posTicket = PositionGetTicket(i);
                    long posType = PositionGetInteger(POSITION_TYPE);

                    if (PositionSelectByTicket(posTicket)) {
                        if (PositionGetString(POSITION_SYMBOL) == symbol &&
                            posType == POSITION_TYPE_SELL) {
                            double posOpenPrice =
                                PositionGetDouble(POSITION_PRICE_OPEN);
                            double posSl = PositionGetDouble(POSITION_SL);
                            double posTp = PositionGetDouble(POSITION_TP);

                            double sl = NormalizeDouble(
                                getAsk() + TslPoints * point, digits);
                            if ((sl < posSl || posSl == 0.0) && sl != posSl) {
                                if (trade.PositionModify(posTicket, sl,
                                                         posTp)) {
                                    Print(__FUNCTION__ " > Position ticket # ",
                                          posTicket,
                                          " was modified by multiple trailing "
                                          "stop.");
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

bool GBPAUDTradeValidator::executeTrade(ENUM_ORDER_TYPE type,
                                        double currentPrice, double volume,
                                        ulong magic) {
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

void GBPAUDTradeValidator::closePositions(ENUM_ORDER_TYPE type,
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

EURUSDTradeValidator EURUSDvalidator;
int eurusdHandleFastMA, eurusdHandleSlowMA;
double eurusdFastMA[], eurusdSlowMA[];

GBPAUDTradeValidator GBPAUDvalidator;
int gbpaudHandleFastMA, gbpaudHandleSlowMA;
double gbpaudFastMA[], gbpaudSlowMA[];

int OnInit() {
    eurusdHandleFastMA =
        iMA(EURUSD_SYMBOL, PERIOD_M15, FastMAPeriod, 0, MAMode, AppliedPrice);
    eurusdHandleSlowMA =
        iMA(EURUSD_SYMBOL, PERIOD_M15, SlowMAPeriod, 0, MAMode, AppliedPrice);

    gbpaudHandleFastMA =
        iMA(GBPAUD_SYMBOL, PERIOD_M15, FastMAPeriod, 0, MAMode, AppliedPrice);
    gbpaudHandleSlowMA =
        iMA(GBPAUD_SYMBOL, PERIOD_M15, SlowMAPeriod, 0, MAMode, AppliedPrice);

    if (eurusdHandleFastMA == INVALID_HANDLE ||
        eurusdHandleSlowMA == INVALID_HANDLE ||
        gbpaudHandleFastMA == INVALID_HANDLE ||
        gbpaudHandleSlowMA == INVALID_HANDLE) {
        Print("Failed to create MA.", GetLastError());
        return INIT_FAILED;
    }

    EURUSDvalidator.loadSymbolInfo();
    GBPAUDvalidator.loadSymbolInfo();

    ArraySetAsSeries(eurusdFastMA, true);
    ArraySetAsSeries(eurusdSlowMA, true);
    ArraySetAsSeries(gbpaudFastMA, true);
    ArraySetAsSeries(gbpaudSlowMA, true);

    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {}

void OnTick() {
    //---- EURUSD trade section.
    EURUSDvalidator.loadAccountInfo();
    EURUSDvalidator.validateTrailingStop();

    int eurusdCurrentBars = iBars(EURUSDvalidator.getSymbol(), PERIOD_M15);
    double eurusdBid = EURUSDvalidator.getBid();
    double eurusdAsk = EURUSDvalidator.getAsk();
    bool eurusdHasOpenBuyPositions = EURUSDvalidator.hasOpenBuyPositions(),
         eurusdHasOpenSellPositions = EURUSDvalidator.hasOpenSellPositions();

    EURUSDvalidator.validateLotSize();

    if (eurusdCurrentBars != EURUSDvalidator.getTotalBars()) {
        EURUSDvalidator.refresh();
        EURUSDvalidator.updateBuyLotSize(false);
        EURUSDvalidator.updateSellLotSize(false);
        EURUSDvalidator.updateTotalBars(eurusdCurrentBars);

        if (CopyBuffer(eurusdHandleFastMA, 0, 1, IndicatorStopTime,
                       eurusdFastMA) < IndicatorStopTime ||
            CopyBuffer(eurusdHandleSlowMA, 0, 1, IndicatorStopTime,
                       eurusdSlowMA) < IndicatorStopTime) {
            Print("Failed copying indicator values. ", GetLastError());
            return;
        }

        bool buySignal = eurusdFastMA[PREVIOUS] < eurusdSlowMA[PREVIOUS] &&
                         eurusdFastMA[CURRENT] > eurusdSlowMA[CURRENT];
        bool sellSignal = eurusdFastMA[PREVIOUS] > eurusdSlowMA[PREVIOUS] &&
                          eurusdFastMA[CURRENT] < eurusdSlowMA[CURRENT];

        if (sellSignal) {
            // sell signal
            if (eurusdHasOpenSellPositions &&
                EURUSDvalidator.getLastSellPrice() <
                    eurusdAsk -
                        EURUSDMartingalePointGap * EURUSDvalidator.getPoint()) {
                double volume = EURUSDvalidator.getSellLotSize();
                EURUSDvalidator.executeTrade(ORDER_TYPE_SELL, eurusdAsk, volume,
                                             MagicNumber);
                EURUSDvalidator.updateLastSellPrice(eurusdAsk);
                EURUSDvalidator.updateSellLotSize(true);
            } else if (!eurusdHasOpenSellPositions) {
                double volume = EURUSDvalidator.getSellLotSize();
                EURUSDvalidator.executeTrade(ORDER_TYPE_SELL, eurusdAsk, volume,
                                             MagicNumber);
                EURUSDvalidator.updateLastSellPrice(eurusdAsk);
                EURUSDvalidator.updateSellLotSize(true);
            }
        }
        if (buySignal) {
            // buy signal
            if (eurusdHasOpenBuyPositions &&
                EURUSDvalidator.getLastBuyPrice() >
                    eurusdBid + EURUSDMartingalePointGap * _Point) {
                double volume = EURUSDvalidator.getBuyLotSize();
                EURUSDvalidator.executeTrade(ORDER_TYPE_BUY, eurusdBid, volume,
                                             MagicNumber);
                EURUSDvalidator.updateLastBuyPrice(eurusdBid);
                EURUSDvalidator.updateBuyLotSize(true);
            } else if (!eurusdHasOpenBuyPositions) {
                double volume = EURUSDvalidator.getBuyLotSize();
                EURUSDvalidator.executeTrade(ORDER_TYPE_BUY, eurusdBid, volume,
                                             MagicNumber);
                EURUSDvalidator.updateLastBuyPrice(eurusdBid);
                EURUSDvalidator.updateBuyLotSize(true);
            }
        }
    }

    //---- GBPAUD trade section.
    GBPAUDvalidator.loadAccountInfo();
    GBPAUDvalidator.validateTrailingStop();

    int gbpaudCurrentBars = iBars(GBPAUDvalidator.getSymbol(), PERIOD_M15);
    double gbpaudBid = GBPAUDvalidator.getBid();
    double gbpaudAsk = GBPAUDvalidator.getAsk();
    bool gbpaudHasOpenBuyPositions = GBPAUDvalidator.hasOpenBuyPositions(),
         gbpaudHasOpenSellPositions = GBPAUDvalidator.hasOpenSellPositions();

    GBPAUDvalidator.validateLotSize();

    if (gbpaudCurrentBars != GBPAUDvalidator.getTotalBars()) {
        GBPAUDvalidator.refresh();
        GBPAUDvalidator.updateBuyLotSize(false);
        GBPAUDvalidator.updateSellLotSize(false);
        GBPAUDvalidator.updateTotalBars(gbpaudCurrentBars);

        if (CopyBuffer(gbpaudHandleFastMA, 0, 1, IndicatorStopTime,
                       gbpaudFastMA) < IndicatorStopTime ||
            CopyBuffer(gbpaudHandleSlowMA, 0, 1, IndicatorStopTime,
                       gbpaudSlowMA) < IndicatorStopTime) {
            Print("Failed copying indicator values. ", GetLastError());
            return;
        }

        bool buySignal = gbpaudFastMA[PREVIOUS] < gbpaudSlowMA[PREVIOUS] &&
                         gbpaudFastMA[CURRENT] > gbpaudSlowMA[CURRENT];
        bool sellSignal = gbpaudFastMA[PREVIOUS] > gbpaudSlowMA[PREVIOUS] &&
                          gbpaudFastMA[CURRENT] < gbpaudSlowMA[CURRENT];
		
        if (sellSignal) {
            // sell signal
            if (gbpaudHasOpenSellPositions &&
                GBPAUDvalidator.getLastSellPrice() <
                    gbpaudAsk -
                        GBPAUDMartingalePointGap * GBPAUDvalidator.getPoint()) {
                double volume = GBPAUDvalidator.getSellLotSize();
                GBPAUDvalidator.executeTrade(ORDER_TYPE_SELL, gbpaudAsk, volume,
                                             MagicNumber);
                GBPAUDvalidator.updateLastSellPrice(gbpaudAsk);
                GBPAUDvalidator.updateSellLotSize(true);
            } else if (!gbpaudHasOpenSellPositions) {
                double volume = GBPAUDvalidator.getSellLotSize();
                GBPAUDvalidator.executeTrade(ORDER_TYPE_SELL, gbpaudAsk, volume,
                                             MagicNumber);
                GBPAUDvalidator.updateLastSellPrice(gbpaudAsk);
                GBPAUDvalidator.updateSellLotSize(true);
            }
        }
        if (buySignal) {
			Print("buy signal");
            // buy signal
            if (gbpaudHasOpenBuyPositions &&
                GBPAUDvalidator.getLastBuyPrice() >
                    gbpaudBid + GBPAUDMartingalePointGap * _Point) {
                double volume = GBPAUDvalidator.getBuyLotSize();
                GBPAUDvalidator.executeTrade(ORDER_TYPE_BUY, gbpaudBid, volume,
                                             MagicNumber);
                GBPAUDvalidator.updateLastBuyPrice(gbpaudBid);
                GBPAUDvalidator.updateBuyLotSize(true);
            } else if (!gbpaudHasOpenBuyPositions) {
                double volume = GBPAUDvalidator.getBuyLotSize();
                GBPAUDvalidator.executeTrade(ORDER_TYPE_BUY, gbpaudBid, volume,
                                             MagicNumber);
                GBPAUDvalidator.updateLastBuyPrice(gbpaudBid);
                GBPAUDvalidator.updateBuyLotSize(true);
            }
        }
    }
}

/*

        Simple Fast MA(50) + Simple Slow MA(200), Martingale trading strategy.
        Use Trailing stop.

                -----

                EURUSD + GBPAUD

*/