//+------------------------------------------------------------------+
//|                                        FloorPivotGrid_Debug.mq5  |
//|                                  Copyright 2025, p3pwp3p         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, p3pwp3p"
#property version "1.04"  // 디버깅 버전
#property strict

#include <Arrays\ArrayString.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>

//--- Input Parameters
input group "Section1";
input int MagicNumber = 202403;
input double AccountMaxLots = 0.15;
input double SpreadLimitPoints = 40.0;
input bool EnableSoundAlerts = false;
input double MinMarginLevel = 400.0;
input string InfoDirection = "LEFT_DOWN";

input group "Section2";
input string TradeSymbol = "";
input bool EnableSell = true;
input bool EnableBuy = true;
input string SellLotSteps = "0.02,0.02,0.03,0.04,0.05,0.06";
input string BuyLotSteps = "0.02,0.02,0.03,0.04,0.05,0.06";
input double MinGridStepPoints = 400.0;
input int MaxEntries = 9;

input group "GapPoint";
input double R1GapAlphaPoints = 90.0;
input double R2GapAlphaPoints = 90.0;
input double R3GapAlphaPoints = 70.0;
input double R4GapAlphaPoints = 0.0;
input double S1GapAlphaPoints = -90.0;
input double S2GapAlphaPoints = -90.0;
input double S3GapAlphaPoints = -70.0;
input double S4GapAlphaPoints = 0.0;

enum ENUM_TRADE_DIR { DIR_NO_TRADE, DIR_BUY, DIR_SELL, DIR_BOTH };

input group "Order";
input ENUM_TRADE_DIR R1Direction = DIR_SELL;
input ENUM_TRADE_DIR R2Direction = DIR_SELL;
input ENUM_TRADE_DIR R3Direction = DIR_SELL;
input ENUM_TRADE_DIR R4Direction = DIR_SELL;
input ENUM_TRADE_DIR S1Direction = DIR_BUY;
input ENUM_TRADE_DIR S2Direction = DIR_BUY;
input ENUM_TRADE_DIR S3Direction = DIR_BUY;
input ENUM_TRADE_DIR S4Direction = DIR_BUY;

input group "Close";
input double FirstEntryProfitPoints = 200.0;
input double CloseTarget2 = 7.0;
input double CloseTarget3 = 12.0;
input double CloseTarget4 = 17.0;
input double CloseTarget5 = 23.0;
input double CloseTarget6 = 29.0;
input double CloseTarget7 = 35.0;
input double CloseTarget8 = 35.0;
input double CloseTarget9 = 35.0;
input double CloseTarget10 = 35.0;
input double CloseTarget11Plus = 35.0;

input group "Daily";
input double DailyMinRangeR4S4 = 4000.0;
input ENUM_TRADE_DIR DailyR1Direction = DIR_NO_TRADE;
input ENUM_TRADE_DIR DailyR2Direction = DIR_SELL;
input ENUM_TRADE_DIR DailyR3Direction = DIR_NO_TRADE;
input ENUM_TRADE_DIR DailyR4Direction = DIR_SELL;
input ENUM_TRADE_DIR DailyS1Direction = DIR_NO_TRADE;
input ENUM_TRADE_DIR DailyS2Direction = DIR_BUY;
input ENUM_TRADE_DIR DailyS3Direction = DIR_NO_TRADE;
input ENUM_TRADE_DIR DailyS4Direction = DIR_BUY;

input double SellNextDayGap = 400.0;
input double BuyNextDayGap = -400.0;

CTrade trade;
CPositionInfo posInfo;

struct PivotLevels {
    double p, r1, r2, r3, r4, s1, s2, s3, s4;
    double openPrice;
    double rangeR4S4;
    bool success;
};

double sellLots[];
double buyLots[];
double closeMoneyTarget[];
const string PREFIX = "FP_EA_";

void parseStringToArray(string str, double& dst[]) {
    string elements[];
    int total = StringSplit(str, ',', elements);
    ArrayResize(dst, total);
    for (int i = 0; i < total; i++) dst[i] = StringToDouble(elements[i]);
}

