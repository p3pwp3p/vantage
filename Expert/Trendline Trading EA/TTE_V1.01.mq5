//+------------------------------------------------------------------+
//|                                          trendlinetrader_v1.7.mq5 |
//|                                  copyright 2024, anonymous ltd.    |
//|                                           https://github.com/hayan2 |
//+------------------------------------------------------------------+
#property copyright "copyright 2024, anonymous ltd."
#property link      "https://github.com/hayan2"
#property version   "1.7" // core logic rewritten using bar shift calculation (y=mx+c)

//--- include standard libraries
#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/OrderInfo.mqh>

//--- enumerations
enum ENUM_TRENDLINE_ORDER_TYPE { BUY_ORDER, SELL_ORDER };

//--- input parameters
input group "--- main settings ---";
input string              TrendlineName = "trend";
input ENUM_TRENDLINE_ORDER_TYPE OrderType = BUY_ORDER;
input double              LotSize = 0.01;
input long                MagicNumber = 333444;
input int                 TakeProfitPoints = 200;
input int                 StopLossPoints = 200;
input int BarShift = 8;

//+------------------------------------------------------------------+
//| trendline trader class                                           |
//+------------------------------------------------------------------+
class CTrendlineTrader {
private:
    string   symbol;
    string   trendlineName;
    ENUM_TRENDLINE_ORDER_TYPE orderType;
    double   lots;
    long     magic;
    int      tpPoints;
    int      slPoints;
    ulong    pendingOrderTicket;
    
    CTrade      *trade;
    CSymbolInfo *symbolInfo;
    COrderInfo  *orderInfo;

public:
    CTrendlineTrader(string sym, CTrade &tradeInstance) {
        symbol = sym;
        trade = &tradeInstance;
        symbolInfo = new CSymbolInfo();
        symbolInfo.Name(symbol);
        orderInfo = new COrderInfo();
        pendingOrderTicket = 0;
    }

    ~CTrendlineTrader() {
        delete symbolInfo;
        delete orderInfo;
    }
    
    void init(string name, ENUM_TRENDLINE_ORDER_TYPE type, double lotSize, long magicNumber, int tp, int sl) {
        trendlineName = name;
        orderType = type;
        lots = lotSize;
        magic = magicNumber;
        tpPoints = tp;
        slPoints = sl;
        
        if(MQLInfoInteger(MQL_TESTER)) {
            createTestTrendline();
        }
    }

    void execute() {
        if(ObjectFind(0, trendlineName) < 0) {
            deletePendingOrder();
            return;
        }
        
        if(pendingOrderTicket > 0 && !orderInfo.Select(pendingOrderTicket)) {
            pendingOrderTicket = 0;
        }

        if(isPositionOpen()) {
            deletePendingOrder();
            return;
        }

        manageOrder();
    }
    
    void deinit() {
        deletePendingOrder();
    }
    
    // public function for debugging in ontick
    double getTrendlinePriceAtCurrentBar() {
        return getTrendlinePriceAtShift(BarShift);
    }

private:
    // --- COMPLETELY REWRITTEN PRICE CALCULATION LOGIC ---
    double getTrendlinePriceAtShift(int shift) {
        // 1. get the time and price of the two points of the trendline
        datetime time1 = (datetime)ObjectGetInteger(0, trendlineName, OBJPROP_TIME, 0);
        double   price1 = ObjectGetDouble(0, trendlineName, OBJPROP_PRICE, 0);
        datetime time2 = (datetime)ObjectGetInteger(0, trendlineName, OBJPROP_TIME, 1);
        double   price2 = ObjectGetDouble(0, trendlineName, OBJPROP_PRICE, 1);

        // 2. convert the absolute times into relative bar shifts
        int shift1 = iBarShift(symbol, Period(), time1);
        int shift2 = iBarShift(symbol, Period(), time2);

        if(shift1 < 0 || shift2 < 0) return 0.0; // error getting bar shifts
        if(shift1 == shift2) return 0.0; // avoid division by zero

        // 3. calculate slope (m) and y-intercept (c) using y=mx+c formula
        double m = (price2 - price1) / (shift2 - shift1);
        double c = price1 - m * shift1;

        // 4. calculate the price (y) at the target shift (x)
        double targetPrice = m * shift + c;

        return NormalizeDouble(targetPrice, (int)symbolInfo.Digits());
    }

