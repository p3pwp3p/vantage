//+------------------------------------------------------------------+
//|                                   Project X Backtest Only.mq5    |
//|                               Copyright 2025, Arctane FinTech.   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Arctane FinTech."
#property version "1.0"
#property strict

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_PIVOT_METHOD {
    PIVOT_CLASSIC,
    PIVOT_FIBONACCI,
    PIVOT_WOODIE,
    PIVOT_CAMARILLA,
    PIVOT_DEMARK
};

enum ENUM_INFO_DIRECTION {
    DIR_LEFT_UP,
    DIR_LEFT_DOWN,
    DIR_RIGHT_UP,
    DIR_RIGHT_DOWN
};

enum ENUM_ENTRY_POSITION { POS_SELL, POS_BUY, POS_NO_TRADE };

//+------------------------------------------------------------------+
//| Input Parameters: Section 1                                      |
//+------------------------------------------------------------------+
input group "=============== Section 1 ===============";
input string Symbol_1 = "GBPAUD";
input long MagicNumber_1 = 202501;
input ENUM_PIVOT_METHOD PivotMethod_1 = PIVOT_CLASSIC;
input double MaxLots_1 = 0.15;
input bool BuySellSound_1 = false;
input double MinMarginLevel_1 = 400.0;
input ENUM_INFO_DIRECTION InfoDirection_1 = DIR_LEFT_DOWN;

input group "=============== Section 1 Strategy ===============";
input bool HasSellPosition_1 = true;
input bool HasBuyPosition_1 = true;
input string SupportLineLots_1 = "0.02,0.02,0.03,0.04,0.05";
input string ResistanceLineLots_1 = "0.02,0.02,0.03,0.04,0.05";
input double MinPointGap_1 = 400.0;
input int MaxPositions_1 = 9;
input int MaxBuyOrders_1 = 12;
input int MaxSellOrders_1 = 12;
input color SupportLineColor_1 = clrRed;
input color ResistanceLineColor_1 = clrDodgerBlue;

input group "=============== Section 1 Percent ===============";
input double PercentS1_1 = -0.7;
input double PercentS2_1 = -1.5;
input double PercentS3_1 = -2.0;
input double PercentS4_1 = -3.0;
input double PercentS5_1 = -4.0;
input double PercentR1_1 = 0.7;
input double PercentR2_1 = 1.5;
input double PercentR3_1 = 2.0;
input double PercentR4_1 = 3.0;
input double PercentR5_1 = 4.0;

input group "=============== Section 1 Orders ===============";
input ENUM_ENTRY_POSITION PositionS1_1 = POS_BUY;
input ENUM_ENTRY_POSITION PositionS2_1 = POS_BUY;
input ENUM_ENTRY_POSITION PositionS3_1 = POS_BUY;
input ENUM_ENTRY_POSITION PositionS4_1 = POS_BUY;
input ENUM_ENTRY_POSITION PositionS5_1 = POS_BUY;
input ENUM_ENTRY_POSITION PositionR1_1 = POS_SELL;
input ENUM_ENTRY_POSITION PositionR2_1 = POS_SELL;
input ENUM_ENTRY_POSITION PositionR3_1 = POS_SELL;
input ENUM_ENTRY_POSITION PositionR4_1 = POS_SELL;
input ENUM_ENTRY_POSITION PositionR5_1 = POS_SELL;

input group "=============== Section 1 TP/SL (USD) ===============";
input double FirstEntryTP_1 = 5.0;
input double FirstEntrySL_1 = -5.0;
input double SecondEntryTP_1 = 7.0;
input double SecondEntrySL_1 = -7.0;
input double ThirdEntryTP_1 = 12.0;
input double ThirdEntrySL_1 = -12.0;
input double FourthEntryTP_1 = 17.0;
input double FourthEntrySL_1 = -17.0;
input double FifthEntryTP_1 = 23.0;
input double FifthEntrySL_1 = -23.0;

