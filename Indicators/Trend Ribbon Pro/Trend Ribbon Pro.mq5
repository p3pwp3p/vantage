//+------------------------------------------------------------------+
//|                                      SlopeBasedColorCloud.mq5    |
//|                        Copyright 2025, p3pwp3p                   |
//+------------------------------------------------------------------+
#property copyright "p3pwp3p"
#property link "https://www.mql5.com"
#property version "1.00"
#property indicator_chart_window

#property indicator_buffers 4
#property indicator_plots 1

#property indicator_label1 "SlopeCloud"
#property indicator_type1 DRAW_COLOR_HISTOGRAM2
#property indicator_color1 clrAqua, clrMediumVioletRed
#property indicator_style1 STYLE_SOLID
#property indicator_width1 10

//--- Inputs (PascalCase)
input group "MA Settings" input int InputFastPeriod = 20; // Fast MA
input int InputSlowPeriod = 50;                           // Slow MA (색상 기준)
input int InputMaShift = 0;
input ENUM_MA_METHOD InputMaMethod = MODE_EMA;
input ENUM_APPLIED_PRICE InputAppliedPrice = PRICE_CLOSE;

input group "Color Logic" input int InputSensitivity = 3;

input group "Visual Settings" input int InputAlphaOpacity = 150;
input bool InputForceColorSwap = false;

//--- Global Variables
int fastMaHandle;
int slowMaHandle;
double fastBuffer[];
double slowBuffer[];
double colorBuffer[];
double dummyBuffer[];

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit() {
    ChartSetInteger(0, CHART_FOREGROUND, true);

    SetIndexBuffer(0, fastBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, slowBuffer, INDICATOR_DATA);
    SetIndexBuffer(2, colorBuffer, INDICATOR_COLOR_INDEX);
    SetIndexBuffer(3, dummyBuffer, INDICATOR_CALCULATIONS);

    PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_COLOR_HISTOGRAM2);
    PlotIndexSetInteger(0, PLOT_COLOR_INDEXES, 2);

    // 색상/투명도 설정
    color c1 = clrLime;
    color c2 = clrBlue;

    if (InputForceColorSwap) {
        c1 = (color)GetSwappedColor(c1, (uchar)InputAlphaOpacity);
        c2 = (color)GetSwappedColor(c2, (uchar)InputAlphaOpacity);
    } else {
        c1 = ColorToARGB(c1, (uchar)InputAlphaOpacity);
        c2 = ColorToARGB(c2, (uchar)InputAlphaOpacity);
    }

    PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, c1);
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, c2);

    fastMaHandle = iMA(_Symbol, _Period, InputFastPeriod, InputMaShift, InputMaMethod, InputAppliedPrice);
    slowMaHandle = iMA(_Symbol, _Period, InputSlowPeriod, InputMaShift, InputMaMethod, InputAppliedPrice);

    if (fastMaHandle == INVALID_HANDLE || slowMaHandle == INVALID_HANDLE)
        return (INIT_FAILED);

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[]) {
    if (rates_total < MathMax(InputFastPeriod, InputSlowPeriod))
        return (0);
    int limit = (prev_calculated == 0) ? 0 : prev_calculated - 1;

    if (CopyBuffer(fastMaHandle, 0, 0, rates_total, fastBuffer) <= 0)
        return (0);
    if (CopyBuffer(slowMaHandle, 0, 0, rates_total, slowBuffer) <= 0)
        return (0);

    for (int i = limit; i < rates_total; i++) {
        int compareIndex = i - InputSensitivity;

        if (compareIndex < 0) {
            colorBuffer[i] = 0.0;
            continue;
        }

        double currentVal = slowBuffer[i];
        double oldVal = slowBuffer[compareIndex];

        // [Slope Logic]
        // 교차 무시, 오직 기울기만 봄

        if (currentVal > oldVal)
            colorBuffer[i] = 0.0; // 상승 (Lime)
        else if (currentVal < oldVal)
            colorBuffer[i] = 1.0; // 하락 (Blue)
        else if (i > 0)
            colorBuffer[i] = colorBuffer[i - 1];
        else
            colorBuffer[i] = 0.0;
    }

    return (rates_total);
}

//+------------------------------------------------------------------+
//| Helper                                                           |
//+------------------------------------------------------------------+
uint GetSwappedColor(color baseColor, uchar alpha) {
    int r = (baseColor >> 0) & 0xFF;
    int g = (baseColor >> 8) & 0xFF;
    int b = (baseColor >> 16) & 0xFF;
    return ((uint)alpha << 24) | ((uint)r << 16) | ((uint)g << 8) | (uint)b;
}