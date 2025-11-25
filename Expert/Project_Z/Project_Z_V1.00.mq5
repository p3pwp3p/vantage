//+------------------------------------------------------------------+
//|                                               Project_Z_V1.0.mq5 |
//|                                  copyright 2025, anonymous ltd.  |
//|                                        https://github.com/hayan2 |
//+------------------------------------------------------------------+
#property copyright "copyright 2025, anonymous ltd."
#property link "https://github.com/hayan2"
#property version "1.00"

//--- include standard libraries
#include <ChartObjects/ChartObjectsTxtControls.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/Trade.mqh>

#define MAX_ENTRY_LEVELS 4

//--- enumerations
enum ENUM_INFO_DIRECTION { LEFT_UP = 0, RIGHT_UP = 1, LEFT_DOWN = 2, RIGHT_DOWN = 3 };

//--- constant variable
const ENUM_INFO_DIRECTION InfoDirection = RIGHT_DOWN; // panel position is fixed to top-right

//+------------------------------------------------------------------+
//| input parameters                                                 |
//+------------------------------------------------------------------+
input group "--- trade settings ---";
input string Symbol_1 = "XAUUSD";
input long MagicNumber = 2147483647;
input bool AllowDailyHedging = false; // if false, only one direction is traded per day

input group "--- entry settings ---";
input double FirstEntryLots = 0.01;
input double FirstBuyEntryPercent = -0.5;
input double FirstSellEntryPercent = 0.5;
input double FirstEntryTpPoints = 200.0; // TP in points
input double FirstEntrySlPoints = 200.0; // SL in points

input double SecondEntryLots = 0.02;
input double SecondBuyEntryPercent = -0.8;
input double SecondSellEntryPercent = 0.8;
input double SecondEntryTpPoints = 200.0;
input double SecondEntrySlPoints = 200.0;

input double ThirdEntryLots = 0.04;
input double ThirdBuyEntryPercent = -1.3;
input double ThirdSellEntryPercent = 1.3;
input double ThirdEntryTpPoints = 200.0;
input double ThirdEntrySlPoints = 200.0;

input double FourthEntryLots = 0.08;
input double FourthBuyEntryPercent = -1.7;
input double FourthSellEntryPercent = 1.7;
input double FourthEntryTpPoints = 200.0;
input double FourthEntrySlPoints = 200.0;

//+------------------------------------------------------------------+
//| strategy brain class                                             |
//+------------------------------------------------------------------+
class CStrategyController {
  private:
    //--- configuration
    string symbol;
    long magicNumber;
    bool allowDailyHedging;

    //--- entry settings arrays
    double lotSizes[MAX_ENTRY_LEVELS];
    double buyEntryPercents[MAX_ENTRY_LEVELS];
    double sellEntryPercents[MAX_ENTRY_LEVELS];
    double tpPoints[MAX_ENTRY_LEVELS];
    double slPoints[MAX_ENTRY_LEVELS];

    //--- daily data
    double dailyOpenPrice;
    double buyEntryPrices[MAX_ENTRY_LEVELS];
    double sellEntryPrices[MAX_ENTRY_LEVELS];
    datetime lastPriceUpdateDate;

    //--- trade state flags
    bool buyTradedToday[MAX_ENTRY_LEVELS];
    bool sellTradedToday[MAX_ENTRY_LEVELS];
    int dailyTradeDirection; // 0 = none, 1 = buy, 2 = sell

    //--- mql5 objects
    CTrade *trade;
    CSymbolInfo *symbolInfo;
    string infoPanelPrefix;

  public:
    CStrategyController(string sym, CTrade &tradeInstance) {
        symbol = sym;
        trade = &tradeInstance;
        symbolInfo = new CSymbolInfo();

        dailyOpenPrice = 0;
        lastPriceUpdateDate = 0;
        infoPanelPrefix = symbol + "_DailyOpenInfo_";
        resetDailyFlags();
    }

    ~CStrategyController() {
        delete symbolInfo;
    }

    void init(long magic, bool hedging) {
        magicNumber = magic;
        allowDailyHedging = hedging;
        symbolInfo.Name(symbol);
    }

    void initializeEntrySettings(double &lots[], double &buy_pct[], double &sell_pct[], double &tps[], double &sls[]) {
        for (int i = 0; i < MAX_ENTRY_LEVELS; i++) {
            lotSizes[i] = lots[i];
            buyEntryPercents[i] = buy_pct[i];
            sellEntryPercents[i] = sell_pct[i];
            tpPoints[i] = tps[i];
            slPoints[i] = sls[i];
        }
    }