//+------------------------------------------------------------------+
//| Input Parameters: Section 2                                      |
//+------------------------------------------------------------------+
input group "=============== Section 2 ===============";
input string Symbol_2 = "";
input long MagicNumber_2 = 202502;
input ENUM_PIVOT_METHOD PivotMethod_2 = PIVOT_FIBONACCI;
input double MaxLots_2 = 0.15;
input bool BuySellSound_2 = false;
input double MinMarginLevel_2 = 400.0;
input ENUM_INFO_DIRECTION InfoDirection_2 = DIR_LEFT_DOWN;

input group "=============== Section 2 Strategy ===============";
input bool HasSellPosition_2 = true;
input bool HasBuyPosition_2 = true;
input string SupportLineLots_2 = "0.02,0.02,0.03";
input string ResistanceLineLots_2 = "0.02,0.02,0.03";
input double MinPointGap_2 = 400.0;
input int MaxPositions_2 = 9;
input int MaxBuyOrders_2 = 12;
input int MaxSellOrders_2 = 12;
input color SupportLineColor_2 = clrRed;
input color ResistanceLineColor_2 = clrDodgerBlue;

input group "=============== Section 2 Percent ===============";
input double PercentS1_2 = -0.7;
input double PercentS2_2 = -1.5;
input double PercentS3_2 = -2.0;
input double PercentS4_2 = -3.0;
input double PercentS5_2 = -4.0;
input double PercentR1_2 = 0.7;
input double PercentR2_2 = 1.5;
input double PercentR3_2 = 2.0;
input double PercentR4_2 = 3.0;
input double PercentR5_2 = 4.0;

input group "=============== Section 2 Orders ===============";
input ENUM_ENTRY_POSITION PositionS1_2 = POS_BUY;
input ENUM_ENTRY_POSITION PositionS2_2 = POS_BUY;
input ENUM_ENTRY_POSITION PositionS3_2 = POS_BUY;
input ENUM_ENTRY_POSITION PositionS4_2 = POS_BUY;
input ENUM_ENTRY_POSITION PositionS5_2 = POS_BUY;
input ENUM_ENTRY_POSITION PositionR1_2 = POS_SELL;
input ENUM_ENTRY_POSITION PositionR2_2 = POS_SELL;
input ENUM_ENTRY_POSITION PositionR3_2 = POS_SELL;
input ENUM_ENTRY_POSITION PositionR4_2 = POS_SELL;
input ENUM_ENTRY_POSITION PositionR5_2 = POS_SELL;

input group "=============== Section 2 TP/SL (USD) ===============";
input double FirstEntryTP_2 = 5.0;
input double FirstEntrySL_2 = -5.0;
input double SecondEntryTP_2 = 7.0;
input double SecondEntrySL_2 = -7.0;
input double ThirdEntryTP_2 = 12.0;
input double ThirdEntrySL_2 = -12.0;
input double FourthEntryTP_2 = 17.0;
input double FourthEntrySL_2 = -17.0;
input double FifthEntryTP_2 = 23.0;
input double FifthEntrySL_2 = -23.0;

//+------------------------------------------------------------------+
//| Input Parameters: Section 3                                      |
//+------------------------------------------------------------------+
input group "=============== Section 3 ===============";
input string Symbol_3 = "";
input long MagicNumber_3 = 202503;
input ENUM_PIVOT_METHOD PivotMethod_3 = PIVOT_CAMARILLA;
input double MaxLots_3 = 0.15;
input bool BuySellSound_3 = false;
input double MinMarginLevel_3 = 400.0;
input ENUM_INFO_DIRECTION InfoDirection_3 = DIR_LEFT_DOWN;

input group "=============== Section 3 Strategy ===============";
input bool HasSellPosition_3 = true;
input bool HasBuyPosition_3 = true;
input string SupportLineLots_3 = "0.01";
input string ResistanceLineLots_3 = "0.01";
input double MinPointGap_3 = 400.0;
input int MaxPositions_3 = 9;
input int MaxBuyOrders_3 = 12;
input int MaxSellOrders_3 = 12;
input color SupportLineColor_3 = clrRed;
input color ResistanceLineColor_3 = clrDodgerBlue;

