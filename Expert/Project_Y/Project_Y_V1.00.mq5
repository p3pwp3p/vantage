//+------------------------------------------------------------------+
//|                                              Project_Y_V1.00.mq5 |
//|                                   copyright 2025, anonymous ltd. |
//|                                        https://github.com/hayan2 |
//+------------------------------------------------------------------+
#property copyright "copyright 2025, anonymous ltd."
#property link "https://github.com/hayan2"
#property version "1.00"

//--- enumerations
enum ENUM_INFO_DIRECTION { LEFT_UP = 0, RIGHT_UP = 1, LEFT_DOWN = 2, RIGHT_DOWN = 3 };
enum ENUM_ENTRY_POSITION { SELL, BUY, NO_TRADE };

//--- constance variable
#define MAX_PIVOT_LEVELS 5
#define MAX_TP_SL_LEVELS 10

const ENUM_INFO_DIRECTION InfoDirection = RIGHT_DOWN;

//--- input parameters
input group "=============== section 1 ===============";
input group "=============== default trade setting ===============";
input long MagicNumber = 2147483647;
input double MaxLots = 0.15;
input bool BuySellSound = false;
input double MinMarginLevel = 400.0;
input string Symbol_1 = "GBPAUD";
input bool HasSellPosition = true;
input bool HasBuyPosition = true;
input string SupportLineLots = "0.02,0.02,0.03,0.04,0.05,0.06,0.07,0.08,0.09,0.10,0.11,0.13";
input string ResistanceLineLots = "0.02,0.02,0.03,0.04,0.05,0.06,0.07,0.08,0.09,0.10,0.11,0.13";
input double MinPointGap = 400.0;
input int MaxPositions = 9;
input int MaxEntryCount = 2;
input int MaxBuyOrders = 12;
input int MaxSellOrders = 12;
input color SupportLineColor = Red;
input color ResistanceLineColor = DodgerBlue;
input color CenterLineColor = clrWhite;

input group "entry offset points";
input double EntryOffsetS1 = -20;
input double EntryOffsetS2 = -30;
input double EntryOffsetS3 = -50;
input double EntryOffsetS4 = -80;
input double EntryOffsetS5 = -100;
input double EntryOffsetR1 = 20;
input double EntryOffsetR2 = 30;
input double EntryOffsetR3 = 50;
input double EntryOffsetR4 = 80;
input double EntryOffsetR5 = 100;

input group "orders";
input ENUM_ENTRY_POSITION PositionS1 = BUY;
input ENUM_ENTRY_POSITION PositionS2 = BUY;
input ENUM_ENTRY_POSITION PositionS3 = BUY;
input ENUM_ENTRY_POSITION PositionS4 = BUY;
input ENUM_ENTRY_POSITION PositionS5 = BUY;
input ENUM_ENTRY_POSITION PositionR1 = SELL;
input ENUM_ENTRY_POSITION PositionR2 = SELL;
input ENUM_ENTRY_POSITION PositionR3 = SELL;
input ENUM_ENTRY_POSITION PositionR4 = SELL;
input ENUM_ENTRY_POSITION PositionR5 = SELL;

input group "close positions";
input double FirstEntryTP = 5.0;
input double FirstEntrySL = -5.0;
input double SecondEntryTP = 7.0;
input double SecondEntrySL = -7.0;
input double ThirdEntryTP = 12.0;
input double ThirdEntrySL = -12.0;
input double FourthEntryTP = 17.0;
input double FourthEntrySL = -17.0;
input double FifthEntryTP = 23.0;
input double FifthEntrySL = -23.0;
input double SixthEntryTP = 29.0;
input double SixthEntrySL = -29.0;
input double SeventhEntryTP = 35.0;
input double SeventhEntrySL = -35.0;
input double EighthEntryTP = 35.0;
input double EighthEntrySL = -35.0;
input double NinthEntryTP = 35.0;
input double NinthEntrySL = -35.0;
input double TenthEntryTP = 35.0;
input double TenthEntrySL = -35.0;
input double SellEntryGapOvernight = 400.0;
input double BuyEntryGapOvernight = -400.0;