int OnInit() {
    trade.SetExpertMagicNumber(MagicNumber);
    parseStringToArray(SellLotSteps, sellLots);
    parseStringToArray(BuyLotSteps, buyLots);
    ArrayResize(closeMoneyTarget, 20);
    closeMoneyTarget[0] = 0;
    closeMoneyTarget[1] = 0;
    closeMoneyTarget[2] = CloseTarget2;
    closeMoneyTarget[3] = CloseTarget3;
    closeMoneyTarget[4] = CloseTarget4;
    closeMoneyTarget[5] = CloseTarget5;
    closeMoneyTarget[6] = CloseTarget6;
    closeMoneyTarget[7] = CloseTarget7;
    closeMoneyTarget[8] = CloseTarget8;
    closeMoneyTarget[9] = CloseTarget9;
    closeMoneyTarget[10] = CloseTarget10;
    for (int i = 11; i < 20; i++) closeMoneyTarget[i] = CloseTarget11Plus;

    EventSetTimer(1);

    Print("=== EA 시작: OnInit 성공 ===");  // [디버깅]
    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    EventKillTimer();
    ObjectsDeleteAll(0, PREFIX);
    ChartRedraw();
    Print("=== EA 종료: OnDeinit ===");  // [디버깅]
}

void OnTick() { RunStrategy(); }

void OnTimer() { RunStrategy(); }

void RunStrategy() {
    string symbol =
        (TradeSymbol == "" || TradeSymbol == NULL) ? _Symbol : TradeSymbol;
    if (MQLInfoInteger(MQL_TESTER) && symbol != _Symbol) symbol = _Symbol;

    if (MinMarginLevel > 0 &&
        AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) < MinMarginLevel)
        return;

    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

    // [디버깅] 심볼 정보 확인
    if (point == 0) {
        Print("오류: Point 값이 0입니다. 심볼 데이터가 로딩되지 않았습니다.");
        return;
    }

    // 1. Pivot Calculation
    PivotLevels pivots = getPivotLevels(symbol, point);

    if (!pivots.success) {
        // [디버깅] 데이터 수신 실패 로그
        static int errorCount = 0;
        if (errorCount < 5) {  // 로그 폭주 방지 (5번만 출력)
            Print(
                "데이터 수신 실패: D1 데이터를 가져오지 못했습니다. (Error "
                "code: ",
                GetLastError(), ")");
            errorCount++;
        }
        createLabel("Info_Error", 50, 60, "데이터 수신 대기중 (" + symbol + ")",
                    clrRed, 10);
        return;
    } else {
        if (ObjectFind(0, PREFIX + "Info_Error") >= 0)
            ObjectDelete(0, PREFIX + "Info_Error");
    }

    // 2. Logic Mode
    bool isDailyMode = (pivots.rangeR4S4 >= DailyMinRangeR4S4);

    // 3. Graphics
    updateChartGraphics(pivots, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS),
                        point, isDailyMode);

    // 4. Manage Positions
    checkCloseLogic(symbol);

    // 5. Entry
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    if (ask > 0 && bid > 0) {
        checkEntry(symbol, pivots, isDailyMode, ask, bid, point);
    }
}

PivotLevels getPivotLevels(string symbol, double point) {
    PivotLevels pv;
    pv.success = false;

    double open[], high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open, true);

    // [중요] 에러 초기화
    ResetLastError();

    int copiedH = CopyHigh(symbol, PERIOD_D1, 1, 1, high);
    int copiedL = CopyLow(symbol, PERIOD_D1, 1, 1, low);
    int copiedC = CopyClose(symbol, PERIOD_D1, 1, 1, close);
    int copiedO = CopyOpen(symbol, PERIOD_D1, 0, 1, open);

    if (copiedH < 1 || copiedL < 1 || copiedC < 1 || copiedO < 1) {
        // 실패 시 아무것도 하지 않고 리턴
        return pv;
    }

    pv.openPrice = open[0];
    double H = high[0];
    double L = low[0];
    double C = close[0];

    pv.p = (H + L + C) / 3.0;
    pv.r1 = (2 * pv.p) - L;
    pv.s1 = (2 * pv.p) - H;
    pv.r2 = pv.p + (H - L);
    pv.s2 = pv.p - (H - L);
    pv.r3 = H + 2 * (pv.p - L);
    pv.s3 = L - 2 * (H - pv.p);
    pv.r4 = H + 3 * (pv.p - L);
    pv.s4 = L - 3 * (H - pv.p);

    pv.rangeR4S4 = (pv.r4 - pv.s4) / point;
    pv.success = true;
    return pv;
}

