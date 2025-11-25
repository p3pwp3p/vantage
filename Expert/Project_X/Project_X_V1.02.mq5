//+------------------------------------------------------------------+
//|                                                 PivotPointEA.mq5 |
//|                                   Copyright 2025, Anonymous Ltd. |
//|                                        https://github.com/hayan2 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Anonymous Ltd."
#property link "https://github.com/hayan2"
#property version "1.02"  // version updated to reflect critical fixes

enum ENUM_INFO_DIRECTION { LEFT_UP = 1, LEFT_DOWN = 2 };
enum ENUM_ENTRY_POSITION { SELL, BUY, NO_TRADE };

input group "=============== Section 1 ===============";
input group "=============== Default Trade Setting ===============";
input long MagicNumber = 2147483647;
input double MaxLots = 0.15;
input bool BuySellSound = false;
input double MinMarginLevel = 400.0;
input ENUM_INFO_DIRECTION InfoDirection = LEFT_DOWN;
input string Symbol_1 = "GBPAUD";
input bool HasSellPosition = true;
input bool HasBuyPosition = true;
input string SupportLineLots =
    "0.02,0.02,0.03,0.04,0.05,0.06,0.07,0.08,0.09,0.10,0.11,0.13";
input string ResistanceLineLots =
    "0.02,0.02,0.03,0.04,0.05,0.06,0.07,0.08,0.09,0.10,0.11,0.13";
input double MinPointGap = 400.0;
input int MaxPostions = 9;
input int MaxBuyOrders = 12;
input int MaxSellOrders = 12;
input color SupportLineColor = Red;
input color ResistanceLineColor = DodgerBlue;
input group "Percent";
input double PercentS1 = -0.7;
input double PercentS2 = -1.5;
input double PercentS3 = -2.0;
input double PercentS4 = -3.0;
input double PercentS5 = -4.0;
input double PercentR1 = 0.7;
input double PercentR2 = 1.5;
input double PercentR3 = 2.0;
input double PercentR4 = 3.0;
input double PercentR5 = 4.0;
input group "Orders";
input ENUM_ENTRY_POSITION PositonS1 = BUY;
input ENUM_ENTRY_POSITION PositonS2 = BUY;
input ENUM_ENTRY_POSITION PositonS3 = BUY;
input ENUM_ENTRY_POSITION PositonS4 = BUY;
input ENUM_ENTRY_POSITION PositonS5 = BUY;
input ENUM_ENTRY_POSITION PositonR1 = SELL;
input ENUM_ENTRY_POSITION PositonR2 = SELL;
input ENUM_ENTRY_POSITION PositonR3 = SELL;
input ENUM_ENTRY_POSITION PositonR4 = SELL;
input ENUM_ENTRY_POSITION PositonR5 = SELL;
input group "Close Positions";
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

//+------------------------------------------------------------------+
//| PivotPoint Class                                                 |
//| calculates, stores, and draws support/resistance levels.         |
//+------------------------------------------------------------------+
class PivotPoint {
   private:
    datetime lastUpdateTime;
    string symbol;

    // arrays for entry offset Percentages
    double resistanceEntryPercents[5];
    double supportEntryPercents[5];

    // arrays for calculated fibonacci pivot line prices (for drawing)
    double resistancePrices[5];
    double supportPrices[5];

    // arrays for final entry prices (for trading)
    double resistanceEntryPrices[5];
    double supportEntryPrices[5];

   public:
    PivotPoint(string sym) {
        symbol = sym;
        lastUpdateTime = 0;
    }

    ~PivotPoint() {}

    // now correctly initializes the entry offset percentages
    void initializeEntryPercents(double r1, double r2, double r3, double r4,
                                 double r5, double s1, double s2, double s3,
                                 double s4, double s5) {
        resistanceEntryPercents[0] = r1;
        resistanceEntryPercents[1] = r2;
        resistanceEntryPercents[2] = r3;
        resistanceEntryPercents[3] = r4;
        resistanceEntryPercents[4] = r5;
        supportEntryPercents[0] = s1;
        supportEntryPercents[1] = s2;
        supportEntryPercents[2] = s3;
        supportEntryPercents[3] = s4;
        supportEntryPercents[4] = s5;
    }

