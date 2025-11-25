//+------------------------------------------------------------------+
//|                                    Trendline Limit Trading.mq5 |
//|                                     copyright 2025, anonymous ltd. |
//|                                        https://github.com/hayan2 |
//+------------------------------------------------------------------+
#property copyright "copyright 2025, anonymous ltd."
#property link "https://github.com/hayan2"
#property version "2.00" // Market execution on touch & Trailing Stop feature

//--- include standard libraries
#include <Trade/OrderInfo.mqh>
#include <Trade/PositionInfo.mqh> // PositionInfo for Trailing Stop
#include <Trade/SymbolInfo.mqh>
#include <Trade/Trade.mqh>

//--- input parameters
input group "--- Main Settings ---";
input long MagicNumber = 2147483647;
input string SellLimitTrendLineName = "sell";
input string BuyLimitTrendLineName = "buy";
input double LotSize = 0.01;
input group "--- Profit & Loss ---";
input int TakeProfitPoints = 200;
input int StopLossPoints = 200;
input int TrailingStopPoints = 0;

//+------------------------------------------------------------------+
//| CTrendlineTrader Class                                           |
//+------------------------------------------------------------------+
class CTrendlineTrader {
  private:
    string symbol;
    string sellLimitName;
    string buyLimitName;
    double lots;
    long magic;
    int tpPoints;
    int slPoints;
    int tslPoints;

    CTrade *trade;
    CSymbolInfo *symbolInfo;
    CPositionInfo *positionInfo; // Use CPositionInfo for easier access

  public:
    CTrendlineTrader(string sym, CTrade &tradeInstance) {
        symbol = sym;
        trade = &tradeInstance;
        symbolInfo = new CSymbolInfo();
        symbolInfo.Name(symbol);
        positionInfo = new CPositionInfo();
    }

    ~CTrendlineTrader() {
        delete symbolInfo;
        delete positionInfo;
    }

    void init(string slName, string blName, double lotSize, long magicNumber, int tp, int sl, int tsl) {
        sellLimitName = slName;
        buyLimitName = blName;
        lots = lotSize;
        magic = magicNumber;
        tpPoints = tp;
        slPoints = sl;
        tslPoints = tsl;
    }

    void execute() {
        // Refresh market data once per tick
        symbolInfo.RefreshRates();

        // If a position is already open, manage trailing stop. Otherwise, check for new trades.
        if (isPositionOpen()) {
            manageTrailingStop();
        } else {
            checkTrendlinesAndTrade();
        }
    }

  private:
    //
    // NEW LOGIC: Finds the most valid (closest) trendline and checks for a trade.
    //
    void checkTrendlinesAndTrade() {
        double point = symbolInfo.Point();
        double bid = symbolInfo.Bid();
        double ask = symbolInfo.Ask();

        // --- Find the best (closest) trendline price for Buy and Sell ---
        double bestBuyLinePrice = 0;        // Highest price among all 'buy' lines below current price
        double bestSellLinePrice = DBL_MAX; // Lowest price among all 'sell' lines above current price

        for (int i = ObjectsTotal(0, -1, OBJ_TREND) - 1; i >= 0; i--) {
            string objName = ObjectName(0, i, -1, OBJ_TREND);
            double linePrice = ObjectGetValueByTime(0, objName, TimeCurrent(), 0);

            // Check for valid buy lines
            if (StringFind(objName, buyLimitName) != -1 && linePrice < ask) {
                if (linePrice > bestBuyLinePrice) {
                    bestBuyLinePrice = linePrice;
                }
            }

            // Check for valid sell lines
            if (StringFind(objName, sellLimitName) != -1 && linePrice > bid) {
                if (linePrice < bestSellLinePrice) {
                    bestSellLinePrice = linePrice;
                }
            }
        }

        // Normalize the final prices
        if (bestSellLinePrice == DBL_MAX)
            bestSellLinePrice = 0;

        // --- Check for Buy Signal using the best line---
        if (bestBuyLinePrice > 0 && bid <= bestBuyLinePrice) {
            double tp = 0, sl = 0;
            if (tslPoints == 0) {
                if (tpPoints > 0)
                    tp = ask + tpPoints * point;
                if (slPoints > 0)
                    sl = ask - slPoints * point;
            }
            trade.Buy(lots, symbol, ask, sl, tp, "Buy on Trendline Touch");
            return;
        }

        // --- Check for Sell Signal using the best line---
        if (bestSellLinePrice > 0 && ask >= bestSellLinePrice) {
            double tp = 0, sl = 0;
            if (tslPoints == 0) {
                if (tpPoints > 0)
                    tp = bid - tpPoints * point;
                if (slPoints > 0)
                    sl = bid + slPoints * point;
            }
            trade.Sell(lots, symbol, bid, sl, tp, "Sell on Trendline Touch");
        }
    }

    //
    // Manages the trailing stop for an open position.
    //
    void manageTrailingStop() {
        // Only run if trailing stop is enabled
        if (tslPoints <= 0) {
            return;
        }

        double point = symbolInfo.Point();
        int digits = (int)symbolInfo.Digits();

        // Loop through all open positions
        for (int i = PositionsTotal() - 1; i >= 0; i--) {
            if (positionInfo.SelectByIndex(i)) {
                // Check if the position belongs to this EA
                if (positionInfo.Symbol() == symbol && positionInfo.Magic() == magic) {
                    double openPrice = positionInfo.PriceOpen();
                    double currentSL = positionInfo.StopLoss();
                    ulong ticket = positionInfo.Ticket();

                    if (positionInfo.PositionType() == POSITION_TYPE_BUY) {
                        double bid = symbolInfo.Bid();
                        // Check if position is profitable enough to trigger trailing stop
                        if (bid > openPrice + tslPoints * point) {
                            double newSL = NormalizeDouble(bid - tslPoints * point, digits);
                            // Modify SL if it's the first time (currentSL is 0)
                            // OR if the new SL is meaningfully better (at least 1 point higher)
                            if (currentSL == 0 || newSL - currentSL > point) {
                                trade.PositionModify(ticket, newSL, positionInfo.TakeProfit());
                            }
                        }
                    } else if (positionInfo.PositionType() == POSITION_TYPE_SELL) {
                        double ask = symbolInfo.Ask();
                        // Check if position is profitable enough to trigger trailing stop
                        if (ask < openPrice - tslPoints * point) {
                            double newSL = NormalizeDouble(ask + tslPoints * point, digits);
                            // Modify SL if it's the first time (currentSL is 0)
                            // OR if the new SL is meaningfully better (at least 1 point lower)
                            if (currentSL == 0 || currentSL - newSL > point) {
                                trade.PositionModify(ticket, newSL, positionInfo.TakeProfit());
                            }
                        }
                    }
                }
            }
        }
    }

    bool isPositionOpen() {
        return (PositionSelect(symbol));
    }
};

//--- global variables
CTrendlineTrader *trader;
CTrade trade;

//+------------------------------------------------------------------+
int OnInit() {
    trade.SetExpertMagicNumber(MagicNumber);

    trader = new CTrendlineTrader(Symbol(), trade);
    trader.init(SellLimitTrendLineName, BuyLimitTrendLineName, LotSize, MagicNumber, TakeProfitPoints, StopLossPoints,
                TrailingStopPoints);

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    if (CheckPointer(trader) == POINTER_DYNAMIC) {
        delete trader;
    }
}

//+------------------------------------------------------------------+
void OnTick() {
    if (CheckPointer(trader) == POINTER_DYNAMIC) {
        trader.execute();
    }
}
//+------------------------------------------------------------------+