#include <Arrays/ArrayObj.mqh>
#include <ChartObjects/ChartObjectsLines.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| pivot point class                                                |
//+------------------------------------------------------------------+
class PivotPoint {
  private:
    datetime lastUpdateTime;
    string symbol;
    double resistanceEntryPoints[MAX_PIVOT_LEVELS];
    double supportEntryPoints[MAX_PIVOT_LEVELS];
    double resistancePrices[MAX_PIVOT_LEVELS];
    double supportPrices[MAX_PIVOT_LEVELS];
    double resistanceEntryPrices[MAX_PIVOT_LEVELS];
    double supportEntryPrices[MAX_PIVOT_LEVELS];
    double centerLinePrice;
    string infoPanelName;   // name for the label object
    string infoPanelPrefix; // changed from name to prefix

  public:
    PivotPoint(string sym) {
        symbol = sym;
        lastUpdateTime = 0;
        centerLinePrice = 0;
        infoPanelName = symbol + "_InfoPanel";
    }

    ~PivotPoint() {
    }

    // restored this function to store percentages within the class
    void initializeEntryPoints(double &r[], double &s[]) {
        for (int i = 0; i < MAX_PIVOT_LEVELS; i++) {
            resistanceEntryPoints[i] = r[i];
            supportEntryPoints[i] = s[i];
        }
    }

    // --- MODIFIED FUNCTION ---
    bool update() {
        MqlDateTime currentTimeStruct;
        TimeToStruct(TimeCurrent(), currentTimeStruct);
        MqlDateTime lastUpdateTimeStruct;
        TimeToStruct(lastUpdateTime, lastUpdateTimeStruct);

        if (lastUpdateTime == 0 || currentTimeStruct.day != lastUpdateTimeStruct.day) {
            MqlRates rates[];
            if (CopyRates(symbol, PERIOD_D1, 1, 1, rates) < 1) {
                Print("failed to get previous day's candle data for ", symbol);
                return false;
            }

            double prevHigh = rates[0].high;
            double prevLow = rates[0].low;
            double prevClose = rates[0].close;
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

            double pivotPointPrice = (prevHigh + prevLow + prevClose) / 3.0;
            centerLinePrice = pivotPointPrice;

            resistancePrices[0] = (2 * pivotPointPrice) - prevLow;
            resistancePrices[1] = pivotPointPrice + (prevHigh - prevLow);
            resistancePrices[2] = prevHigh + 2 * (pivotPointPrice - prevLow);
            resistancePrices[3] = resistancePrices[2] + (prevHigh - prevLow);
            resistancePrices[4] = resistancePrices[3] + (prevHigh - prevLow);

            supportPrices[0] = (2 * pivotPointPrice) - prevHigh;
            supportPrices[1] = pivotPointPrice - (prevHigh - prevLow);
            supportPrices[2] = prevLow - 2 * (prevHigh - pivotPointPrice);
            supportPrices[3] = supportPrices[2] - (prevHigh - prevLow);
            supportPrices[4] = supportPrices[3] - (prevHigh - prevLow);

            // --- THIS IS THE CORE LOGIC CHANGE ---
            for (int i = 0; i < MAX_PIVOT_LEVELS; i++) {
                resistanceEntryPrices[i] = resistancePrices[i] + (resistanceEntryPoints[i] * point);
                supportEntryPrices[i] = supportPrices[i] + (supportEntryPoints[i] * point);
            }

            lastUpdateTime = TimeCurrent();
            Print("classic pivot prices updated for ", symbol);
            return true;
        }
        return false;
    }

    void drawInfoPanel(int corner, int digits) {
        int line_height = 12, x_pos = 10, y_pos = 15, line_counter = 0;
        
        for (int i = MAX_PIVOT_LEVELS - 1; i >= 0; i--) {
            string price = DoubleToString(resistanceEntryPrices[i], digits);
            string lineText = StringFormat("R%d %.0f Pts : %s", i + 1, resistanceEntryPoints[i], price);
            updateOrCreateLabel(infoPanelPrefix + "R" + IntegerToString(i), lineText, corner, x_pos, y_pos + (line_counter++ * line_height));
        }
        for (int i = 0; i < MAX_PIVOT_LEVELS; i++) {
            string price = DoubleToString(supportEntryPrices[i], digits);
            string lineText = StringFormat("S%d %.0f Pts : %s", i + 1, supportEntryPoints[i], price);
            updateOrCreateLabel(infoPanelPrefix + "S" + IntegerToString(i), lineText, corner, x_pos, y_pos + (line_counter++ * line_height));
        }
    }

