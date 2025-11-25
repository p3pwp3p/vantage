//+------------------------------------------------------------------+
//|                                                 p3pwp3p VWAP.mq5 |
//|                                     Generated for User Request   |
//+------------------------------------------------------------------+
#property copyright "Gemini AI"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots 1

//--- Plot Settings
#property indicator_label1 "VWAP"
#property indicator_type1 DRAW_LINE
#property indicator_color1 clrMagenta  // Default
#property indicator_style1 STYLE_SOLID
#property indicator_width1 2

//--- Input Parameters
input color VwapColor = clrMagenta;  // VWAP 색상 설정

//--- Indicator Buffers
double vwapBuffer[];

//--- Global Variables
double sumPV = 0;
double sumVol = 0;
int lastDay = -1;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit() {
    SetIndexBuffer(0, vwapBuffer, INDICATOR_DATA);
    PlotIndexSetInteger(0, PLOT_LINE_COLOR,
                        VwapColor);  // Input 값으로 색상 변경

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime& time[], const double& open[],
                const double& high[], const double& low[],
                const double& close[], const long& tick_volume[],
                const long& volume[], const int& spread[]) {
    int start = 0;

    // 이미 계산된 바가 있으면 그 다음부터 계산 (효율성)
    if (prev_calculated > 0) start = prev_calculated - 1;

    for (int i = start; i < rates_total; i++) {
        MqlDateTime dt;
        TimeToStruct(time[i], dt);

        // 날짜가 바뀌면 누적 데이터 초기화
        if (lastDay != dt.day_of_year) {
            sumPV = 0;
            sumVol = 0;
            lastDay = dt.day_of_year;
        }

        // Typical Price 계산 (고+저+종 / 3)
        double typicalPrice = (high[i] + low[i] + close[i]) / 3.0;
        double vol = (double)tick_volume[i];  // Forex는 tick volume 사용

        if (vol > 0) {
            sumPV += typicalPrice * vol;
            sumVol += vol;
            vwapBuffer[i] = sumPV / sumVol;
        } else {
            // 거래량이 0이거나 데이터 부족 시 전값 유지 혹은 시가
            vwapBuffer[i] = (i > 0) ? vwapBuffer[i - 1] : typicalPrice;
        }
    }

    return (rates_total);
}