//+------------------------------------------------------------------+
//|                                               EMA Cross.mq5      |
//|                                     Copyright 2025, p3pwp3p      |
//+------------------------------------------------------------------+
#property copyright "p3pwp3p"
#property link ""
#property version "1.00"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots 3

//--- Plot 1: Fast EMA
#property indicator_label1 "Fast EMA"
#property indicator_type1 DRAW_LINE
#property indicator_color1 clrRed
#property indicator_style1 STYLE_SOLID
#property indicator_width1 2

//--- Plot 2: Slow EMA
#property indicator_label2 "Slow EMA"
#property indicator_type2 DRAW_LINE
#property indicator_color2 clrBlue
#property indicator_style2 STYLE_SOLID
#property indicator_width2 2

//--- Plot 3: Cross Circle
#property indicator_label3 "Cross Signal"
#property indicator_type3 DRAW_ARROW
#property indicator_color3 clrWhite
#property indicator_width3 3

//--- Input Parameters (PascalCase)
input int FastPeriod = 30;   // Fast EMA Period
input int SlowPeriod = 60;   // Slow EMA Period
int CircleCode = 108;  // Wingdings Code (159=Small Dot)

//--- Global Variables (camelCase)
double fastBuffer[];
double slowBuffer[];
double crossBuffer[];

int fastHandle;
int slowHandle;

//+------------------------------------------------------------------+
//| Custom Indicator Initialization Function                         |
//+------------------------------------------------------------------+
int OnInit() {
    //--- Indicator Buffers Mapping
    SetIndexBuffer(0, fastBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, slowBuffer, INDICATOR_DATA);
    SetIndexBuffer(2, crossBuffer, INDICATOR_DATA);

    //--- Plot Settings
    PlotIndexSetInteger(2, PLOT_ARROW, CircleCode);
    PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);

    //--- Create MA Handles
    fastHandle = iMA(_Symbol, _Period, FastPeriod, 0, MODE_EMA, PRICE_CLOSE);
    slowHandle = iMA(_Symbol, _Period, SlowPeriod, 0, MODE_EMA, PRICE_CLOSE);

    if (fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE) {
        Print("Error creating MA handles.");
        return (INIT_FAILED);
    }

    string shortName = "EMA Cross Snap (" + IntegerToString(FastPeriod) + "," +
                       IntegerToString(SlowPeriod) + ")";
    IndicatorSetString(INDICATOR_SHORTNAME, shortName);

    //--- Set Series (0 is latest)
    ArraySetAsSeries(fastBuffer, true);
    ArraySetAsSeries(slowBuffer, true);
    ArraySetAsSeries(crossBuffer, true);

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom Indicator Iteration Function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime& time[], const double& open[],
                const double& high[], const double& low[],
                const double& close[], const long& tick_volume[],
                const long& volume[], const int& spread[]) {
    if (rates_total < SlowPeriod) return (0);

    int limit;
    if (prev_calculated == 0)
        limit = rates_total - SlowPeriod - 1;
    else
        limit = rates_total - prev_calculated;

    //--- Copy MA Data
    int toCopy = (prev_calculated == 0) ? rates_total
                                        : (rates_total - prev_calculated) + 1;

    if (CopyBuffer(fastHandle, 0, 0, toCopy, fastBuffer) <= 0) return (0);
    if (CopyBuffer(slowHandle, 0, 0, toCopy, slowBuffer) <= 0) return (0);

    //--- Main Loop
    for (int i = limit; i >= 0; i--) {
        // Safety check
        if (i >= rates_total - SlowPeriod || i + 1 >= rates_total) continue;

        // Initialize current buffer to 0 (Empty) unless already set by previous
        // loop iteration We need to be careful not to overwrite if the logic
        // decided to draw on 'i' from the 'i-1' iteration. But since we loop
        // backwards (limit -> 0), calculating for pair (i, i+1) creates a
        // signal. We will clear crossBuffer[i] only if it wasn't set. Actually,
        // standard practice: clear current, calculate logic.
        if (prev_calculated == 0)
            crossBuffer[i] = 0.0;
        else if (i == 0)
            crossBuffer[0] = 0.0;  // Clear latest only on updates

        double currFast = fastBuffer[i];
        double currSlow = slowBuffer[i];
        double prevFast = fastBuffer[i + 1];
        double prevSlow = slowBuffer[i + 1];

        bool isGoldenCross = (prevFast < prevSlow) && (currFast >= currSlow);
        bool isDeadCross = (prevFast > prevSlow) && (currFast <= currSlow);

        if (isGoldenCross || isDeadCross) {
            // 1. Calculate Exact Intersection Price (Geometric)
            // Formula: y = y1 + (y2 - y1) * x_ratio

            double diffPrev = prevFast - prevSlow;  // Gap at i+1
            double diffCurr = currFast - currSlow;  // Gap at i

            // Calculate ratio 't' where intersection happens (0.0 means at
            // prev, 1.0 means at curr) Logic: diffPrev + t * (diffCurr -
            // diffPrev) = 0 t = -diffPrev / (diffCurr - diffPrev) = diffPrev /
            // (diffPrev - diffCurr)

            double t = 0.5;  // Default middle
            if (MathAbs(diffPrev - diffCurr) > 0.00000001) {
                t = diffPrev / (diffPrev - diffCurr);
            }

            // Calculate the Exact Price Height of the cross
            double crossPrice = prevFast + t * (currFast - prevFast);

            // 2. Decide where to draw (Snap to Closest)
            // If t < 0.5, the cross happened closer to the Previous candle
            // (i+1) If t >= 0.5, the cross happened closer to the Current
            // candle (i)

            if (t < 0.5) {
                // Closer to Previous (i+1)
                crossBuffer[i + 1] = crossPrice;
                // Clean current just in case
                crossBuffer[i] = 0.0;
            } else {
                // Closer to Current (i)
                crossBuffer[i] = crossPrice;
            }
        }
    }

    return (rates_total);
}
//+------------------------------------------------------------------+