    bool updateDailyData() {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        MqlDateTime lastDt;
        TimeToStruct(lastPriceUpdateDate, lastDt);

        if (dt.day != lastDt.day || lastPriceUpdateDate == 0) {
            MqlRates rates[];
            if (CopyRates(symbol, PERIOD_D1, 0, 1, rates) > 0) {
                dailyOpenPrice = rates[0].open;
                int digits = (int)symbolInfo.Digits();

                for (int i = 0; i < MAX_ENTRY_LEVELS; i++) {
                    buyEntryPrices[i] = NormalizeDouble(dailyOpenPrice * (1 + buyEntryPercents[i] / 100.0), digits);
                    sellEntryPrices[i] = NormalizeDouble(dailyOpenPrice * (1 + sellEntryPercents[i] / 100.0), digits);
                }

                lastPriceUpdateDate = TimeCurrent();
                Print("new day. open price: ", dailyOpenPrice);
                return true;
            }
        }
        return false;
    }

    void resetDailyFlags() {
        for (int i = 0; i < MAX_ENTRY_LEVELS; i++) {
            buyTradedToday[i] = false;
            sellTradedToday[i] = false;
        }
        dailyTradeDirection = 0; // reset direction lock
        Print("daily trade flags reset.");
    }

    void checkAndTrade() {
        if (dailyOpenPrice == 0)
            return;

        symbolInfo.RefreshRates();

        for (int i = 0; i < MAX_ENTRY_LEVELS; i++) {
            // --- check for buy entry ---
            if (!buyTradedToday[i] && (dailyTradeDirection != 2 || allowDailyHedging) &&
                symbolInfo.Ask() <= buyEntryPrices[i]) {
                openPosition(ORDER_TYPE_BUY, lotSizes[i], tpPoints[i], slPoints[i],
                             "Buy Entry " + IntegerToString(i + 1));
                buyTradedToday[i] = true;
                if (!allowDailyHedging && dailyTradeDirection == 0)
                    dailyTradeDirection = 1;
            }

            // --- check for sell entry ---
            if (!sellTradedToday[i] && (dailyTradeDirection != 1 || allowDailyHedging) &&
                symbolInfo.Bid() >= sellEntryPrices[i]) {
                openPosition(ORDER_TYPE_SELL, lotSizes[i], tpPoints[i], slPoints[i],
                             "Sell Entry " + IntegerToString(i + 1));
                sellTradedToday[i] = true;
                if (!allowDailyHedging && dailyTradeDirection == 0)
                    dailyTradeDirection = 2;
            }
        }
    }

    void drawLines() {
        if (dailyOpenPrice == 0)
            return;

        ObjectCreate(0, "DailyOpen", OBJ_HLINE, 0, 0, dailyOpenPrice);
        ObjectSetInteger(0, "DailyOpen", OBJPROP_COLOR, clrWhite);

        for (int i = 0; i < MAX_ENTRY_LEVELS; i++) {
            ObjectCreate(0, "BuyEntry" + IntegerToString(i + 1), OBJ_HLINE, 0, 0, buyEntryPrices[i]);
            ObjectSetInteger(0, "BuyEntry" + IntegerToString(i + 1), OBJPROP_COLOR, clrDodgerBlue);
            ObjectSetInteger(0, "BuyEntry" + IntegerToString(i + 1), OBJPROP_STYLE, STYLE_DOT);

            ObjectCreate(0, "SellEntry" + IntegerToString(i + 1), OBJ_HLINE, 0, 0, sellEntryPrices[i]);
            ObjectSetInteger(0, "SellEntry" + IntegerToString(i + 1), OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, "SellEntry" + IntegerToString(i + 1), OBJPROP_STYLE, STYLE_DOT);
        }
    }

    void deleteLines() {
        ObjectDelete(0, "DailyOpen");
        for (int i = 0; i < MAX_ENTRY_LEVELS; i++) {
            ObjectDelete(0, "BuyEntry" + IntegerToString(i + 1));
            ObjectDelete(0, "SellEntry" + IntegerToString(i + 1));
        }
        ChartRedraw();
    }

