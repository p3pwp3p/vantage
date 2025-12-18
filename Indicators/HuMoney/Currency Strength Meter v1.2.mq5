//+------------------------------------------------------------------+
//|                                   CSM_Premium_Smooth.mq5         |
//|                                  Copyright 2025, p3pwp3p         |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, p3pwp3p"
#property link "https://www.mql5.com"
#property version "1.2"
#property strict
#property indicator_separate_window
#property indicator_buffers 8
#property indicator_plots 8

//--- 선 스타일 (두께 1, 매우 부드러운 설정)
#property indicator_type1 DRAW_LINE
#property indicator_width1 1
#property indicator_type2 DRAW_LINE
#property indicator_width2 1
#property indicator_type3 DRAW_LINE
#property indicator_width3 1
#property indicator_type4 DRAW_LINE
#property indicator_width4 1
#property indicator_type5 DRAW_LINE
#property indicator_width5 1
#property indicator_type6 DRAW_LINE
#property indicator_width6 1
#property indicator_type7 DRAW_LINE
#property indicator_width7 1
#property indicator_type8 DRAW_LINE
#property indicator_width8 1

//--- 통화별 고정 색상 (사진과 유사하게 매칭)
#property indicator_color1 clrDeepSkyBlue  // AUD
#property indicator_color2 clrDarkOrchid   // CAD
#property indicator_color3 clrLimeGreen    // EUR
#property indicator_color4 clrOrange       // GBP
#property indicator_color5 clrChocolate    // CHF
#property indicator_color6 clrWhite        // USD
#property indicator_color7 clrYellow       // NZD
#property indicator_color8 clrRed          // JPY

input group "--- Calculation Settings ---";
input int InpPeriod = 12;         // 분석 기간 (사진 설정값: 12)
input int InpHistoryBars = 1000;  // 계산할 과거 막대 수
input int InpSmoothLevel = 10;    // 평활화 강도 (사진 같은 곡선용)

input group "--- UI & Label Settings ---";
input bool InpShowLabels = true;  // 라벨 표시 여부
input int InpFontSize = 10;       // 라벨 크기
input int InpXOffset = 15;        // 라벨 우측 여백

input group "--- Symbol Settings ---";
input string InpUsePairs = "AUD,CAD,EUR,GBP,CHF,USD,NZD,JPY";  // 순서 조정
input string InpPairPrefix = "";

//--- 전역 변수
double Buf1[], Buf2[], Buf3[], Buf4[], Buf5[], Buf6[], Buf7[], Buf8[];
string GSymbols[8];

//+------------------------------------------------------------------+
int OnInit() {
    ushort sep = StringGetCharacter(",", 0);
    StringSplit(InpUsePairs, sep, GSymbols);

    SetIndexBuffer(0, Buf1, INDICATOR_DATA);
    SetIndexBuffer(1, Buf2, INDICATOR_DATA);
    SetIndexBuffer(2, Buf3, INDICATOR_DATA);
    SetIndexBuffer(3, Buf4, INDICATOR_DATA);
    SetIndexBuffer(4, Buf5, INDICATOR_DATA);
    SetIndexBuffer(5, Buf6, INDICATOR_DATA);
    SetIndexBuffer(6, Buf7, INDICATOR_DATA);
    SetIndexBuffer(7, Buf8, INDICATOR_DATA);

    for (int i = 0; i < 8; i++) {
        PlotIndexSetString(i, PLOT_LABEL, GSymbols[i]);
        PlotIndexSetInteger(i, PLOT_LINE_WIDTH, 1);
    }

    IndicatorSetString(INDICATOR_SHORTNAME, "Premium CSM (Smooth)");
    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime& time[], const double& open[],
                const double& high[], const double& low[],
                const double& close[], const long& tick_volume[],
                const long& volume[], const int& spread[]) {
    int limit = rates_total - prev_calculated;
    if (limit > InpHistoryBars) limit = InpHistoryBars;
    if (rates_total < InpPeriod + InpSmoothLevel * 3) return 0;

    // 1. 강도 계산 (Raw Data)
    for (int i = limit; i >= 0; i--) {
        int barIdx = rates_total - 1 - i;
        if (barIdx < InpPeriod) continue;

        for (int s = 0; s < 8; s++) {
            double totalRoc = 0;
            int count = 0;
            for (int k = 0; k < 8; k++) {
                if (s == k) continue;
                string symbol = GSymbols[s] + GSymbols[k] + InpPairPrefix;
                bool inverted = false;
                if (!SymbolExist(symbol)) {
                    symbol = GSymbols[k] + GSymbols[s] + InpPairPrefix;
                    inverted = true;
                }

                if (SymbolExist(symbol)) {
                    double cNow = iClose(symbol, _Period, i);
                    double cOld = iClose(symbol, _Period, i + InpPeriod);
                    if (cNow > 0 && cOld > 0) {
                        double roc = (cNow - cOld) / cOld;
                        totalRoc += (inverted) ? -roc : roc;
                        count++;
                    }
                }
            }
            double val = (count > 0) ? (totalRoc / count) * 100 : 0;
            SetBufVal(s, barIdx, val);
        }
    }

    // 2. 가중 지수 평활화 (사진 같은 부드러운 곡선 구현)
    ApplyPremiumSmooth(Buf1, rates_total, limit);
    ApplyPremiumSmooth(Buf2, rates_total, limit);
    ApplyPremiumSmooth(Buf3, rates_total, limit);
    ApplyPremiumSmooth(Buf4, rates_total, limit);
    ApplyPremiumSmooth(Buf5, rates_total, limit);
    ApplyPremiumSmooth(Buf6, rates_total, limit);
    ApplyPremiumSmooth(Buf7, rates_total, limit);
    ApplyPremiumSmooth(Buf8, rates_total, limit);

    // 3. 사진과 같은 정밀 라벨 배치
    if (InpShowLabels) DrawPremiumLabels(rates_total);

    return (rates_total);
}