    // --- ADDED MISSING HELPER FUNCTION ---
    void updateOrCreateLabel(string name, string text, int corner, int x, int y) {
        if (ObjectFind(0, name) < 0) {
            ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
            ObjectSetString(0, name, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
        }
        
        ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
        ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
        
        switch(corner) {
            case 0: ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER); break;
            case 1: ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER); break;
            case 2: ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER); break;
            case 3: ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER); break;
        }

        ObjectSetString(0, name, OBJPROP_TEXT, text);
    }

    // --- REWRITTEN FUNCTION ---
    void deleteInfoPanel() {
        // delete all labels associated with this panel
        for (int i = 0; i < MAX_PIVOT_LEVELS; i++) {
            ObjectDelete(0, infoPanelPrefix + "R" + IntegerToString(i));
            ObjectDelete(0, infoPanelPrefix + "S" + IntegerToString(i));
        }
    }

    // --- MODIFIED FUNCTION ---
    // draws lines at the final entry price levels
    void drawLines(color resColor, color supColor, color cenColor) {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        dt.hour = 0;
        dt.min = 0;
        dt.sec = 0;
        datetime startTime = StructToTime(dt);
        datetime endTime = startTime + (24 * 60 * 60) - 1;

        // center line is drawn at the standard pivot point
        string cLineName = symbol + "_CenterLine";
        if (ObjectFind(0, cLineName) < 0) {
            ObjectCreate(0, cLineName, OBJ_RECTANGLE, 0, 0, 0);
            ObjectSetInteger(0, cLineName, OBJPROP_COLOR, cenColor);
            ObjectSetInteger(0, cLineName, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetString(0, cLineName, OBJPROP_TEXT, "PP");
            ObjectSetInteger(0, cLineName, OBJPROP_FILL, false);
        }
        ObjectSetInteger(0, cLineName, OBJPROP_TIME, 0, (long)startTime);
        ObjectSetInteger(0, cLineName, OBJPROP_TIME, 1, (long)endTime);
        ObjectSetDouble(0, cLineName, OBJPROP_PRICE, 0, centerLinePrice);
        ObjectSetDouble(0, cLineName, OBJPROP_PRICE, 1, centerLinePrice);

        // support and resistance lines are now drawn at the calculated entry
        // prices
        for (int i = 0; i < MAX_PIVOT_LEVELS; i++) {
            string rLineName = symbol + "_R_Entry" + IntegerToString(i + 1);
            if (ObjectFind(0, rLineName) < 0) {
                ObjectCreate(0, rLineName, OBJ_RECTANGLE, 0, 0, 0);
                ObjectSetInteger(0, rLineName, OBJPROP_COLOR, resColor);
                ObjectSetInteger(0, rLineName, OBJPROP_STYLE, STYLE_DOT);
                ObjectSetString(0, rLineName, OBJPROP_TEXT, "R" + IntegerToString(i + 1) + " Entry");
                ObjectSetInteger(0, rLineName, OBJPROP_FILL, false);
            }
            ObjectSetInteger(0, rLineName, OBJPROP_TIME, 0, (long)startTime);
            ObjectSetInteger(0, rLineName, OBJPROP_TIME, 1, (long)endTime);
            ObjectSetDouble(0, rLineName, OBJPROP_PRICE, 0, resistanceEntryPrices[i]);
            ObjectSetDouble(0, rLineName, OBJPROP_PRICE, 1, resistanceEntryPrices[i]);

            string sLineName = symbol + "_S_Entry" + IntegerToString(i + 1);
            if (ObjectFind(0, sLineName) < 0) {
                ObjectCreate(0, sLineName, OBJ_RECTANGLE, 0, 0, 0);
                ObjectSetInteger(0, sLineName, OBJPROP_COLOR, supColor);
                ObjectSetInteger(0, sLineName, OBJPROP_STYLE, STYLE_DOT);
                ObjectSetString(0, sLineName, OBJPROP_TEXT, "S" + IntegerToString(i + 1) + " Entry");
                ObjectSetInteger(0, sLineName, OBJPROP_FILL, false);
            }
            ObjectSetInteger(0, sLineName, OBJPROP_TIME, 0, (long)startTime);
            ObjectSetInteger(0, sLineName, OBJPROP_TIME, 1, (long)endTime);
            ObjectSetDouble(0, sLineName, OBJPROP_PRICE, 0, supportEntryPrices[i]);
            ObjectSetDouble(0, sLineName, OBJPROP_PRICE, 1, supportEntryPrices[i]);
        }
    }

    void deleteLines() {
        ObjectDelete(0, symbol + "_CenterLine");
        for (int i = 0; i < MAX_PIVOT_LEVELS; i++) {
            ObjectDelete(0, symbol + "_R_Entry" + IntegerToString(i + 1));
            ObjectDelete(0, symbol + "_S_Entry" + IntegerToString(i + 1));
        }
        ChartRedraw();
    }

    // getters
    double R(int level) {
        if (level < 1 || level > 5)
            return 0.0;
        return resistancePrices[level - 1];
    }
    double S(int level) {
        if (level < 1 || level > 5)
            return 0.0;
        return supportPrices[level - 1];
    }
    double centerLine() {
        return centerLinePrice;
    }
    double entryR(int level) {
        if (level < 1 || level > 5)
            return 0.0;
        return resistanceEntryPrices[level - 1];
    }
    double entryS(int level) {
        if (level < 1 || level > 5)
            return 0.0;
        return supportEntryPrices[level - 1];
    }
};

