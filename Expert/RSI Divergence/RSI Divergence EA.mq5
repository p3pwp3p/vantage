//+------------------------------------------------------------------+
//|                                   Copyright 2024, Anonymous Ltd. |
//|                                        https://github.com/hayan2 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Anonymous Ltd."
#property link "https://github.com/hayan2"
#property version "1.00"

#include <Trade/SymbolInfo.mqh>
#include <Trade/Trade.mqh>

const string FILE_PATH = "Market\\RSI Divergence Indicator MT5";
// "..\\Experts\\hayann\\Indicators\\Project\\RSI Divergence Indicator MT5";
const double DIVERGENCE_SELL_SIGNAL = -1.0;
const double DIVERGENCE_BUY_SIGNAL = 1.0;

CTrade trade;
CSymbolInfo symbolInfo;
CPositionInfo positionInfo;
CHistoryOrderInfo historyOrderInfo;
CDealInfo dealInfo;

int handleRsiDiv = INVALID_HANDLE;
double tradeSignal[], rsi[];

int OnInit() {
    // TesterHideIndicators(true);

    handleRsiDiv = iCustom(_Symbol, _Period, FILE_PATH);

    if (handleRsiDiv == INVALID_HANDLE) {
        Print("Error loading indicators : ", GetLastError());
        return INIT_FAILED;
    }

    ArraySetAsSeries(tradeSignal, true);
	ArraySetAsSeries(rsi, true);

    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {}

void OnTick() {
    if (CopyBuffer(handleRsiDiv, 1, 0, 1, tradeSignal) < 1 ||
        CopyBuffer(handleRsiDiv, 0, 0, 3, rsi) < 3) {
        Print("Error copying indicators values : ", GetLastError());
        return;
    }

    int currentBar = iBars(_Symbol, _Period);
    static int previousBar = currentBar;
    if (currentBar == previousBar) return;
    previousBar = currentBar;
	
    double bid =
        NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
    double ask =
        NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
	
	bool hasOpenBuyPositions = false;
	bool hasOpenSellPositions = false;

	for (int i = 0; i < PositionsTotal(); i++) {
		if (positionInfo.SelectByIndex(i)) {
			if (positionInfo.PositionType() == POSITION_TYPE_BUY) {
				hasOpenBuyPositions = true;
			}
			else {
				hasOpenSellPositions = true;
			}
		}
	}

    if (tradeSignal[0] == DIVERGENCE_BUY_SIGNAL) {
        trade.Buy(0.05, _Symbol, bid, 0.0, bid + 3000 * _Point,
                  "");
    }
	if (tradeSignal[0] == DIVERGENCE_SELL_SIGNAL) {
        trade.Sell(0.05, _Symbol, ask, 0.0, ask - 3000 * _Point,
                   "");
    }
}