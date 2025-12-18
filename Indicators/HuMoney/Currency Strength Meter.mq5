//+------------------------------------------------------------------+
//|                                   AdvancedCurrencyStrength.mq5   |
//+------------------------------------------------------------------+
#property indicator_separate_window
#property indicator_buffers 8
#property indicator_plots 8

//--- 스타일 설정
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

//--- 주요 설정
input group "--- Calculation Settings ---" input int iPeriod =
    14;                         // 분석 기간 (iPeriod)
input int HistoryBars = 1000;   // 계산할 과거 막대 수
input int SmoothingPeriod = 3;  // 평활화 기간 (1: 비활성)

input group "--- UI & Label Settings ---" input bool ShowPairLabels =
    true;                       // 통화 라벨 표시
input int LabelsFontSize = 10;  // 라벨 글꼴 크기

input group "--- Symbol Settings ---" input string UsePairs =
    "EUR,USD,GBP,JPY,AUD,CAD,CHF,NZD";
input string PairPrefix = "";

//--- 버퍼 선언
double Buf1[], Buf2[], Buf3[], Buf4[], Buf5[], Buf6[], Buf7[], Buf8[];
string g_symbols[8];

//+------------------------------------------------------------------+
int OnInit() {
    ushort sep = StringGetCharacter(",", 0);
    StringSplit(UsePairs, sep, g_symbols);

    // 지표 버퍼 매핑 (오류 수정: 개별 직접 매핑)
    SetIndexBuffer(0, Buf1, INDICATOR_DATA);
    SetIndexBuffer(1, Buf2, INDICATOR_DATA);
    SetIndexBuffer(2, Buf3, INDICATOR_DATA);
    SetIndexBuffer(3, Buf4, INDICATOR_DATA);
    SetIndexBuffer(4, Buf5, INDICATOR_DATA);
    SetIndexBuffer(5, Buf6, INDICATOR_DATA);
    SetIndexBuffer(6, Buf7, INDICATOR_DATA);
    SetIndexBuffer(7, Buf8, INDICATOR_DATA);

    for (int i = 0; i < 8; i++) {
        PlotIndexSetString(i, PLOT_LABEL, g_symbols[i]);
        PlotIndexSetInteger(i, PLOT_LINE_WIDTH, 2);
    }

    IndicatorSetString(INDICATOR_SHORTNAME, "CSM (" + (string)iPeriod + ")");
    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime& time[], const double& open[],
                const double& high[], const double& low[],
                const double& close[], const long& tick_volume[],
                const long& volume[], const int& spread[]) {
    int limit = rates_total - prev_calculated;
    if (limit > HistoryBars) limit = HistoryBars;
    if (rates_total < iPeriod + SmoothingPeriod) return 0;

    //--- 1. 기초 강도 계산
    for (int i = limit; i >= 0; i--) {
        int bar_idx = rates_total - 1 - i;
        if (bar_idx < iPeriod) continue;

        for (int s = 0; s < 8; s++) {
            double total_roc = 0;
            int count = 0;

            for (int k = 0; k < 8; k++) {
                if (s == k) continue;

                string symbol = g_symbols[s] + g_symbols[k] + PairPrefix;
                bool inverted = false;

                if (!SymbolExist(symbol)) {
                    symbol = g_symbols[k] + g_symbols[s] + PairPrefix;
                    inverted = true;
                }

                if (SymbolExist(symbol)) {
                    double c_now = iClose(symbol, _Period, i);
                    double c_old = iClose(symbol, _Period, i + iPeriod);

                    if (c_now > 0 && c_old > 0) {
                        double roc = (c_now - c_old) / c_old;
                        total_roc += (inverted) ? -roc : roc;
                        count++;
                    }
                }
            }

            double strength = (count > 0) ? (total_roc / count) * 100 : 0;

            // 버퍼에 할당 (오류 수정: switch 문으로 안전하게 처리)
            switch (s) {
                case 0:
                    Buf1[bar_idx] = strength;
                    break;
                case 1:
                    Buf2[bar_idx] = strength;
                    break;
                case 2:
                    Buf3[bar_idx] = strength;
                    break;
                case 3:
                    Buf4[bar_idx] = strength;
                    break;
                case 4:
                    Buf5[bar_idx] = strength;
                    break;
                case 5:
                    Buf6[bar_idx] = strength;
                    break;
                case 6:
                    Buf7[bar_idx] = strength;
                    break;
                case 7:
                    Buf8[bar_idx] = strength;
                    break;
            }
        }
    }

    //--- 2. 평활화(Smoothing) 적용
    if (SmoothingPeriod > 1) {
        ApplySmoothing(Buf1, rates_total, limit);
        ApplySmoothing(Buf2, rates_total, limit);
        ApplySmoothing(Buf3, rates_total, limit);
        ApplySmoothing(Buf4, rates_total, limit);
        ApplySmoothing(Buf5, rates_total, limit);
        ApplySmoothing(Buf6, rates_total, limit);
        ApplySmoothing(Buf7, rates_total, limit);
        ApplySmoothing(Buf8, rates_total, limit);
    }

    if (ShowPairLabels && prev_calculated == 0) DrawLabels();

    return (rates_total);
}

//--- 심볼 존재 확인
bool SymbolExist(string sym) { return SymbolInfoInteger(sym, SYMBOL_EXIST); }

//--- 평활화 함수 (오류 수정: 배열 참조 전달)
void ApplySmoothing(double& buffer[], int total, int limit) {
    for (int i = limit; i >= 0; i--) {
        int idx = total - 1 - i;
        double sum = 0;
        int count = 0;
        for (int k = 0; k < SmoothingPeriod; k++) {
            if (idx - k >= 0) {
                sum += buffer[idx - k];
                count++;
            }
        }
        if (count > 0) buffer[idx] = sum / count;
    }
}

void DrawLabels() {
    int win = ChartWindowFind();
    int total = iBars(_Symbol, _Period);
    if (total <= 0) return;

    // 각 버퍼의 마지막 유효 값을 가져오기 위한 배열
    double last_values[8];
    last_values[0] = Buf1[total - 1];
    last_values[1] = Buf2[total - 1];
    last_values[2] = Buf3[total - 1];
    last_values[3] = Buf4[total - 1];
    last_values[4] = Buf5[total - 1];
    last_values[5] = Buf6[total - 1];
    last_values[6] = Buf7[total - 1];
    last_values[7] = Buf8[total - 1];

    for (int i = 0; i < 8; i++) {
        string name = "CSM_Dynamic_Label_" + (string)i;

        // 가격(값) 기반의 텍스트 객체 생성 (OBJ_TEXT 사용)
        if (ObjectFind(0, name) < 0) {
            ObjectCreate(0, name, OBJ_TEXT, win, 0, 0);
        }

        // 시간은 마지막 바의 시간, 가격은 해당 라인의 마지막 값으로 설정
        ObjectMove(0, name, 0, iTime(_Symbol, _Period, 0), last_values[i]);

        // 텍스트 설정
        ObjectSetString(0, name, OBJPROP_TEXT, "── " + g_symbols[i]);
        ObjectSetInteger(0, name, OBJPROP_COLOR,
                         (color)PlotIndexGetInteger(i, PLOT_LINE_COLOR));
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, LabelsFontSize);
        ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");

        // 앵커 설정: 라인의 오른쪽에 붙도록 좌측 정렬
        ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
    }

    ChartRedraw();
}