void updateChartGraphics(PivotLevels& pv, int digits, double point,
                         bool isDailyMode) {
    createHLine("R4", pv.r4, clrDodgerBlue, STYLE_SOLID, 1);
    createHLine("R3", pv.r3, clrDodgerBlue, STYLE_SOLID, 1);
    createHLine("R2", pv.r2, clrDodgerBlue, STYLE_SOLID, 1);
    createHLine("R1", pv.r1, clrDodgerBlue, STYLE_SOLID, 1);
    createHLine("Open", pv.openPrice, clrYellow, STYLE_SOLID, 2);
    createHLine("S1", pv.s1, clrRed, STYLE_SOLID, 1);
    createHLine("S2", pv.s2, clrRed, STYLE_SOLID, 1);
    createHLine("S3", pv.s3, clrRed, STYLE_SOLID, 1);
    createHLine("S4", pv.s4, clrRed, STYLE_SOLID, 1);

    datetime timePos = TimeCurrent();
    createLineLabel("Txt_R4", timePos, pv.r4,
                    "R4: " + DoubleToString(pv.r4, digits), R4GapAlphaPoints,
                    clrDodgerBlue);
    createLineLabel("Txt_R3", timePos, pv.r3,
                    "R3: " + DoubleToString(pv.r3, digits), R3GapAlphaPoints,
                    clrDodgerBlue);
    createLineLabel("Txt_R2", timePos, pv.r2,
                    "R2: " + DoubleToString(pv.r2, digits), R2GapAlphaPoints,
                    clrDodgerBlue);
    createLineLabel("Txt_R1", timePos, pv.r1,
                    "R1: " + DoubleToString(pv.r1, digits), R1GapAlphaPoints,
                    clrDodgerBlue);
    createLineLabel("Txt_OP", timePos, pv.openPrice,
                    "OP: " + DoubleToString(pv.openPrice, digits), 0, clrWhite,
                    true);
    createLineLabel("Txt_S1", timePos, pv.s1,
                    "S1: " + DoubleToString(pv.s1, digits), S1GapAlphaPoints,
                    clrRed);
    createLineLabel("Txt_S2", timePos, pv.s2,
                    "S2: " + DoubleToString(pv.s2, digits), S2GapAlphaPoints,
                    clrRed);
    createLineLabel("Txt_S3", timePos, pv.s3,
                    "S3: " + DoubleToString(pv.s3, digits), S3GapAlphaPoints,
                    clrRed);
    createLineLabel("Txt_S4", timePos, pv.s4,
                    "S4: " + DoubleToString(pv.s4, digits), S4GapAlphaPoints,
                    clrRed);

    color infoColor = isDailyMode ? clrRed : clrYellow;
    createLabel("Info_Range", 50, 20,
                "일봉편차 : " + DoubleToString(pv.rangeR4S4, 0), infoColor, 10);
    createLabel("Info_Set", 50, 40,
                "셋팅편차 : " + DoubleToString(DailyMinRangeR4S4, 0), clrYellow,
                10);
    ChartRedraw();
}

void createHLine(string suffix, double price, color col, ENUM_LINE_STYLE style,
                 int width) {
    string name = PREFIX + suffix;
    if (ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
    }
    ObjectSetDouble(0, name, OBJPROP_PRICE, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_STYLE, style);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
}

void createLineLabel(string suffix, datetime time, double price,
                     string baseText, double gap, color col,
                     bool noGap = false) {
    string name = PREFIX + suffix;
    string fullText = baseText;
    if (!noGap) {
        string gapStr =
            (gap >= 0) ? "+" + DoubleToString(gap, 0) : DoubleToString(gap, 0);
        fullText += " (" + gapStr + ")";
    }
    if (ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_TEXT, 0, time, price);
        ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
    }
    ObjectSetString(0, name, OBJPROP_TEXT, fullText);
    ObjectSetDouble(0, name, OBJPROP_PRICE, price);
    ObjectSetInteger(0, name, OBJPROP_TIME, time);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
}

