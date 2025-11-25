//+------------------------------------------------------------------+
//|                                       ColorVolumeIndicator.mq5 |
//|                                  Copyright 2025, Gemini & User   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Gemini & User"
#property link "https://github.com/hayan2"
#property version "1.4"
#property description "Tick volume colored by bar direction"

#property indicator_separate_window
#property indicator_plots 2
#property indicator_buffers 2

#property indicator_label1 "Buy Volume"
#property indicator_type1 DRAW_HISTOGRAM
#property indicator_color1 clrDodgerBlue
#property indicator_style1 STYLE_SOLID
#property indicator_width1 2

#property indicator_label2 "Sell Volume"
#property indicator_type2 DRAW_HISTOGRAM
#property indicator_color2 clrDeepPink
#property indicator_style2 STYLE_SOLID
#property indicator_width2 2

double BuyVolumeBuffer[];
double SellVolumeBuffer[];

int OnInit() {
    SetIndexBuffer(0, BuyVolumeBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, SellVolumeBuffer, INDICATOR_DATA);

    IndicatorSetString(INDICATOR_SHORTNAME, "Color Volume");

    return (INIT_SUCCEEDED);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[]) {
    int start = (prev_calculated > 0) ? prev_calculated - 1 : 0;

    for (int i = start; i < rates_total; i++) {
        BuyVolumeBuffer[i] = 0;
        SellVolumeBuffer[i] = 0;

        if (close[i] > open[i]) {
            BuyVolumeBuffer[i] = (double)tick_volume[i];
        } else if (close[i] < open[i]) {
            SellVolumeBuffer[i] = (double)tick_volume[i];
        } else {
            BuyVolumeBuffer[i] = (double)tick_volume[i];
        }
    }

    return (rates_total);
}
//+------------------------------------------------------------------+