//--- position data class for sorting
class CPositionData : public CObject {
  public:
    ulong ticket;
    datetime openTime;
    // constructor
    CPositionData(ulong t, datetime ot) : ticket(t), openTime(ot) {
    }

    // comparison method for sorting
    virtual int Compare(const CObject *node, const int mode = 0) const override {
        const CPositionData *other = (const CPositionData *)node;
        if (openTime < other.openTime)
            return -1;
        if (openTime > other.openTime)
            return 1;
        return 0;
    }
};

//+------------------------------------------------------------------+
//| tradecontroller class                                            |
//+------------------------------------------------------------------+
class TradeController {
  private:
    PivotPoint *pivotPoint;
    CTrade *trade;
    CSymbolInfo *symbolInfo;
    CPositionInfo *positionInfo;

    long magicNumber;
    string symbol;
    int maxPositions;
    int maxEntryCount;
    bool hasSell;
    bool hasBuy;
    int dailyBuyEntries;
    int dailySellEntries;
    double buyEntryGapOvernight;
    double sellEntryGapOvernight;
    double minPointGap;

    // arrays to hold parsed lot sizes for performance
    double supportLots[];
    double resistanceLots[];
    int supportLotSteps;
    int resistanceLotSteps;

    double resistanceEntryPoints[MAX_PIVOT_LEVELS];
    double supportEntryPoints[MAX_PIVOT_LEVELS];

    ENUM_ENTRY_POSITION supportPositions[MAX_PIVOT_LEVELS];
    ENUM_ENTRY_POSITION resistancePositions[MAX_PIVOT_LEVELS];

    // flags to prevent multiple entries on the same line per day
    bool tradedResistance[MAX_PIVOT_LEVELS];
    bool tradedSupport[MAX_PIVOT_LEVELS];

    double tpValues[MAX_TP_SL_LEVELS];
    double slValues[MAX_TP_SL_LEVELS];

    double prevDayHighestBuy;
    double prevDayLowestSell;

  public:
    TradeController(PivotPoint &pp, CTrade &tr, string sym) {
        pivotPoint = &pp;
        trade = &tr;
        symbol = sym;

        symbolInfo = new CSymbolInfo();
        symbolInfo.Name(symbol);

        dailyBuyEntries = 0;
        dailySellEntries = 0;
        prevDayHighestBuy = 0.0;
        prevDayLowestSell = 0.0;

        positionInfo = new CPositionInfo();

        resetTradeFlags(); // initialize flags on creation
    }

    ~TradeController() {
        delete symbolInfo;
        delete positionInfo;
    }

    void init(long magic, int maxPos, int maxEntry, bool sell, bool buy, string sLots, string rLots, double buyGap,
              double sellGap, double minGap) {
        magicNumber = magic;
        maxPositions = maxPos;
        hasSell = sell;
        hasBuy = buy;
        maxEntryCount = maxEntry;
        buyEntryGapOvernight = buyGap;
        sellEntryGapOvernight = sellGap;
        minPointGap = minGap;

        // parse lot strings once on initialization
        parseLotStrings(sLots, rLots);
    }