    bool update() {
        MqlDateTime currentTimeStruct;
        TimeToStruct(TimeCurrent(), currentTimeStruct);
        MqlDateTime lastUpdateTimeStruct;
        TimeToStruct(lastUpdateTime, lastUpdateTimeStruct);

        if (lastUpdateTime == 0 ||
            currentTimeStruct.day != lastUpdateTimeStruct.day) {
            MqlRates rates[];
            if (CopyRates(symbol, PERIOD_D1, 1, 1, rates) < 1) {
                Print("Failed to get previous day's candle data for ", symbol);
                return false;
            }

            double prevHigh = rates[0].high;
            double prevLow = rates[0].low;
            double prevClose = rates[0].close;
            double range = prevHigh - prevLow;

            // --- calculate fibonacci pivot points ---
            double pivotPointPrice = (prevHigh + prevLow + prevClose) / 3.0;

            // calculate Resistance lines (for drawing)
            resistancePrices[0] = pivotPointPrice + (range * 0.382);  // R1
            resistancePrices[1] = pivotPointPrice + (range * 0.618);  // R2
            resistancePrices[2] = pivotPointPrice + (range * 1.000);  // R3
            resistancePrices[3] =
                pivotPointPrice + (range * 1.382);  // R4 (Extended)
            resistancePrices[4] =
                pivotPointPrice + (range * 1.618);  // R5 (Extended)

            // calculate support lines (for drawing)
            supportPrices[0] = pivotPointPrice - (range * 0.382);  // S1
            supportPrices[1] = pivotPointPrice - (range * 0.618);  // S2
            supportPrices[2] = pivotPointPrice - (range * 1.000);  // S3
            supportPrices[3] =
                pivotPointPrice - (range * 1.382);  // S4 (Extended)
            supportPrices[4] =
                pivotPointPrice - (range * 1.618);  // S5 (Extended)

            // --- calculate final entry prices using the offset
            for (int i = 0; i < 5; i++) {
                resistanceEntryPrices[i] =
                    resistancePrices[i] *
                    (1 + resistanceEntryPercents[i] / 100.0);
                supportEntryPrices[i] =
                    supportPrices[i] * (1 + supportEntryPercents[i] / 100.0);
            }

            lastUpdateTime = TimeCurrent();
            Print("Fibonacci Pivot prices updated for ", symbol);
            return true;
        }
        return false;
    }

    void drawLines(color resColor, color supColor) {
        for (int i = 0; i < 5; i++) {
            // lines are drawn at the calculated fibonacci pivot levels
            string rLineName = symbol + "_R" + IntegerToString(i + 1);
            if (ObjectFind(0, rLineName) < 0)
                ObjectCreate(0, rLineName, OBJ_HLINE, 0, 0, 0);
            ObjectSetInteger(0, rLineName, OBJPROP_COLOR, resColor);
            ObjectSetString(0, rLineName, OBJPROP_TEXT,
                            "R" + IntegerToString(i + 1));
            ObjectSetDouble(0, rLineName, OBJPROP_PRICE, resistancePrices[i]);

            string sLineName = symbol + "_S" + IntegerToString(i + 1);
            if (ObjectFind(0, sLineName) < 0)
                ObjectCreate(0, sLineName, OBJ_HLINE, 0, 0, 0);
            ObjectSetInteger(0, sLineName, OBJPROP_COLOR, supColor);
            ObjectSetString(0, sLineName, OBJPROP_TEXT,
                            "S" + IntegerToString(i + 1));
            ObjectSetDouble(0, sLineName, OBJPROP_PRICE, supportPrices[i]);
        }
    }

    void deleteLines() {
        for (int i = 0; i < 5; i++) {
            ObjectDelete(0, symbol + "_R" + IntegerToString(i + 1));
            ObjectDelete(0, symbol + "_S" + IntegerToString(i + 1));
        }
        ChartRedraw();
    }

    // getters for drawn line prices
    double R(int level) {
        if (level < 1 || level > 5) return 0;
        return resistancePrices[level - 1];
    }
    double S(int level) {
        if (level < 1 || level > 5) return 0;
        return supportPrices[level - 1];
    }

    // getters for final entry prices
    double entryR(int level) {
        if (level < 1 || level > 5) return 0;
        return resistanceEntryPrices[level - 1];
    }
    double entryS(int level) {
        if (level < 1 || level > 5) return 0;
        return supportEntryPrices[level - 1];
    }
};

//+------------------------------------------------------------------+
//| TradeController Class (Placeholder)                              |
//+------------------------------------------------------------------+
class TradeController {};

#include <Trade/Trade.mqh>

PivotPoint *pivotPoint;
CTrade trade;

//+------------------------------------------------------------------+
int OnInit() {
    pivotPoint = new PivotPoint(Symbol_1);

    pivotPoint.initializeEntryPercents(
        PercentR1, PercentR2, PercentR3, PercentR4, PercentR5, PercentS1,
        PercentS2, PercentS3, PercentS4, PercentS5);

    OnTick();
    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    pivotPoint.deleteLines();
    delete pivotPoint;
}

//+------------------------------------------------------------------+
void OnTick() {
    if (pivotPoint.update()) {
        pivotPoint.drawLines(ResistanceLineColor, SupportLineColor);
        ChartRedraw();
    }
}
//+------------------------------------------------------------------+