void createLabel(string suffix, int x, int y, string text, color col,
                 int fontSize) {
    string name = PREFIX + suffix;
    if (ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    }
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
}

void checkEntry(string symbol, PivotLevels& pv, bool isDailyMode, double ask,
                double bid, double point) {
    int buyCount = countPositions(symbol, POSITION_TYPE_BUY);
    int sellCount = countPositions(symbol, POSITION_TYPE_SELL);
    if (buyCount >= MaxEntries && sellCount >= MaxEntries) return;

    processLevel(symbol, pv.r1, R1GapAlphaPoints, point,
                 isDailyMode ? DailyR1Direction : R1Direction, buyCount,
                 sellCount, ask, bid);
    processLevel(symbol, pv.r2, R2GapAlphaPoints, point,
                 isDailyMode ? DailyR2Direction : R2Direction, buyCount,
                 sellCount, ask, bid);
    processLevel(symbol, pv.r3, R3GapAlphaPoints, point,
                 isDailyMode ? DailyR3Direction : R3Direction, buyCount,
                 sellCount, ask, bid);
    processLevel(symbol, pv.r4, R4GapAlphaPoints, point,
                 isDailyMode ? DailyR4Direction : R4Direction, buyCount,
                 sellCount, ask, bid);
    processLevel(symbol, pv.s1, S1GapAlphaPoints, point,
                 isDailyMode ? DailyS1Direction : S1Direction, buyCount,
                 sellCount, ask, bid);
    processLevel(symbol, pv.s2, S2GapAlphaPoints, point,
                 isDailyMode ? DailyS2Direction : S2Direction, buyCount,
                 sellCount, ask, bid);
    processLevel(symbol, pv.s3, S3GapAlphaPoints, point,
                 isDailyMode ? DailyS3Direction : S3Direction, buyCount,
                 sellCount, ask, bid);
    processLevel(symbol, pv.s4, S4GapAlphaPoints, point,
                 isDailyMode ? DailyS4Direction : S4Direction, buyCount,
                 sellCount, ask, bid);
}

void processLevel(string symbol, double levelPrice, double alphaPoint,
                  double point, ENUM_TRADE_DIR dirConfig, int bCnt, int sCnt,
                  double ask, double bid) {
    if (dirConfig == DIR_NO_TRADE) return;
    double targetPrice = levelPrice + (alphaPoint * point);

    if (MathAbs(ask - targetPrice) < SpreadLimitPoints * point ||
        MathAbs(bid - targetPrice) < SpreadLimitPoints * point) {
        // 진입 시도 로직
        if ((dirConfig == DIR_BUY || dirConfig == DIR_BOTH) && EnableBuy &&
            bCnt < MaxEntries) {
            if (bCnt > 0 && !checkGridDistance(symbol, POSITION_TYPE_BUY, ask,
                                               MinGridStepPoints * point))
                return;
            if (!checkNextDayGap(symbol, POSITION_TYPE_BUY, ask, point)) return;
            double lot = getLotSize(bCnt, POSITION_TYPE_BUY);
            if (trade.Buy(lot, symbol)) {
                if (EnableSoundAlerts) PlaySound("ok.wav");
                Print("Buy 진입 성공: ", symbol, " @ ", ask);  // [디버깅]
            } else {
                Print("Buy 진입 실패: Error ", GetLastError());  // [디버깅]
            }
        }
        if ((dirConfig == DIR_SELL || dirConfig == DIR_BOTH) && EnableSell &&
            sCnt < MaxEntries) {
            if (sCnt > 0 && !checkGridDistance(symbol, POSITION_TYPE_SELL, bid,
                                               MinGridStepPoints * point))
                return;
            if (!checkNextDayGap(symbol, POSITION_TYPE_SELL, bid, point))
                return;
            double lot = getLotSize(sCnt, POSITION_TYPE_SELL);
            if (trade.Sell(lot, symbol)) {
                if (EnableSoundAlerts) PlaySound("ok.wav");
                Print("Sell 진입 성공: ", symbol, " @ ", bid);  // [디버깅]
            } else {
                Print("Sell 진입 실패: Error ", GetLastError());  // [디버깅]
            }
        }
    }
}