    // --- RESTORED AND IMPROVED FUNCTION ---
    void initOrderSettings(ENUM_ENTRY_POSITION &s[], ENUM_ENTRY_POSITION &r[]) {
        for (int i = 0; i < MAX_PIVOT_LEVELS; i++) {
            supportPositions[i] = s[i];
            resistancePositions[i] = r[i];
        }
    }

    void initEntryPoints(double &r[], double &s[]) {
        for (int i = 0; i < MAX_PIVOT_LEVELS; i++) {
            resistanceEntryPoints[i] = r[i];
            supportEntryPoints[i] = s[i];
        }
    }

    void initTpSlSettings(double &tps[], double &sls[]) {
        int size = ArraySize(tpValues);
        for (int i = 0; i < size; i++) {
            tpValues[i] = tps[i];
            slValues[i] = sls[i];
        }
    }

    void execute() {
        /*
        if (AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) < MinMarginLevel) {
            Print("margin level is too low (", AccountInfoDouble(ACCOUNT_MARGIN_LEVEL),
            "%). no new trades are allowed.");
            return;
        }
        */
        symbolInfo.RefreshRates();
        checkEntryConditions();
        manageOpenPositions();
    }

    // called when a new day starts
    void resetTradeFlags() {
        for (int i = 0; i < MAX_PIVOT_LEVELS; i++) {
            tradedResistance[i] = false;
            tradedSupport[i] = false;
        }
        dailyBuyEntries = 0;
        dailySellEntries = 0;
        Print("daily trade flags have been reset for ", symbol);
    }

    void updateOvernightPriceLevels() {
        prevDayHighestBuy = 0.0;
        prevDayLowestSell = 0.0; // use 0 as a sign that there were no sell positions

        double highestBuy = 0.0;
        double lowestSell = 999999.0; // start with a very high number

        for (int i = PositionsTotal() - 1; i >= 0; i--) {
            if (positionInfo.SelectByIndex(i)) {
                if (positionInfo.Symbol() == symbol && positionInfo.Magic() == magicNumber) {
                    if (positionInfo.PositionType() == POSITION_TYPE_BUY) {
                        if (positionInfo.PriceOpen() > highestBuy) {
                            highestBuy = positionInfo.PriceOpen();
                        }
                    } else { // sell position
                        if (positionInfo.PriceOpen() < lowestSell) {
                            lowestSell = positionInfo.PriceOpen();
                        }
                    }
                }
            }
        }

        prevDayHighestBuy = highestBuy;
        if (lowestSell < 999999.0) { // check if any sell position was found
            prevDayLowestSell = lowestSell;
        }

        Print("overnight gap levels updated. prev day highest buy: ", prevDayHighestBuy,
              ", lowest sell: ", prevDayLowestSell);
    }

  private:
    void parseLotStrings(string sLots, string rLots) {
        string lotArray[];

        // parse support lots
        supportLotSteps = StringSplit(sLots, ',', lotArray);
        ArrayResize(supportLots, supportLotSteps);
        for (int i = 0; i < supportLotSteps; i++) {
            supportLots[i] = StringToDouble(lotArray[i]);
        }

        // parse resistance lots
        resistanceLotSteps = StringSplit(rLots, ',', lotArray);
        ArrayResize(resistanceLots, resistanceLotSteps);
        for (int i = 0; i < resistanceLotSteps; i++) {
            resistanceLots[i] = StringToDouble(lotArray[i]);
        }

        Print("lot sizes parsed successfully. support steps: ", supportLotSteps,
              ", resistance steps: ", resistanceLotSteps);
    }

    void checkEntryConditions() {
        for (int i = 0; i < MAX_PIVOT_LEVELS; i++) {
            if (resistancePositions[i] != NO_TRADE && !tradedResistance[i] && getAsk() >= pivotPoint.entryR(i + 1)) {
                handleTradeAction(resistancePositions[i], "R" + IntegerToString(i + 1));
                tradedResistance[i] = true;
            }
            if (supportPositions[i] != NO_TRADE && !tradedSupport[i] && getBid() <= pivotPoint.entryS(i + 1)) {
                handleTradeAction(supportPositions[i], "S" + IntegerToString(i + 1));
                tradedSupport[i] = true;
            }
        }
    }

