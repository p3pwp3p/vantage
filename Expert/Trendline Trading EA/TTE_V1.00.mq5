//+------------------------------------------------------------------+
//|                                          trendlinetrader_v1.3.mq5 |
//|                                  copyright 2024, anonymous ltd.    |
//|                                           https://github.com/hayan2 |
//+------------------------------------------------------------------+
#property copyright "copyright 2024, anonymous ltd."
#property link "https://github.com/hayan2"
#property version "1.3" // variable names changed to camelcase

//--- include standard libraries
#include <Trade/OrderInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/Trade.mqh>

//--- enumerations
enum ENUM_TRENDLINE_ORDER_TYPE {
    BUY_ORDER, // trendline for buy
    SELL_ORDER // trendline for sell
};

//+------------------------------------------------------------------+
//| input parameters                                                 |
//+------------------------------------------------------------------+
input group "--- main settings ---";
input string TrendlineName = "trend";                  // name of the trendline object to follow
input ENUM_TRENDLINE_ORDER_TYPE OrderType = BUY_ORDER; // type of order to place on the trendline
input double LotSize = 0.01;
input long MagicNumber = 333444;
input int TakeProfitPoints = 200; // tp in points (0 = no tp)
input int StopLossPoints = 200;   // sl in points (0 = no sl)

//+------------------------------------------------------------------+
//| trendline trader class                                           |
//+------------------------------------------------------------------+
class CTrendlineTrader {
  private:
    //--- settings
    string symbol;
    string trendlineName;
    ENUM_TRENDLINE_ORDER_TYPE orderType;
    double lots;
    long magic;
    int tpPoints;
    int slPoints;

    //--- state variables
    ulong pendingOrderTicket;

    //--- mql5 objects
    CTrade *trade;
    CSymbolInfo *symbolInfo;
    COrderInfo *orderInfo;

  public:
    // constructor
    CTrendlineTrader(string sym, CTrade &tradeInstance) {
        symbol = sym;
        trade = &tradeInstance;
        symbolInfo = new CSymbolInfo();
        symbolInfo.Name(symbol);
        orderInfo = new COrderInfo();
        pendingOrderTicket = 0;
    }

    // destructor
    ~CTrendlineTrader() {
        delete symbolInfo;
        delete orderInfo;
    }

    // initialize with user settings
    void init(string name, ENUM_TRENDLINE_ORDER_TYPE type, double lotSize, long magicNumber, int tp, int sl) {
        trendlineName = name;
        orderType = type; // --- corrected assignment ---
        lots = lotSize;
        magic = magicNumber;
        tpPoints = tp;
        slPoints = sl;

        if (MQLInfoInteger(MQL_TESTER)) {
            createTestTrendline();
        }
    }

    // main logic to be called on every tick
    void execute() {
        if (ObjectFind(0, trendlineName) < 0) {
            deletePendingOrder();
            return;
        }

        if (pendingOrderTicket > 0 && !orderInfo.Select(pendingOrderTicket)) {
            pendingOrderTicket = 0;
        }

        if (isPositionOpen())
            return;

        manageOrder();
    }

    double getCurrentTrendlinePrice(datetime t) {
        datetime time1 = (datetime)ObjectGetInteger(0, trendlineName, OBJPROP_TIME, 0);
        double price1 = ObjectGetDouble(0, trendlineName, OBJPROP_PRICE, 0);
        datetime time2 = (datetime)ObjectGetInteger(0, trendlineName, OBJPROP_TIME, 1);
        double price2 = ObjectGetDouble(0, trendlineName, OBJPROP_PRICE, 1);

        if (time2 == time1)
            return 0.0;

        double slope = (price2 - price1) / (double)(time2 - time1);
        double targetPrice = price1 + slope * (double)(t - time1);

        return NormalizeDouble(targetPrice, (int)symbolInfo.Digits());
    }

    string getTrendlineName() {
        return trendlineName;
    }

    // delete pending order on ea exit
    void deinit() {
        deletePendingOrder();
    }

  private:
    // calculates the price on the trendline at a specific time
    double getTrendlinePriceAtTime(datetime targetTime) {
        datetime time1 = (datetime)ObjectGetInteger(0, trendlineName, OBJPROP_TIME, 0);
        double price1 = ObjectGetDouble(0, trendlineName, OBJPROP_PRICE, 0);
        datetime time2 = (datetime)ObjectGetInteger(0, trendlineName, OBJPROP_TIME, 1);
        double price2 = ObjectGetDouble(0, trendlineName, OBJPROP_PRICE, 1);

        if (time2 == time1)
            return 0.0;

        double slope = (price2 - price1) / (double)(time2 - time1);
        double targetPrice = price1 + slope * (double)(targetTime - time1);

        return NormalizeDouble(targetPrice, (int)symbolInfo.Digits());
    }