//--- 가중치를 활용한 프리미엄 평활화 알고리즘
void ApplyPremiumSmooth(double& buffer[], int total, int limit) {
    for (int step = 0; step < 2; step++)  // 2단계 반복으로 삐죽함을 완전히 제거
    {
        for (int i = limit; i >= 0; i--) {
            int idx = total - 1 - i;
            double sum = 0;
            double weightSum = 0;
            for (int k = 0; k < InpSmoothLevel; k++) {
                if (idx - k >= 0) {
                    double w = MathPow(
                        InpSmoothLevel - k,
                        2);  // 제곱 가중치로 현재가 반응성 유지하며 부드럽게
                    sum += buffer[idx - k] * w;
                    weightSum += w;
                }
            }
            if (weightSum > 0) buffer[idx] = sum / weightSum;
        }
    }
}

//--- 사진(image_ca7062.png) 스타일의 라벨 구현
void DrawPremiumLabels(int total) {
    int win = ChartWindowFind();
    double lastValues[8] = {Buf1[total - 1], Buf2[total - 1], Buf3[total - 1],
                            Buf4[total - 1], Buf5[total - 1], Buf6[total - 1],
                            Buf7[total - 1], Buf8[total - 1]};

    for (int i = 0; i < 8; i++) {
        string name = "CSM_Premium_" + (string)i;
        if (ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TEXT, win, 0, 0);

        // 캔들 끝 지점에서 약간 오른쪽으로 띄움
        ObjectMove(0, name, 0, iTime(_Symbol, _Period, 0), lastValues[i]);

        // 이름과 현재 수치를 소수점 2자리까지 표시 (사진 스타일)
        string labelText =
            GSymbols[i] + "  " + DoubleToString(lastValues[i], 2);
        ObjectSetString(0, name, OBJPROP_TEXT, "   " + labelText);

        ObjectSetInteger(0, name, OBJPROP_COLOR,
                         (color)PlotIndexGetInteger(i, PLOT_LINE_COLOR));
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
        ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
        ObjectSetString(0, name, OBJPROP_FONT,
                        "Segoe UI Semibold");  // 깔끔한 폰트
    }
    ChartRedraw();
}

void SetBufVal(int s, int idx, double v) {
    if (s == 0)
        Buf1[idx] = v;
    else if (s == 1)
        Buf2[idx] = v;
    else if (s == 2)
        Buf3[idx] = v;
    else if (s == 3)
        Buf4[idx] = v;
    else if (s == 4)
        Buf5[idx] = v;
    else if (s == 5)
        Buf6[idx] = v;
    else if (s == 6)
        Buf7[idx] = v;
    else if (s == 7)
        Buf8[idx] = v;
}

bool SymbolExist(string sym) { return SymbolInfoInteger(sym, SYMBOL_EXIST); }