    // --- CORRECTED FUNCTION ---
    void handleTradeAction(ENUM_ENTRY_POSITION action, string comment) {
        if (action == BUY && hasBuy) {
            double highestBuy = getHighestBuyPrice();
            if (highestBuy > 0 && getAsk() < highestBuy + minPointGap * symbolInfo.Point()) {
                return;
            }
            // Corrected logic: block if ask is NOT LESS THAN the required level
            if (prevDayHighestBuy > 0 && getAsk() >= prevDayHighestBuy + buyEntryGapOvernight * symbolInfo.Point()) {
                Print("buy entry blocked by overnight gap rule.");
                return;
            }
            if (countOpenPositions(POSITION_TYPE_BUY) < maxPositions && dailyBuyEntries < maxEntryCount) {
                double lot = getLotSize(POSITION_TYPE_BUY);
                if (lot > 0 && openNewPosition(ORDER_TYPE_BUY, getAsk(), lot, 0, 0, comment)) {
                    dailyBuyEntries++;
                }
            }
        } else if (action == SELL && hasSell) {
            double lowestSell = getLowestSellPrice();
            if (lowestSell > 0 && getBid() > lowestSell - minPointGap * symbolInfo.Point()) {
                return;
            }
            // Corrected logic: block if bid is NOT GREATER THAN the required
            // level
            if (prevDayLowestSell > 0 && getBid() <= prevDayLowestSell + sellEntryGapOvernight * symbolInfo.Point()) {
                Print("sell entry blocked by overnight gap rule.");
                return;
            }
            if (countOpenPositions(POSITION_TYPE_SELL) < maxPositions && dailySellEntries < maxEntryCount) {
                double lot = getLotSize(POSITION_TYPE_SELL);
                if (lot > 0 && openNewPosition(ORDER_TYPE_SELL, getBid(), lot, 0, 0, comment)) {
                    dailySellEntries++;
                }
            }
        }
    }

    void manageOpenPositions() {
        // get lists of buy and sell positions, sorted by open time
        CArrayObj *buyPositions = getOpenPositions(POSITION_TYPE_BUY);
        CArrayObj *sellPositions = getOpenPositions(POSITION_TYPE_SELL);

        // manage buy positions
        if (buyPositions != NULL) {
            for (int i = 0; i < buyPositions.Total(); i++) {
                CPositionData *posData = buyPositions.At(i);
                if (posData == NULL)
                    continue;
                // apply tp/sl based on the position's sequence (i)
                applyTpSl(posData.ticket, i);
            }
            delete buyPositions;
        }

        // manage sell positions
        if (sellPositions != NULL) {
            for (int i = 0; i < sellPositions.Total(); i++) {
                CPositionData *posData = sellPositions.At(i);
                if (posData == NULL)
                    continue;
                // apply tp/sl based on the position's sequence (i)
                applyTpSl(posData.ticket, i);
            }
            delete sellPositions;
        }
    }

    // gets a list of open positions for a given type, sorted by open time
    CArrayObj *getOpenPositions(ENUM_POSITION_TYPE type) {
        CArrayObj *positionList = new CArrayObj();
        for (int i = PositionsTotal() - 1; i >= 0; i--) {
            if (positionInfo.SelectByIndex(i)) {
                if (positionInfo.Symbol() == symbol && positionInfo.Magic() == magicNumber &&
                    positionInfo.PositionType() == type) {
                    // create a data object to hold ticket and time for sorting
                    CPositionData *posData = new CPositionData(positionInfo.Ticket(), positionInfo.Time());
                    positionList.Add(posData);
                }
            }
        }
        positionList.Sort(); // sort by open time, ascending (oldest first)
        return positionList;
    }