    void manageOrder() {
        // calculate the price at the current bar (shift = 0)
        double trendlinePriceNow = getTrendlinePriceAtShift(BarShift);
        if(trendlinePriceNow <= 0) return;

        symbolInfo.RefreshRates();
        double ask = symbolInfo.Ask();
        double bid = symbolInfo.Bid();
        double point = symbolInfo.Point();
        
        if(orderType == BUY_ORDER) {
            if(bid <= trendlinePriceNow) {
                deletePendingOrder();
                double tp = (tpPoints > 0) ? ask + tpPoints * point : 0;
                double sl = (slPoints > 0) ? ask - slPoints * point : 0;
                trade.Buy(lots, symbol, ask, sl, tp, "Trendline Market Buy");
                return;
            }
            
            if(trendlinePriceNow >= ask) return;
            
            double slPrice = (slPoints > 0) ? trendlinePriceNow - slPoints * point : 0;
            double tpPrice = (tpPoints > 0) ? trendlinePriceNow + tpPoints * point : 0;

            if(pendingOrderTicket == 0) {
                if(trade.BuyLimit(lots, trendlinePriceNow, symbol, slPrice, tpPrice, 0, 0, "Trendline Buy Limit"))
                    pendingOrderTicket = trade.ResultOrder();
            } else {
                if(MathAbs(orderInfo.PriceOpen() - trendlinePriceNow) > point) {
                    trade.OrderModify(pendingOrderTicket, trendlinePriceNow, slPrice, tpPrice, 0, 0);
                }
            }
        } else if (orderType == SELL_ORDER) {
            if(ask >= trendlinePriceNow) {
                deletePendingOrder();
                double tp = (tpPoints > 0) ? bid - tpPoints * point : 0;
                double sl = (slPoints > 0) ? bid + slPoints * point : 0;
                trade.Sell(lots, symbol, bid, sl, tp, "Trendline Market Sell");
                return;
            }
            
            if(trendlinePriceNow <= bid) return;

            double slPrice = (slPoints > 0) ? trendlinePriceNow + slPoints * point : 0;
            double tpPrice = (tpPoints > 0) ? trendlinePriceNow - tpPoints * point : 0;

            if(pendingOrderTicket == 0) {
                 if(trade.SellLimit(lots, trendlinePriceNow, symbol, slPrice, tpPrice, 0, 0, "Trendline Sell Limit"))
                    pendingOrderTicket = trade.ResultOrder();
            } else {
                if(MathAbs(orderInfo.PriceOpen() - trendlinePriceNow) > point) {
                    trade.OrderModify(pendingOrderTicket, trendlinePriceNow, slPrice, tpPrice, 0, 0);
                }
            }
        }
    }
    
    bool isPositionOpen() {
        for(int i=PositionsTotal()-1; i>=0; i--) {
            if(PositionSelectByTicket(PositionGetTicket(i))) {
               if(PositionGetString(POSITION_SYMBOL) == symbol && PositionGetInteger(POSITION_MAGIC) == magic)
                  return true;
            }
        }
        return false;
    }
    
    void deletePendingOrder() {
        if(pendingOrderTicket > 0) {
            if(orderInfo.Select(pendingOrderTicket)) {
                trade.OrderDelete(pendingOrderTicket);
            }
            pendingOrderTicket = 0;
        }
    }
    
    void createTestTrendline() {
        datetime time1 = iTime(symbol, Period(), 50); // 50 bars ago
        datetime time2 = iTime(symbol, Period(), 10); // 10 bars ago
        
        double price1, price2;
        if(orderType == BUY_ORDER) {
            price1 = iLow(symbol, Period(), 50);
            price2 = iLow(symbol, Period(), 10);
        } else {
            price1 = iHigh(symbol, Period(), 50);
            price2 = iHigh(symbol, Period(), 10);
        }

        ObjectCreate(0, trendlineName, OBJ_TREND, 0, time1, price1, time2, price2);
        ObjectSetInteger(0, trendlineName, OBJPROP_COLOR, clrLime);
        Print("strategy tester detected. created sample trendline '", trendlineName, "' for testing.");
    }
};

//--- global variables
CTrendlineTrader *trader;
CTrade           trade;

//+------------------------------------------------------------------+
int OnInit() {
    trade.SetExpertMagicNumber(MagicNumber);
    
    trader = new CTrendlineTrader(Symbol(), trade);
    trader.init(TrendlineName, OrderType, LotSize, MagicNumber, TakeProfitPoints, StopLossPoints);
    
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
        
        if(ObjectFind(0, TrendlineName) >= 0) {
           double trendlinePrice = trader.getTrendlinePriceAtCurrentBar();
           Print("Current Market Bid: ", SymbolInfoDouble(Symbol(), SYMBOL_BID),
                 " / Calculated Trendline Price at current bar: ", trendlinePrice);
        }
    }
}
//+------------------------------------------------------------------+