input group "=============== Section 3 Percent ===============";
input double PercentS1_3 = -0.7;
input double PercentS2_3 = -1.5;
input double PercentS3_3 = -2.0;
input double PercentS4_3 = -3.0;
input double PercentS5_3 = -4.0;
input double PercentR1_3 = 0.7;
input double PercentR2_3 = 1.5;
input double PercentR3_3 = 2.0;
input double PercentR4_3 = 3.0;
input double PercentR5_3 = 4.0;

input group "=============== Section 3 Orders ===============";
input ENUM_ENTRY_POSITION PositionS1_3 = POS_BUY;
input ENUM_ENTRY_POSITION PositionS2_3 = POS_BUY;
input ENUM_ENTRY_POSITION PositionS3_3 = POS_BUY;
input ENUM_ENTRY_POSITION PositionS4_3 = POS_BUY;
input ENUM_ENTRY_POSITION PositionS5_3 = POS_BUY;
input ENUM_ENTRY_POSITION PositionR1_3 = POS_SELL;
input ENUM_ENTRY_POSITION PositionR2_3 = POS_SELL;
input ENUM_ENTRY_POSITION PositionR3_3 = POS_SELL;
input ENUM_ENTRY_POSITION PositionR4_3 = POS_SELL;
input ENUM_ENTRY_POSITION PositionR5_3 = POS_SELL;

input group "=============== Section 3 TP/SL (USD) ===============";
input double FirstEntryTP_3 = 5.0;
input double FirstEntrySL_3 = -5.0;
input double SecondEntryTP_3 = 7.0;
input double SecondEntrySL_3 = -7.0;
input double ThirdEntryTP_3 = 12.0;
input double ThirdEntrySL_3 = -12.0;
input double FourthEntryTP_3 = 17.0;
input double FourthEntrySL_3 = -17.0;
input double FifthEntryTP_3 = 23.0;
input double FifthEntrySL_3 = -23.0;

//+------------------------------------------------------------------+
//| Class: CPivotStrategy                                            |
//+------------------------------------------------------------------+
class CPivotStrategy {
   private:
    // --- Identification ---
    string m_symbol;
    long m_magic;
    bool m_isActive;

    // --- Cached Symbol Info (Optimization) ---
    double m_point;
    int m_digits;

    // --- Settings ---
    ENUM_PIVOT_METHOD m_method;
    double m_maxLots;
    bool m_enableBuy;
    bool m_enableSell;
    double m_minMargin;

    // --- Visual Settings ---
    color m_colorR;
    color m_colorS;

    // --- Data Containers ---
    double m_sLots[];
    double m_rLots[];

    struct LevelSettings {
        double percent;
        ENUM_ENTRY_POSITION posDir;
    };
    LevelSettings m_rLevels[5];
    LevelSettings m_sLevels[5];

    double m_stepTP[10];
    double m_stepSL[10];

    // --- Trade State & Objects ---
    CTrade m_trade;
    datetime m_lastDayTime;

    // --- Pivot Values ---
    double P, R1, R2, R3, R4, R5, S1, S2, S3, S4, S5;

    // --- Execution Flags ---
    bool m_isTraded_R[5];
    bool m_isTraded_S[5];

    // --- Helper: Parse Lot String ---
    void ParseLotString(string inputStr, double& outputArr[]) {
        string elements[];
        int total = StringSplit(inputStr, ',', elements);
        if (total > 0) {
            ArrayResize(outputArr, total);
            for (int i = 0; i < total; i++)
                outputArr[i] = StringToDouble(elements[i]);
        } else {
            ArrayResize(outputArr, 1);
            outputArr[0] = 0.01;
        }
    }

