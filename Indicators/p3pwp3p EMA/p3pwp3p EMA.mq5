//+------------------------------------------------------------------+
//|                                                  p3pwp3p EMA.mq5 |
//|                                     Generated for User Request   |
//+------------------------------------------------------------------+
#property copyright "Gemini AI"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

//--- Plot Settings
#property indicator_label1  "EMA"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrWhite // Default
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Input Parameters
input int    EmaPeriod = 8;          // EMA 기간
input color  EmaColor  = clrWhite;  // EMA 색상

//--- Indicator Buffers
double emaBuffer[];
int emaHandle; // 내장 iMA 핸들 사용

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, emaBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, EmaColor); // Input 값으로 색상 변경
   
   // 내장 iMA 지표 핸들 생성
   emaHandle = iMA(_Symbol, _Period, EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   
   if(emaHandle == INVALID_HANDLE)
   {
      Print("Failed to create internal iMA handle");
      return(INIT_FAILED);
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   // 내장 지표 값 복사
   if(CopyBuffer(emaHandle, 0, 0, rates_total, emaBuffer) <= 0)
      return(0);
      
   return(rates_total);
}