    // --- COMPLETELY REWRITTEN LOGIC ---
    void manageOrder() {
        double trendlinePriceNow = getTrendlinePriceAtTime(TimeCurrent());
        if (trendlinePriceNow <= 0)
            return;

        symbolInfo.RefreshRates();
        double ask = symbolInfo.Ask();
        double bid = symbolInfo.Bid();
        double point = symbolInfo.Point();

        // --- corrected logic ---
        if (orderType == BUY_ORDER) {
            if (bid <= trendlinePriceNow) {
                deletePendingOrder();
                double tp = (tpPoints > 0) ? ask + tpPoints * point : 0;
                double sl = (slPoints > 0) ? ask - slPoints * point : 0;
                trade.Buy(lots, symbol, ask, sl, tp, "Trendline Market Buy");
                return;
            }

            if (trendlinePriceNow >= ask)
                return;

            double slPrice = (slPoints > 0) ? trendlinePriceNow - slPoints * point : 0;
            double tpPrice = (tpPoints > 0) ? trendlinePriceNow + tpPoints * point : 0;

            if (pendingOrderTicket == 0) {
                if (trade.BuyLimit(lots, trendlinePriceNow, symbol, slPrice, tpPrice, 0, 0, "Trendline Buy Limit"))
                    pendingOrderTicket = trade.ResultOrder();
            } else {
                if (MathAbs(orderInfo.PriceOpen() - trendlinePriceNow) > point) {
                    trade.OrderModify(pendingOrderTicket, trendlinePriceNow, slPrice, tpPrice, 0, 0);
                }
            }
        } else if (orderType == SELL_ORDER) {
            if (ask >= trendlinePriceNow) {
                deletePendingOrder();
                double tp = (tpPoints > 0) ? bid - tpPoints * point : 0;
                double sl = (slPoints > 0) ? bid + slPoints * point : 0;
                trade.Sell(lots, symbol, bid, sl, tp, "Trendline Market Sell");
                return;
            }

            if (trendlinePriceNow <= bid)
                return;

            double slPrice = (slPoints > 0) ? trendlinePriceNow + slPoints * point : 0;
            double tpPrice = (tpPoints > 0) ? trendlinePriceNow - tpPoints * point : 0;

            if (pendingOrderTicket == 0) {
                if (trade.SellLimit(lots, trendlinePriceNow, symbol, slPrice, tpPrice, 0, 0, "Trendline Sell Limit"))
                    pendingOrderTicket = trade.ResultOrder();
            } else {
                if (MathAbs(orderInfo.PriceOpen() - trendlinePriceNow) > point) {
                    trade.OrderModify(pendingOrderTicket, trendlinePriceNow, slPrice, tpPrice, 0, 0);
                }
            }
        }
    }

    // checks if a market position from this ea is already open
    bool isPositionOpen() {
        for (int i = PositionsTotal() - 1; i >= 0; i--) {
            if (PositionSelectByTicket(PositionGetTicket(i))) {
                if (PositionGetString(POSITION_SYMBOL) == symbol && PositionGetInteger(POSITION_MAGIC) == magic)
                    return true;
            }
        }
        return false;
    }

    // deletes the pending order managed by the ea
    void deletePendingOrder() {
        if (pendingOrderTicket > 0) {
            if (orderInfo.Select(pendingOrderTicket)) {
                trade.OrderDelete(pendingOrderTicket);
            }
            pendingOrderTicket = 0;
        }
    }

    // --- new function for testing ---
    void createTestTrendline() {
        datetime time1 = TimeCurrent() - 3600 * 24;
        datetime time2 = TimeCurrent() + 3600 * 24;

        symbolInfo.RefreshRates();
        double priceNow = symbolInfo.Ask();
        double point = symbolInfo.Point();

        double price1, price2;
        // Corrected: use the correct 'orderType' which is ENUM_TRENDLINE_ORDER_TYPE
        if (orderType == BUY_ORDER) {
            price1 = priceNow - 500 * point;
            price2 = priceNow - 300 * point;
        } else // SELL_ORDER
        {
            price1 = priceNow + 500 * point;
            price2 = priceNow + 300 * point;
        }

        ObjectCreate(0, trendlineName, OBJ_TREND, 0, time1, price1, time2, price2);
        ObjectSetInteger(0, trendlineName, OBJPROP_COLOR, clrLime);
        Print("strategy tester detected. created sample trendline '", trendlineName, "' for testing.");
    }
};

//--- global variables
CTrendlineTrader *trader;
CTrade trade;

//+------------------------------------------------------------------+
int OnInit() {
    trade.SetExpertMagicNumber(MagicNumber);

    trader = new CTrendlineTrader(Symbol(), trade);
    trader.init(TrendlineName, OrderType, LotSize, MagicNumber, TakeProfitPoints, StopLossPoints);
    Print(trader.getTrendlineName());

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    if (CheckPointer(trader) == POINTER_DYNAMIC) {
        trader.deinit();
        delete trader;
    }
}

//+------------------------------------------------------------------+
void OnTick() {
    if (CheckPointer(trader) == POINTER_DYNAMIC) {
        trader.execute();
    }

    Print("Current trendline price : ", trader.getCurrentTrendlinePrice(TimeCurrent()));
}
//+------------------------------------------------------------------+