    // --- Helper: Count Open Positions ---
    int GetMagicPositionCount() {
        int count = 0;
        int total = PositionsTotal();
        // Optimization: No need to loop if total is 0
        if (total == 0) return 0;

        for (int i = 0; i < total; i++) {
            if (PositionGetSymbol(i) == m_symbol &&
                PositionGetInteger(POSITION_MAGIC) == m_magic)
                count++;
        }
        return count;
    }

    // --- Helper: Draw Line ---
    void DrawLine(string name, double price, color clr, string desc,
                  datetime startTime, datetime endTime) {
        string objName = m_symbol + "_" + IntegerToString(m_magic) + "_" + name;
        if (ObjectFind(0, objName) >= 0) ObjectDelete(0, objName);
        if (ObjectCreate(0, objName, OBJ_TREND, 0, startTime, price, endTime,
                         price)) {
            ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
            ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DASH);
            ObjectSetString(0, objName, OBJPROP_TEXT, desc);
            ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
        }
    }

    // --- Helper: Delete All Lines ---
    void DeleteAllLines() {
        ObjectsDeleteAll(0, m_symbol + "_" + IntegerToString(m_magic) + "_");
    }

    // --- Helper: Calculate Pivot Points ---
    void CalculatePivots() {
        double h[], l[], c[], o[];  // Added 'o' for DeMark
        ArraySetAsSeries(h, true);
        ArraySetAsSeries(l, true);
        ArraySetAsSeries(c, true);
        ArraySetAsSeries(o, true);

        if (CopyHigh(m_symbol, PERIOD_D1, 1, 1, h) < 1 ||
            CopyLow(m_symbol, PERIOD_D1, 1, 1, l) < 1 ||
            CopyClose(m_symbol, PERIOD_D1, 1, 1, c) < 1 ||
            CopyOpen(m_symbol, PERIOD_D1, 1, 1, o) < 1)
            return;

        double H = h[0];
        double L = l[0];
        double C = c[0];
        double O = o[0];
        double Range = H - L;

        P = 0;
        R1 = 0;
        R2 = 0;
        R3 = 0;
        R4 = 0;
        R5 = 0;
        S1 = 0;
        S2 = 0;
        S3 = 0;
        S4 = 0;
        S5 = 0;

        switch (m_method) {
            case PIVOT_CLASSIC:
                P = (H + L + C) / 3.0;
                R1 = (2 * P) - L;
                S1 = (2 * P) - H;
                R2 = P + Range;
                S2 = P - Range;
                R3 = H + 2 * (P - L);
                S3 = L - 2 * (H - P);
                R4 = R3 + Range;
                R5 = R4 + Range;
                S4 = S3 - Range;
                S5 = S4 - Range;
                break;

            case PIVOT_FIBONACCI:
                P = (H + L + C) / 3.0;
                R1 = P + (Range * 0.382);
                S1 = P - (Range * 0.382);
                R2 = P + (Range * 0.618);
                S2 = P - (Range * 0.618);
                R3 = P + (Range * 1.000);
                S3 = P - (Range * 1.000);
                R4 = P + (Range * 1.382);
                S4 = P - (Range * 1.382);
                R5 = P + (Range * 1.618);
                S5 = P - (Range * 1.618);
                break;

            case PIVOT_WOODIE:
                // Woodie's Pivot: (High + Low + 2*Close) / 4
                P = (H + L + 2.0 * C) / 4.0;
                R1 = (2.0 * P) - L;
                S1 = (2.0 * P) - H;
                R2 = P + Range;
                S2 = P - Range;
                // Woodie typically defines R1-R2. We extrapolate R3-R5 for EA
                // compatibility.
                R3 = R1 + Range;
                R4 = R3 + Range;
                R5 = R4 + Range;
                S3 = S1 - Range;
                S4 = S3 - Range;
                S5 = S4 - Range;
                break;

            case PIVOT_CAMARILLA:
                P = (H + L + C) / 3.0;  // Visual Pivot only
                // Camarilla Equation
                R4 = C + Range * 1.1 / 2.0;
                R3 = C + Range * 1.1 / 4.0;
                R2 = C + Range * 1.1 / 6.0;
                R1 = C + Range * 1.1 / 12.0;
                S1 = C - Range * 1.1 / 12.0;
                S2 = C - Range * 1.1 / 6.0;
                S3 = C - Range * 1.1 / 4.0;
                S4 = C - Range * 1.1 / 2.0;
                // Extrapolate R5/S5
                R5 = R4 + (R4 - R3);
                S5 = S4 - (S4 - S3);
                break;

            case PIVOT_DEMARK: {
                double X;
                if (C < O)
                    X = H + 2.0 * L + C;
                else if (C > O)
                    X = 2.0 * H + L + C;
                else
                    X = H + L + 2.0 * C;

                P = X / 4.0;
                R1 = X / 2.0 - L;
                S1 = X / 2.0 - H;
                // DeMark only has 1 level. We extrapolate others using Classic
                // method from P
                R2 = P + Range;
                S2 = P - Range;
                R3 = R1 + Range;
                R4 = R3 + Range;
                R5 = R4 + Range;
                S3 = S1 - Range;
                S4 = S3 - Range;
                S5 = S4 - Range;
                break;
            }

            default:  // Fallback to Classic
                P = (H + L + C) / 3.0;
                R1 = (2 * P) - L;
                S1 = (2 * P) - H;
                break;
        }

        m_lastDayTime = iTime(m_symbol, PERIOD_D1, 0);

        ArrayInitialize(m_isTraded_R, false);
        ArrayInitialize(m_isTraded_S, false);

        DrawLevels();
    }

    // --- Draw Levels ---
    void DrawLevels() {
        if (!m_isActive) return;
        datetime dayStart = iTime(m_symbol, PERIOD_D1, 0);
        datetime dayEnd = dayStart + PeriodSeconds(PERIOD_D1);

        DrawLine("P", P, clrGray, "Pivot", dayStart, dayEnd);
        DrawLine("R1", R1 * (1.0 + m_rLevels[0].percent / 100.0), m_colorR,
                 "R1", dayStart, dayEnd);
        DrawLine("R2", R2 * (1.0 + m_rLevels[1].percent / 100.0), m_colorR,
                 "R2", dayStart, dayEnd);
        DrawLine("R3", R3 * (1.0 + m_rLevels[2].percent / 100.0), m_colorR,
                 "R3", dayStart, dayEnd);
        DrawLine("R4", R4 * (1.0 + m_rLevels[3].percent / 100.0), m_colorR,
                 "R4", dayStart, dayEnd);
        DrawLine("R5", R5 * (1.0 + m_rLevels[4].percent / 100.0), m_colorR,
                 "R5", dayStart, dayEnd);
        DrawLine("S1", S1 * (1.0 + m_sLevels[0].percent / 100.0), m_colorS,
                 "S1", dayStart, dayEnd);
        DrawLine("S2", S2 * (1.0 + m_sLevels[1].percent / 100.0), m_colorS,
                 "S2", dayStart, dayEnd);
        DrawLine("S3", S3 * (1.0 + m_sLevels[2].percent / 100.0), m_colorS,
                 "S3", dayStart, dayEnd);
        DrawLine("S4", S4 * (1.0 + m_sLevels[3].percent / 100.0), m_colorS,
                 "S4", dayStart, dayEnd);
        DrawLine("S5", S5 * (1.0 + m_sLevels[4].percent / 100.0), m_colorS,
                 "S5", dayStart, dayEnd);
        ChartRedraw(0);
    }

   public:
    CPivotStrategy() : m_isActive(false) {}
    ~CPivotStrategy() { DeleteAllLines(); }

    // --- Initializer ---
    void Init(string sym, long magic, ENUM_PIVOT_METHOD method, string sLotStr,
              string rLotStr, bool eBuy, bool eSell, double pr1, double pr2,
              double pr3, double pr4, double pr5, double ps1, double ps2,
              double ps3, double ps4, double ps5, ENUM_ENTRY_POSITION posR1,
              ENUM_ENTRY_POSITION posR2, ENUM_ENTRY_POSITION posR3,
              ENUM_ENTRY_POSITION posR4, ENUM_ENTRY_POSITION posR5,
              ENUM_ENTRY_POSITION posS1, ENUM_ENTRY_POSITION posS2,
              ENUM_ENTRY_POSITION posS3, ENUM_ENTRY_POSITION posS4,
              ENUM_ENTRY_POSITION posS5, double tp1, double sl1, double tp2,
              double sl2, double tp3, double sl3, double tp4, double sl4,
              double tp5, double sl5, color cR, color cS, double minMargin) {
        m_symbol = sym;
        m_magic = magic;
        m_method = method;
        m_colorR = cR;
        m_colorS = cS;
        m_minMargin = minMargin;

        if (m_symbol == "" || m_symbol == NULL) {
            m_isActive = false;
            return;
        }
        m_isActive = true;
        m_enableBuy = eBuy;
        m_enableSell = eSell;

        // Optimization: Cache Static Info
        m_point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

        ParseLotString(sLotStr, m_sLots);
        ParseLotString(rLotStr, m_rLots);

        m_rLevels[0].percent = pr1;
        m_rLevels[0].posDir = posR1;
        m_rLevels[1].percent = pr2;
        m_rLevels[1].posDir = posR2;
        m_rLevels[2].percent = pr3;
        m_rLevels[2].posDir = posR3;
        m_rLevels[3].percent = pr4;
        m_rLevels[3].posDir = posR4;
        m_rLevels[4].percent = pr5;
        m_rLevels[4].posDir = posR5;

        m_sLevels[0].percent = ps1;
        m_sLevels[0].posDir = posS1;
        m_sLevels[1].percent = ps2;
        m_sLevels[1].posDir = posS2;
        m_sLevels[2].percent = ps3;
        m_sLevels[2].posDir = posS3;
        m_sLevels[3].percent = ps4;
        m_sLevels[3].posDir = posS4;
        m_sLevels[4].percent = ps5;
        m_sLevels[4].posDir = posS5;

        m_stepTP[0] = tp1;
        m_stepSL[0] = sl1;
        m_stepTP[1] = tp2;
        m_stepSL[1] = sl2;
        m_stepTP[2] = tp3;
        m_stepSL[2] = sl3;
        m_stepTP[3] = tp4;
        m_stepSL[3] = sl4;
        m_stepTP[4] = tp5;
        m_stepSL[4] = sl5;

        m_trade.SetExpertMagicNumber(m_magic);
        m_trade.SetDeviationInPoints(10);
        m_trade.SetTypeFillingBySymbol(m_symbol);
        m_trade.SetMarginMode();
    }

    // --- Main Logic (Optimized: Calculate Position Count ONCE) ---
    void OnTick() {
        if (!m_isActive) return;

        datetime today = iTime(m_symbol, PERIOD_D1, 0);
        if (today != m_lastDayTime) CalculatePivots();

        // Optimization: Fetch Price once
        double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
        double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

        if (m_minMargin > 0 &&
            AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) < m_minMargin &&
            AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) != 0)
            return;

        // Optimization: Calculate Position Count ONCE per tick per section
        int currentPosCount = GetMagicPositionCount();

        // Check all levels (Pass cached count)
        CheckLevel(0, R1, m_rLevels[0], m_rLots, bid, ask, currentPosCount,
                   true);
        CheckLevel(1, R2, m_rLevels[1], m_rLots, bid, ask, currentPosCount,
                   true);
        CheckLevel(2, R3, m_rLevels[2], m_rLots, bid, ask, currentPosCount,
                   true);
        CheckLevel(3, R4, m_rLevels[3], m_rLots, bid, ask, currentPosCount,
                   true);
        CheckLevel(4, R5, m_rLevels[4], m_rLots, bid, ask, currentPosCount,
                   true);

        CheckLevel(0, S1, m_sLevels[0], m_sLots, bid, ask, currentPosCount,
                   false);
        CheckLevel(1, S2, m_sLevels[1], m_sLots, bid, ask, currentPosCount,
                   false);
        CheckLevel(2, S3, m_sLevels[2], m_sLots, bid, ask, currentPosCount,
                   false);
        CheckLevel(3, S4, m_sLevels[3], m_sLots, bid, ask, currentPosCount,
                   false);
        CheckLevel(4, S5, m_sLevels[4], m_sLots, bid, ask, currentPosCount,
                   false);
    }

    // --- Entry Logic (Optimized) ---
    void CheckLevel(int stepIndex, double basePrice, LevelSettings& settings,
                    double& lots[], double bid, double ask, int currentPosCount,
                    bool isResistance) {
        // Check trade flag first to avoid unnecessary math
        if (isResistance) {
            if (m_isTraded_R[stepIndex]) return;
        } else {
            if (m_isTraded_S[stepIndex]) return;
        }

        double entryPrice = basePrice * (1.0 + settings.percent / 100.0);

        double vol = 0.01;
        if (currentPosCount < ArraySize(lots))
            vol = lots[currentPosCount];
        else
            vol = lots[ArraySize(lots) - 1];

        bool signal = false;
        if (isResistance) {
            if (settings.posDir == POS_SELL && m_enableSell) {
                if (bid >= entryPrice) signal = true;
            } else if (settings.posDir == POS_BUY && m_enableBuy) {
                if (ask >= entryPrice) signal = true;
            }
        } else  // Support
        {
            if (settings.posDir == POS_BUY && m_enableBuy) {
                if (bid <= entryPrice) signal = true;
            } else if (settings.posDir == POS_SELL && m_enableSell) {
                if (bid <= entryPrice) signal = true;
            }
        }

        if (signal) {
            int tpStepIndex = currentPosCount;
            if (tpStepIndex >= 10) tpStepIndex = 9;

            double tickValue =
                SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
            if (tickValue <= 0) tickValue = 1.0;

            double targetProfitUSD = MathAbs(m_stepTP[tpStepIndex]);
            double targetLossUSD = MathAbs(m_stepSL[tpStepIndex]);

            double requiredPointsTP = targetProfitUSD / (tickValue * vol);
            double requiredPointsSL = targetLossUSD / (tickValue * vol);

            long stopLevel =
                SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
            int spread = (int)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
            double safeMinPoints = (double)(stopLevel + spread + 20);
            if (safeMinPoints < 50.0) safeMinPoints = 50.0;

            if (requiredPointsTP < safeMinPoints)
                requiredPointsTP = safeMinPoints;
            if (requiredPointsSL < safeMinPoints)
                requiredPointsSL = safeMinPoints;

            double distPriceTP =
                requiredPointsTP * m_point;  // Use cached point
            double distPriceSL = requiredPointsSL * m_point;

            bool result = false;

            if (settings.posDir == POS_SELL) {
                double sl = bid + distPriceSL;
                double tp = bid - distPriceTP;
                sl = NormalizeDouble(sl, m_digits);
                tp = NormalizeDouble(tp, m_digits);
                result =
                    m_trade.Sell(vol, m_symbol, bid, sl, tp,
                                 "Pivot R" + IntegerToString(stepIndex + 1));
            } else if (settings.posDir == POS_BUY) {
                double sl = ask - distPriceSL;
                double tp = ask + distPriceTP;
                sl = NormalizeDouble(sl, m_digits);
                tp = NormalizeDouble(tp, m_digits);
                result =
                    m_trade.Buy(vol, m_symbol, ask, sl, tp,
                                "Pivot S" + IntegerToString(stepIndex + 1));
            }

            if (result) {
                if (isResistance)
                    m_isTraded_R[stepIndex] = true;
                else
                    m_isTraded_S[stepIndex] = true;
                // Removed Print to prevent IO lag on Entry
            }
        }
    }
};

