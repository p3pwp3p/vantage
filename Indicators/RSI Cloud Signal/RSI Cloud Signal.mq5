//+------------------------------------------------------------------+
//|                               Rsi50LevelCloud_Transparent.mq5    |
//|                                  Copyright 2024, Gemini Assistant|
//+------------------------------------------------------------------+
#property copyright "Gemini Assistant"
#property link ""
#property version "1.02"
#property indicator_separate_window
#property indicator_buffers 5
#property indicator_plots 2

//--- Plot 1: Cloud Filling (Background)
#property indicator_label1 "Smoothed RSI Cloud"
#property indicator_type1 DRAW_FILLING
// #property indicator_color1 ... (코드에서 동적으로 투명도 적용하므로 여기서
// 제외해도 됨)
#property indicator_width1 1

//--- Plot 2: RSI Color Line (Foreground)
#property indicator_label2 "Smoothed RSI Line"
#property indicator_type2 DRAW_COLOR_LINE
#property indicator_color2 clrLime, clrRed
#property indicator_style2 STYLE_SOLID
#property indicator_width2 2

//--- Input Parameters
input int RsiPeriod = 14;    // RSI Period
input int SmoothPeriod = 5;  // Smoothing Period (SMA)
input int Transparency =
    70;  // [추가] Cloud Transparency (0=Invisible, 255=Solid)
input int OverBought = 70;  // Overbought Level
input int OverSold = 30;    // Oversold Level

//--- Global Variables
double rsiFillBuffer[];
double baseFillBuffer[];
double rsiLineBuffer[];
double lineColorBuffer[];
double rsiRawBuffer[];

int rsiHandle;

//+------------------------------------------------------------------+
//| Custom Indicator Initialization Function                         |
//+------------------------------------------------------------------+
int OnInit() {
    //--- Indicator Buffers Mapping
    SetIndexBuffer(0, rsiFillBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, baseFillBuffer, INDICATOR_DATA);
    SetIndexBuffer(2, rsiLineBuffer, INDICATOR_DATA);
    SetIndexBuffer(3, lineColorBuffer, INDICATOR_COLOR_INDEX);
    SetIndexBuffer(4, rsiRawBuffer, INDICATOR_CALCULATIONS);

    //--- Set Levels
    IndicatorSetInteger(INDICATOR_DIGITS, 1);
    IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, OverSold);
    IndicatorSetDouble(INDICATOR_LEVELVALUE, 1, 50);
    IndicatorSetDouble(INDICATOR_LEVELVALUE, 2, OverBought);

    //--- [핵심] 투명도 적용 로직 ---------------------------------------
    // ColorToARGB(색상, 알파값) : 알파값은 0~255
    color upCloudColor =
        ColorToARGB(clrLime, (uchar)Transparency);  // 상승 구름 (초록 계열)
    color downCloudColor =
        ColorToARGB(clrRed, (uchar)Transparency);  // 하락 구름 (빨강 계열)

    // Plot 0번(DRAW_FILLING)의 색상을 코드로 강제 설정
    // Modifier 0: 첫 번째 색상, Modifier 1: 두 번째 색상
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, upCloudColor);
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, downCloudColor);
    //------------------------------------------------------------------

    //--- Create RSI Handle
    rsiHandle = iRSI(_Symbol, _Period, RsiPeriod, PRICE_CLOSE);
    if (rsiHandle == INVALID_HANDLE) {
        Print("Failed to create RSI handle");
        return (INIT_FAILED);
    }

    string shortName =
        "Transparent RSI Cloud (" + IntegerToString(Transparency) + ")";
    IndicatorSetString(INDICATOR_SHORTNAME, shortName);

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom Indicator Iteration Function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const int begin, const double& price[]) {
    if (rates_total < RsiPeriod + SmoothPeriod) return (0);

    int calculated = BarsCalculated(rsiHandle);
    if (calculated < rates_total) return (0);

    int limit;
    if (prev_calculated == 0)
        limit = rates_total - 1;
    else
        limit = rates_total - prev_calculated;

    int toCopy = (prev_calculated == 0) ? rates_total
                                        : (rates_total - prev_calculated) + 1;
    if (CopyBuffer(rsiHandle, 0, 0, toCopy, rsiRawBuffer) <= 0) return (0);

    int start =
        (prev_calculated > SmoothPeriod) ? prev_calculated - 1 : SmoothPeriod;

    for (int i = start; i < rates_total; i++) {
        double sum = 0;
        for (int k = 0; k < SmoothPeriod; k++) {
            sum += rsiRawBuffer[i - k];
        }
        double smoothedRsi = sum / SmoothPeriod;

        rsiLineBuffer[i] = smoothedRsi;
        rsiFillBuffer[i] = smoothedRsi;
        baseFillBuffer[i] = 50.0;

        if (rsiLineBuffer[i] >= 50.0)
            lineColorBuffer[i] = 0.0;
        else
            lineColorBuffer[i] = 1.0;
    }

    return (rates_total);
}
//+------------------------------------------------------------------+