    // --- MODIFIED FUNCTION ---
    // now it only sets tp/sl once and then exits.
    void applyTpSl(ulong ticket, int positionIndex) {
        if (!positionInfo.SelectByTicket(ticket))
            return;

        // --- NEW LOGIC ---
        // if this position already has a tp and sl set, do nothing.
        // this prevents the unintended trailing stop behavior.
        if (positionInfo.TakeProfit() > 0 && positionInfo.StopLoss() > 0) {
            return;
        }

        if (positionIndex >= MAX_TP_SL_LEVELS)
            return;

        double openPrice = positionInfo.PriceOpen();
        double lotSize = positionInfo.Volume();

        symbolInfo.RefreshRates();
        double tickValue = symbolInfo.TickValue();
        double point = symbolInfo.Point();
        int stopsLevel = (int)symbolInfo.StopsLevel();
        double ask = symbolInfo.Ask();
        double bid = symbolInfo.Bid();

        if (lotSize <= 0 || tickValue <= 0)
            return;

        double idealTpPrice = 0;
        double idealSlPrice = 0;

        double tpPoints = tpValues[positionIndex] / (tickValue * lotSize);
        double slPoints = slValues[positionIndex] / (tickValue * lotSize);

        if (positionInfo.PositionType() == POSITION_TYPE_BUY) {
            idealTpPrice = openPrice + tpPoints * point;
            idealSlPrice = openPrice + slPoints * point;

            if (idealTpPrice > 0 && idealTpPrice < ask + stopsLevel * point) {
                idealTpPrice = ask + stopsLevel * point;
            }
            if (idealSlPrice > 0 && idealSlPrice > bid - stopsLevel * point) {
                idealSlPrice = bid - stopsLevel * point;
            }
        } else { // sell
            idealTpPrice = openPrice - tpPoints * point;
            idealSlPrice = openPrice - slPoints * point;

            if (idealTpPrice > 0 && idealTpPrice > bid - stopsLevel * point) {
                idealTpPrice = bid - stopsLevel * point;
            }
            if (idealSlPrice > 0 && idealSlPrice < ask + stopsLevel * point) {
                idealSlPrice = ask + stopsLevel * point;
            }
        }

        if (tpValues[positionIndex] == 0)
            idealTpPrice = 0.0;
        if (slValues[positionIndex] == 0)
            idealSlPrice = 0.0;

        double targetTpPrice = (idealTpPrice == 0) ? 0.0 : NormalizeDouble(idealTpPrice, (int)symbolInfo.Digits());
        double targetSlPrice = (idealSlPrice == 0) ? 0.0 : NormalizeDouble(idealSlPrice, (int)symbolInfo.Digits());

        // since we already checked if tp/sl exist, this check is no longer needed,
        // but we leave it for safety.
        if (MathAbs(targetTpPrice - positionInfo.TakeProfit()) > 0.000001 ||
            MathAbs(targetSlPrice - positionInfo.StopLoss()) > 0.000001) {
            bool modified = trade.PositionModify(ticket, targetSlPrice, targetTpPrice);
            if (modified) {
                Print("tp/sl for ticket #", ticket, " set to sl: ", targetSlPrice, ", tp: ", targetTpPrice);
            }
        }
    }

    // counts currently open positions for this ea and symbol
    int countOpenPositions(ENUM_POSITION_TYPE type) {
        int count = 0;
        for (int i = PositionsTotal() - 1; i >= 0; i--) {
            if (positionInfo.SelectByIndex(i)) {
                if (positionInfo.Symbol() == symbol && positionInfo.Magic() == magicNumber) {
                    if (positionInfo.PositionType() == type) {
                        count++;
                    }
                }
            }
        }
        return count;
    }

    // gets the correct lot size for the next trade based on the number of open
    // positions
    double getLotSize(ENUM_POSITION_TYPE type) {
        int count = countOpenPositions(type);

        if (type == POSITION_TYPE_BUY) {
            if (supportLotSteps == 0)
                return 0.0;
            if (count < supportLotSteps)
                return supportLots[count];
            return supportLots[supportLotSteps - 1]; // return last lot size if
                                                     // count exceeds steps
        } else {                                     // position_type_sell
            if (resistanceLotSteps == 0)
                return 0.0;
            if (count < resistanceLotSteps)
                return resistanceLots[count];
            return resistanceLots[resistanceLotSteps - 1]; // return last lot size
        }
    }

    // places the trade using the ctrade library
    bool openNewPosition(ENUM_ORDER_TYPE type, double price, double lot, double sl, double tp, string comment) {
        trade.SetExpertMagicNumber(magicNumber);
        trade.SetMarginMode();
        trade.SetTypeFillingBySymbol(symbol);

        bool result = false;
        if (type == ORDER_TYPE_SELL) {
            result = trade.Sell(lot, symbol, price, 0, 0, comment);
        } else if (type == ORDER_TYPE_BUY) {
            result = trade.Buy(lot, symbol, price, 0, 0, comment);
        }

        if (result) {
            Print("position opened successfully: ", comment, " @ ", price, " lot: ", lot);
        } else {
            Print("failed to open position. error: ", trade.ResultRetcode(), ", ", trade.ResultRetcodeDescription());
        }
        return result;
    }

