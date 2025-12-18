//+------------------------------------------------------------------+
//|                                     CrossSignal_Precise.mq5      |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots 4

#property indicator_type1 DRAW_ARROW
#property indicator_type2 DRAW_ARROW
#property indicator_type3 DRAW_ARROW
#property indicator_type4 DRAW_LINE

//--- 입력 파라미터
input group "--- SMA Settings (Arrows) ---" input int InpSMA_Fast = 5;
input int InpSMA_Slow = 14;
input ENUM_MA_METHOD InpSMA_Method = MODE_SMA;
input color InpColor_Up = clrLime;
input color InpColor_Down = clrRed;
input int InpArrow_Size = 1;
input int InpArrow_Dist = 10;  // 화살표 캔들 이격 거리
input int InpArrow_UpCode = 233;
input int InpArrow_DnCode = 234;

input group "--- EMA Settings (Circles & Line) ---" input int InpEMA_Fast = 7;
input int InpEMA_Slow = 24;
input ENUM_MA_METHOD InpEMA_Method = MODE_EMA;
input color InpColor_EMA24 = clrDeepSkyBlue;
input color InpColor_EMACross = clrYellow;
input int InpCircle_Size = 1;  // 점 크기 (1 추천)
input int InpCircle_Code = 159;

//--- 버퍼 및 핸들
double BufSMA_Up[], BufSMA_Down[], BufEMA_Cross[], BufEMA_SlowLine[];
int handleSMA_Fast, handleSMA_Slow, handleEMA_Fast, handleEMA_Slow;

int OnInit() {
    SetIndexBuffer(0, BufSMA_Up, INDICATOR_DATA);
    SetIndexBuffer(1, BufSMA_Down, INDICATOR_DATA);
    SetIndexBuffer(2, BufEMA_Cross, INDICATOR_DATA);
    SetIndexBuffer(3, BufEMA_SlowLine, INDICATOR_DATA);

    PlotIndexSetInteger(0, PLOT_ARROW, InpArrow_UpCode);
    PlotIndexSetInteger(1, PLOT_ARROW, InpArrow_DnCode);
    PlotIndexSetInteger(2, PLOT_ARROW, InpCircle_Code);

    PlotIndexSetInteger(0, PLOT_LINE_WIDTH, InpArrow_Size);
    PlotIndexSetInteger(1, PLOT_LINE_WIDTH, InpArrow_Size);
    PlotIndexSetInteger(2, PLOT_LINE_WIDTH, InpCircle_Size);

    PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpColor_Up);
    PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpColor_Down);
    PlotIndexSetInteger(2, PLOT_LINE_COLOR, InpColor_EMACross);
    PlotIndexSetInteger(3, PLOT_LINE_COLOR, InpColor_EMA24);

    handleSMA_Fast =
        iMA(_Symbol, _Period, InpSMA_Fast, 0, InpSMA_Method, PRICE_CLOSE);
    handleSMA_Slow =
        iMA(_Symbol, _Period, InpSMA_Slow, 0, InpSMA_Method, PRICE_CLOSE);
    handleEMA_Fast =
        iMA(_Symbol, _Period, InpEMA_Fast, 0, InpEMA_Method, PRICE_CLOSE);
    handleEMA_Slow =
        iMA(_Symbol, _Period, InpEMA_Slow, 0, InpEMA_Method, PRICE_CLOSE);

    return (INIT_SUCCEEDED);
}

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime& time[], const double& open[],
                const double& high[], const double& low[],
                const double& close[], const long& tick_volume[],
                const long& volume[], const int& spread[]) {
    int limit = rates_total - prev_calculated;
    if (limit > 1) limit = rates_total - 2;

    double fSMA[], sSMA[], fEMA[], sEMA[];
    if (CopyBuffer(handleSMA_Fast, 0, 0, rates_total, fSMA) <= 0) return 0;
    if (CopyBuffer(handleSMA_Slow, 0, 0, rates_total, sSMA) <= 0) return 0;
    if (CopyBuffer(handleEMA_Fast, 0, 0, rates_total, fEMA) <= 0) return 0;
    if (CopyBuffer(handleEMA_Slow, 0, 0, rates_total, sEMA) <= 0) return 0;

    double offset = InpArrow_Dist * _Point * 10;

    for (int i = (prev_calculated > 0 ? prev_calculated - 1 : 1);
         i < rates_total; i++) {
        BufSMA_Up[i] = EMPTY_VALUE;
        BufSMA_Down[i] = EMPTY_VALUE;
        BufEMA_Cross[i] = EMPTY_VALUE;
        BufEMA_SlowLine[i] = sEMA[i];  // 24선 표시

        // SMA Arrows
        if (fSMA[i - 1] <= sSMA[i - 1] && fSMA[i] > sSMA[i])
            BufSMA_Up[i] = low[i] - offset;
        else if (fSMA[i - 1] >= sSMA[i - 1] && fSMA[i] < sSMA[i])
            BufSMA_Down[i] = high[i] + offset;

        // EMA Cross (Circle) - 라인(sEMA)에 직접 붙임
        if ((fEMA[i - 1] <= sEMA[i - 1] && fEMA[i] > sEMA[i]) ||
            (fEMA[i - 1] >= sEMA[i - 1] && fEMA[i] < sEMA[i])) {
            BufEMA_Cross[i] = sEMA[i];
        }
    }
    return (rates_total);
}