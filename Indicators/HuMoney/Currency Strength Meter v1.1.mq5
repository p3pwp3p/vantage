//+------------------------------------------------------------------+
//|                                   CSM_Smooth_Final.mq5           |
//|                                  Copyright 2025, p3pwp3p         |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, p3pwp3p"
#property link "https://www.mql5.com"
#property version "1.02"
#property strict
#property indicator_separate_window
#property indicator_buffers 8
#property indicator_plots 8

//--- 라인 스타일 설정 (Width 1로 얇게 설정)
#property indicator_type1 DRAW_LINE
#property indicator_color1 clrDodgerBlue
#property indicator_type2 DRAW_LINE
#property indicator_color2 clrRed
#property indicator_type3 DRAW_LINE
#property indicator_color3 clrLime
#property indicator_type4 DRAW_LINE
#property indicator_color4 clrGold
#property indicator_type5 DRAW_LINE
#property indicator_color5 clrDarkOrange
#property indicator_type6 DRAW_LINE
#property indicator_color6 clrWhite
#property indicator_type7 DRAW_LINE
#property indicator_color7 clrMagenta
#property indicator_type8 DRAW_LINE
#property indicator_color8 clrAqua

input group "--- Calculation Settings ---";
input int InpPeriod = 14;         // 분석 기간
input int InpHistoryBars = 1000;  // 계산할 과거 막대 수
input int InpSmooth = 8;          // 평활화 강도 (8 이상 추천, 부드러운 라인용)

input group "--- UI & Label Settings ---";
input bool InpShowLabels = true;  // 라벨 표시 여부
input int InpFontSize = 9;        // 라벨 크기

input group "--- Symbol Settings ---";
input string InpUsePairs = "EUR,USD,GBP,JPY,AUD,CAD,CHF,NZD";  // 분석 대상
input string InpPairPrefix = "";                               // 접두사

//--- 버퍼 및 전역 변수
double Buf1[], Buf2[], Buf3[], Buf4[], Buf5[], Buf6[], Buf7[], Buf8[];
string GSymbols[8];

//+------------------------------------------------------------------+
int OnInit() {
    // 오타 수정: InUsePairs -> InpUsePairs
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
        PlotIndexSetInteger(i, PLOT_LINE_WIDTH,
                            1);  // 선 두께를 1로 고정 (얇게)
    }

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
    if (rates_total < InpPeriod + InpSmooth) return 0;

    // 1. 기초 강도 계산
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
            double strength = (count > 0) ? (totalRoc / count) * 100 : 0;

            // 버퍼 할당
            if (s == 0)
                Buf1[barIdx] = strength;
            else if (s == 1)
                Buf2[barIdx] = strength;
            else if (s == 2)
                Buf3[barIdx] = strength;
            else if (s == 3)
                Buf4[barIdx] = strength;
            else if (s == 4)
                Buf5[barIdx] = strength;
            else if (s == 5)
                Buf6[barIdx] = strength;
            else if (s == 6)
                Buf7[barIdx] = strength;
            else if (s == 7)
                Buf8[barIdx] = strength;
        }
    }

    // 2. 평활화 (부드럽게 보정)
    if (InpSmooth > 1) {
        ApplySmooth(Buf1, rates_total, limit);
        ApplySmooth(Buf2, rates_total, limit);
        ApplySmooth(Buf3, rates_total, limit);
        ApplySmooth(Buf4, rates_total, limit);
        ApplySmooth(Buf5, rates_total, limit);
        ApplySmooth(Buf6, rates_total, limit);
        ApplySmooth(Buf7, rates_total, limit);
        ApplySmooth(Buf8, rates_total, limit);
    }

    // 3. 동적 라벨 표시 (라인 끝 지점)
    if (InpShowLabels) DrawDynamicLabels(rates_total);

    return (rates_total);
}

//--- 부드러운 라인 처리를 위한 함수
void ApplySmooth(double& buffer[], int total, int limit) {
    for (int i = limit; i >= 0; i--) {
        int idx = total - 1 - i;
        double sum = 0;
        int count = 0;
        for (int k = 0; k < InpSmooth; k++) {
            if (idx - k >= 0) {
                sum += buffer[idx - k];
                count++;
            }
        }
        if (count > 0) buffer[idx] = sum / count;
    }
}

//--- 라인 끝 지점에 통화 이름 표시
void DrawDynamicLabels(int total) {
    int win = ChartWindowFind();
    // 마지막 인덱스 값 추출
    double lasts[8] = {Buf1[total - 1], Buf2[total - 1], Buf3[total - 1],
                       Buf4[total - 1], Buf5[total - 1], Buf6[total - 1],
                       Buf7[total - 1], Buf8[total - 1]};

    for (int i = 0; i < 8; i++) {
        string name = "CSM_Lab_" + (string)i;
        if (ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TEXT, win, 0, 0);

        // 마지막 캔들 시간과 해당 라인의 값 위치로 이동
        ObjectMove(0, name, 0, iTime(_Symbol, _Period, 0), lasts[i]);
        ObjectSetString(0, name, OBJPROP_TEXT,
                        "  " + GSymbols[i]);  // 살짝 띄워서 표시
        ObjectSetInteger(0, name, OBJPROP_COLOR,
                         (color)PlotIndexGetInteger(i, PLOT_LINE_COLOR));
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
        ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
        ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
    }
    ChartRedraw();
}

bool SymbolExist(string sym) { return SymbolInfoInteger(sym, SYMBOL_EXIST); }