//+------------------------------------------------------------------+
//| Global Instances                                                 |
//+------------------------------------------------------------------+
CPivotStrategy section1;
CPivotStrategy section2;
CPivotStrategy section3;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    if (!MQLInfoInteger(MQL_TESTER)) {
        Alert(
            "⛔ 경고: 이 EA는 전략 테스터(백테스팅)에서만 실행할 수 있습니다.");
        Print("⛔ Error: This EA is restricted to the Strategy Tester only.");
        return (INIT_FAILED);  // 초기화 실패로 처리하여 실행 중단
    }

    // Section 1 Init
    section1.Init(
        Symbol_1, MagicNumber_1, PivotMethod_1, SupportLineLots_1,
        ResistanceLineLots_1, HasBuyPosition_1, HasSellPosition_1, PercentR1_1,
        PercentR2_1, PercentR3_1, PercentR4_1, PercentR5_1, PercentS1_1,
        PercentS2_1, PercentS3_1, PercentS4_1, PercentS5_1, PositionR1_1,
        PositionR2_1, PositionR3_1, PositionR4_1, PositionR5_1, PositionS1_1,
        PositionS2_1, PositionS3_1, PositionS4_1, PositionS5_1, FirstEntryTP_1,
        FirstEntrySL_1, SecondEntryTP_1, SecondEntrySL_1, ThirdEntryTP_1,
        ThirdEntrySL_1, FourthEntryTP_1, FourthEntrySL_1, FifthEntryTP_1,
        FifthEntrySL_1, ResistanceLineColor_1, SupportLineColor_1,
        MinMarginLevel_1);

    // Section 2 Init
    section2.Init(
        Symbol_2, MagicNumber_2, PivotMethod_2, SupportLineLots_2,
        ResistanceLineLots_2, HasBuyPosition_2, HasSellPosition_2, PercentR1_2,
        PercentR2_2, PercentR3_2, PercentR4_2, PercentR5_2, PercentS1_2,
        PercentS2_2, PercentS3_2, PercentS4_2, PercentS5_2, PositionR1_2,
        PositionR2_2, PositionR3_2, PositionR4_2, PositionR5_2, PositionS1_2,
        PositionS2_2, PositionS3_2, PositionS4_2, PositionS5_2, FirstEntryTP_2,
        FirstEntrySL_2, SecondEntryTP_2, SecondEntrySL_2, ThirdEntryTP_2,
        ThirdEntrySL_2, FourthEntryTP_2, FourthEntrySL_2, FifthEntryTP_2,
        FifthEntrySL_2, ResistanceLineColor_2, SupportLineColor_2,
        MinMarginLevel_2);

    // Section 3 Init
    section3.Init(
        Symbol_3, MagicNumber_3, PivotMethod_3, SupportLineLots_3,
        ResistanceLineLots_3, HasBuyPosition_3, HasSellPosition_3, PercentR1_3,
        PercentR2_3, PercentR3_3, PercentR4_3, PercentR5_3, PercentS1_3,
        PercentS2_3, PercentS3_3, PercentS4_3, PercentS5_3, PositionR1_3,
        PositionR2_3, PositionR3_3, PositionR4_3, PositionR5_3, PositionS1_3,
        PositionS2_3, PositionS3_3, PositionS4_3, PositionS5_3, FirstEntryTP_3,
        FirstEntrySL_3, SecondEntryTP_3, SecondEntrySL_3, ThirdEntryTP_3,
        ThirdEntrySL_3, FourthEntryTP_3, FourthEntrySL_3, FifthEntryTP_3,
        FifthEntrySL_3, ResistanceLineColor_3, SupportLineColor_3,
        MinMarginLevel_3);

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    section1.OnTick();
    section2.OnTick();
    section3.OnTick();
}
//+------------------------------------------------------------------+