double getLotSize(int index, ENUM_POSITION_TYPE type) {
    if (type == POSITION_TYPE_BUY)
        return (index < ArraySize(buyLots)) ? buyLots[index]
                                            : buyLots[ArraySize(buyLots) - 1];
    else
        return (index < ArraySize(sellLots))
                   ? sellLots[index]
                   : sellLots[ArraySize(sellLots) - 1];
}

bool checkGridDistance(string symbol, ENUM_POSITION_TYPE type,
                       double currentPrice, double minDist) {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (posInfo.SelectByIndex(i)) {
            if (posInfo.Symbol() == symbol && posInfo.Magic() == MagicNumber &&
                posInfo.PositionType() == type) {
                if (MathAbs(currentPrice - posInfo.PriceOpen()) < minDist)
                    return false;
            }
        }
    }
    return true;
}

bool checkNextDayGap(string symbol, ENUM_POSITION_TYPE type,
                     double currentPrice, double point) {
    double lastEntryPrice = 0.0;
    datetime lastEntryTime = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (posInfo.SelectByIndex(i)) {
            if (posInfo.Symbol() == symbol && posInfo.Magic() == MagicNumber &&
                posInfo.PositionType() == type) {
                if (posInfo.Time() > lastEntryTime) {
                    lastEntryTime = posInfo.Time();
                    lastEntryPrice = posInfo.PriceOpen();
                }
            }
        }
    }
    if (lastEntryPrice == 0.0) return true;
    double diffPoints = (currentPrice - lastEntryPrice) / point;
    if (type == POSITION_TYPE_BUY && diffPoints < BuyNextDayGap) return false;
    if (type == POSITION_TYPE_SELL && diffPoints < SellNextDayGap) return false;
    return true;
}

void checkCloseLogic(string symbol) {
    double totalBuyProfit = 0, totalSellProfit = 0;
    int bCnt = 0, sCnt = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (posInfo.SelectByIndex(i)) {
            if (posInfo.Symbol() == symbol && posInfo.Magic() == MagicNumber) {
                if (posInfo.PositionType() == POSITION_TYPE_BUY) {
                    totalBuyProfit += posInfo.Profit() + posInfo.Swap() +
                                      posInfo.Commission();
                    bCnt++;
                } else {
                    totalSellProfit += posInfo.Profit() + posInfo.Swap() +
                                       posInfo.Commission();
                    sCnt++;
                }
            }
        }
    }
    if (bCnt > 0) {
        double target = (bCnt == 1) ? 999999 : closeMoneyTarget[bCnt];
        if (bCnt >= 2 && totalBuyProfit >= target)
            closeAllPositions(symbol, POSITION_TYPE_BUY);
    }
    if (sCnt > 0) {
        double target = (sCnt == 1) ? 999999 : closeMoneyTarget[sCnt];
        if (sCnt >= 2 && totalSellProfit >= target)
            closeAllPositions(symbol, POSITION_TYPE_SELL);
    }
}

void closeAllPositions(string symbol, ENUM_POSITION_TYPE type) {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (posInfo.SelectByIndex(i)) {
            if (posInfo.Symbol() == symbol && posInfo.Magic() == MagicNumber &&
                posInfo.PositionType() == type)
                trade.PositionClose(posInfo.Ticket());
        }
    }
    if (EnableSoundAlerts) PlaySound("expert.wav");
}
int countPositions(string symbol, ENUM_POSITION_TYPE type) {
    int cnt = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (posInfo.SelectByIndex(i)) {
            if (posInfo.Symbol() == symbol && posInfo.Magic() == MagicNumber &&
                posInfo.PositionType() == type)
                cnt++;
        }
    }
    return cnt;
}
//+------------------------------------------------------------------+