    // --- new helper functions ---
    double getHighestBuyPrice() {
        double highestPrice = 0.0;
        for (int i = PositionsTotal() - 1; i >= 0; i--) {
            if (positionInfo.SelectByIndex(i)) {
                if (positionInfo.Symbol() == symbol && positionInfo.Magic() == magicNumber &&
                    positionInfo.PositionType() == POSITION_TYPE_BUY) {
                    if (positionInfo.PriceOpen() > highestPrice) {
                        highestPrice = positionInfo.PriceOpen();
                    }
                }
            }
        }
        return highestPrice;
    }

    double getLowestSellPrice() {
        double lowestPrice = 999999.0;
        bool sellExists = false;
        for (int i = PositionsTotal() - 1; i >= 0; i--) {
            if (positionInfo.SelectByIndex(i)) {
                if (positionInfo.Symbol() == symbol && positionInfo.Magic() == magicNumber &&
                    positionInfo.PositionType() == POSITION_TYPE_SELL) {
                    sellExists = true;
                    if (positionInfo.PriceOpen() < lowestPrice) {
                        lowestPrice = positionInfo.PriceOpen();
                    }
                }
            }
        }
        return sellExists ? lowestPrice : 0.0;
    }

    double getBid() {
        return symbolInfo.Bid();
    }
    double getAsk() {
        return symbolInfo.Ask();
    }
};

//--- global variables & init/deinit/ontick functions ---
PivotPoint *pivotPoint;
TradeController *tradeController;
CTrade trade;
bool needsRedraw = true; // global flag to control drawing

int OnInit() {
    pivotPoint = new PivotPoint(Symbol_1);

    double resistanceOffsets[] = {EntryOffsetR1, EntryOffsetR2, EntryOffsetR3, EntryOffsetR4, EntryOffsetR5};
    double supportOffsets[] = {EntryOffsetS1, EntryOffsetS2, EntryOffsetS3, EntryOffsetS4, EntryOffsetS5};
    pivotPoint.initializeEntryPoints(resistanceOffsets, supportOffsets);

    tradeController = new TradeController(*pivotPoint, trade, Symbol_1);
    tradeController.init(MagicNumber, MaxPositions, MaxEntryCount, HasSellPosition, HasBuyPosition, SupportLineLots,
                         ResistanceLineLots, BuyEntryGapOvernight, SellEntryGapOvernight, MinPointGap);

    ENUM_ENTRY_POSITION resistancePositions[] = {PositionR1, PositionR2, PositionR3, PositionR4, PositionR5};
    ENUM_ENTRY_POSITION supportPositions[] = {PositionS1, PositionS2, PositionS3, PositionS4, PositionS5};
    tradeController.initOrderSettings(supportPositions, resistancePositions);

    double tps[MAX_TP_SL_LEVELS] = {FirstEntryTP, SecondEntryTP,  ThirdEntryTP,  FourthEntryTP, FifthEntryTP,
                                    SixthEntryTP, SeventhEntryTP, EighthEntryTP, NinthEntryTP,  TenthEntryTP};
    double sls[MAX_TP_SL_LEVELS] = {FirstEntrySL, SecondEntrySL,  ThirdEntrySL,  FourthEntrySL, FifthEntrySL,
                                    SixthEntrySL, SeventhEntrySL, EighthEntrySL, NinthEntrySL,  TenthEntrySL};
    tradeController.initTpSlSettings(tps, sls);

    OnTick();
    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    if (pivotPoint != NULL) {
        pivotPoint.deleteLines();
        pivotPoint.deleteInfoPanel();
    }
    delete pivotPoint;
    delete tradeController;
}

void OnTick() {
    if (pivotPoint.update()) {
        needsRedraw = true;
        if (tradeController != NULL) {
            tradeController.resetTradeFlags();
            tradeController.updateOvernightPriceLevels();
        }
    }

    if (needsRedraw) {
        pivotPoint.drawLines(ResistanceLineColor, SupportLineColor, CenterLineColor);
        int digits = (int)SymbolInfoInteger(Symbol_1, SYMBOL_DIGITS);
        pivotPoint.drawInfoPanel(InfoDirection, digits);
        ChartRedraw();
        needsRedraw = false;
    }

    if (tradeController != NULL) {
        tradeController.execute();
    }
}
//+------------------------------------------------------------------+
