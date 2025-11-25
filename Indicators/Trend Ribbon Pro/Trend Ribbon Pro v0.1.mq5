//+------------------------------------------------------------------+
//|                                                 Trend Ribbon Pro |
//|                                          Copyright 2025, p3pwp3p |
//+------------------------------------------------------------------+
#property copyright "p3pwp3p"
#property version "1.00"
#property indicator_chart_window

//--- 버퍼 설정
#property indicator_buffers 3
#property indicator_plots 1

//--- Plot 1: Cloud
#property indicator_label1 "SlopeCloud"
#property indicator_type1 DRAW_FILLING
#property indicator_color1 clrAqua, clrMagenta // 기본 색상
#property indicator_style1 STYLE_SOLID
#property indicator_width1 1

//--- User Inputs (PascalCase)
input group "MA Settings" input int InputFastPeriod = 20; // Fast MA (구름 모양용)
input int InputSlowPeriod = 50;                           // Slow MA (색상 결정용)
input ENUM_MA_METHOD InputMaMethod = MODE_EMA;
input ENUM_APPLIED_PRICE InputAppliedPrice = PRICE_CLOSE;

input group "Color Fix & Visuals"
    // [중요] 노란색으로 보이면 이 값을 true로, 정상이면 false로 바꾸세요.
    input bool InputForceColorSwap = true;
input int InputAlphaOpacity = 180;       // 투명도 (0~255)
input color InputUpColor = clrAqua;      // 상승 색상
input color InputDownColor = clrMagenta; // 하락 색상

//--- Global Variables
int fastMaHandle;
int slowMaHandle;
double fastMaBuffer[];
double slowMaBuffer[];
double plotColorBuffer[];

//+------------------------------------------------------------------+
//| Custom Indicator Initialization Function                         |
//+------------------------------------------------------------------+
int OnInit() {
    // 캔들을 지표 위로 올림 (필수)
    ChartSetInteger(0, CHART_FOREGROUND, true);

    SetIndexBuffer(0, fastMaBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, slowMaBuffer, INDICATOR_DATA);
    SetIndexBuffer(2, plotColorBuffer, INDICATOR_COLOR_INDEX);

    PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_FILLING);
    PlotIndexSetInteger(0, PLOT_COLOR_INDEXES, 2);
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);

    //--- 색상 강제 보정 로직 ---
    color finalUpColor, finalDownColor;

    if (InputForceColorSwap) {
        // 노란색 문제를 해결하기 위해 강제로 채널을 바꿉니다.
        finalUpColor = GetSwappedColor(InputUpColor, (uchar)InputAlphaOpacity);
        finalDownColor = GetSwappedColor(InputDownColor, (uchar)InputAlphaOpacity);
    } else {
        // 일반적인 경우
        finalUpColor = ColorToARGB(InputUpColor, (uchar)InputAlphaOpacity);
        finalDownColor = ColorToARGB(InputDownColor, (uchar)InputAlphaOpacity);
    }

    PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, finalUpColor);
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, finalDownColor);

    //--- MA 핸들 생성
    fastMaHandle = iMA(_Symbol, _Period, InputFastPeriod, 0, InputMaMethod, InputAppliedPrice);
    slowMaHandle = iMA(_Symbol, _Period, InputSlowPeriod, 0, InputMaMethod, InputAppliedPrice);

    if (fastMaHandle == INVALID_HANDLE || slowMaHandle == INVALID_HANDLE)
        return (INIT_FAILED);

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom Indicator Iteration Function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[]) {
    if (rates_total < MathMax(InputFastPeriod, InputSlowPeriod))
        return (0);
    int limit = (prev_calculated == 0) ? 0 : prev_calculated - 1;

    if (CopyBuffer(fastMaHandle, 0, 0, rates_total, fastMaBuffer) <= 0)
        return (0);
    if (CopyBuffer(slowMaHandle, 0, 0, rates_total, slowMaBuffer) <= 0)
        return (0);

    for (int i = limit; i < rates_total; i++) {
        // [수정] 민감도를 1로 고정 (바로 직전 봉과 비교)
        // 교차를 기다리지 않고, 1틱이라도 꺾이면 바로 반응합니다.
        int compareIndex = i - 1;

        if (compareIndex < 0) {
            plotColorBuffer[i] = 0.0;
            continue;
        }

        double currentSlope = slowMaBuffer[i];
        double prevSlope = slowMaBuffer[compareIndex];

        // [상승] 현재 기울기가 이전보다 높음 -> 무조건 상승색
        if (currentSlope > prevSlope) {
            plotColorBuffer[i] = 0.0;
        }
        // [하락] 현재 기울기가 이전보다 낮음 -> 무조건 하락색
        else if (currentSlope < prevSlope) {
            plotColorBuffer[i] = 1.0;
        } else {
            // 변화 없음 -> 이전 상태 유지
            if (i > 0)
                plotColorBuffer[i] = plotColorBuffer[i - 1];
            else
                plotColorBuffer[i] = 0.0;
        }
    }
    return (rates_total);
}

//+------------------------------------------------------------------+
//| 헬퍼 함수: 색상 채널 강제 교환 (노란색 오류 해결용)              |
//+------------------------------------------------------------------+
color GetSwappedColor(color baseColor, uchar alpha) {
    // 입력된 색상의 R, G, B 추출
    int r = (baseColor >> 0) & 0xFF;
    int g = (baseColor >> 8) & 0xFF;
    int b = (baseColor >> 16) & 0xFF;

    // [핵심] R과 B의 위치를 서로 바꿔서 조립합니다.
    // 컴퓨터가 잘못 읽어서(Swap) 다시 제자리를 찾도록 유도하는 방식입니다.
    // 포맷: Alpha | Blue | Green | Red
    uint colorInt = ((uint)alpha << 24) | ((uint)r << 16) | ((uint)g << 8) | (uint)b;

    return (color)colorInt;
}