    void drawInfoPanel(ENUM_INFO_DIRECTION corner, int digits) {
        int line_height = 12, x_pos = 10, y_pos = 15, line_counter = 0;
        for (int i = 0; i < MAX_ENTRY_LEVELS; i++) {
            string buy_price_str = DoubleToString(buyEntryPrices[i], digits);
            string sell_price_str = DoubleToString(sellEntryPrices[i], digits);
            string lineText = StringFormat("L%d: Buy %.2f%% (%s) / Sell %.2f%% (%s)", i + 1, buyEntryPercents[i],
                                           buy_price_str, sellEntryPercents[i], sell_price_str);
            updateOrCreateLabel(infoPanelPrefix + "L" + IntegerToString(i), lineText, corner, x_pos,
                                y_pos + (line_counter++ * line_height));
        }
    }

    void deleteInfoPanel() {
        for (int i = 0; i < MAX_ENTRY_LEVELS; i++) {
            ObjectDelete(0, infoPanelPrefix + "L" + IntegerToString(i));
        }
    }

  private:
    void openPosition(ENUM_ORDER_TYPE type, double lots, double tpPips, double slPips, string comment) {
        trade.SetExpertMagicNumber(magicNumber);

        double price = (type == ORDER_TYPE_BUY) ? symbolInfo.Ask() : symbolInfo.Bid();
        double point = symbolInfo.Point();

        double tp = (type == ORDER_TYPE_BUY) ? price + tpPips * point : price - tpPips * point;
        double sl = (type == ORDER_TYPE_BUY) ? price - slPips * point : price + slPips * point;

        if (tpPips == 0)
            tp = 0;
        if (slPips == 0)
            sl = 0;

        if (type == ORDER_TYPE_BUY) {
            trade.Buy(lots, symbol, price, sl, tp, comment);
        } else {
            trade.Sell(lots, symbol, price, sl, tp, comment);
        }
    }

    void updateOrCreateLabel(string name, string text, ENUM_INFO_DIRECTION corner, int x, int y) {
        if (ObjectFind(0, name) < 0) {
            ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
            ObjectSetString(0, name, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
        }
        ObjectSetInteger(0, name, OBJPROP_CORNER, (int)corner);
        ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
        switch (corner) {
        case LEFT_UP:
            ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
            break;
        case RIGHT_UP:
            ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
            break;
        case LEFT_DOWN:
            ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
            break;
        case RIGHT_DOWN:
            ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
            break;
        }
        ObjectSetString(0, name, OBJPROP_TEXT, text);
    }
};

//--- global variables
CStrategyController *strategy;
CTrade trade;
bool needsRedraw = true;

//+------------------------------------------------------------------+
int OnInit() {
    strategy = new CStrategyController(Symbol_1, trade);
    strategy.init(MagicNumber, AllowDailyHedging);

    double lots[] = {FirstEntryLots, SecondEntryLots, ThirdEntryLots, FourthEntryLots};
    double buyPercents[] = {FirstBuyEntryPercent, SecondBuyEntryPercent, ThirdBuyEntryPercent, FourthBuyEntryPercent};
    double sellPercents[] = {FirstSellEntryPercent, SecondSellEntryPercent, ThirdSellEntryPercent,
                             FourthSellEntryPercent};
    double tps[] = {FirstEntryTpPoints, SecondEntryTpPoints, ThirdEntryTpPoints, FourthEntryTpPoints};
    double sls[] = {FirstEntrySlPoints, SecondEntrySlPoints, ThirdEntrySlPoints, FourthEntrySlPoints};

    strategy.initializeEntrySettings(lots, buyPercents, sellPercents, tps, sls);
    OnTick();

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    if (CheckPointer(strategy) == POINTER_DYNAMIC) {
        strategy.deleteLines();
        delete strategy;
    }
}

//+------------------------------------------------------------------+
void OnTick() {
    if (CheckPointer(strategy) != POINTER_DYNAMIC)
        return;

    if (strategy.updateDailyData()) {
        strategy.resetDailyFlags();
        strategy.drawLines(); // redraw lines on a new day
        ChartRedraw();
    }

    if (needsRedraw) {
        strategy.deleteLines();
        strategy.deleteInfoPanel(); // clean up old panel before drawing new one
        strategy.drawLines();
        strategy.drawInfoPanel(InfoDirection, (int)SymbolInfoInteger(Symbol_1, SYMBOL_DIGITS));
        ChartRedraw();
        needsRedraw = false;
    }

    strategy.checkAndTrade();
}
//+------------------------------------------------------------------+
