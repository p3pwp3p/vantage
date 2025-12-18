#property copyright "Copyright 2025, p3pwp3p"
#property link "https://github.com/hayan2"
#property version "0.44"  // input variable to korean

const string GVersion = "0.44";

#include <Trade/PositionInfo.mqh>
#include <Trade/Trade.mqh>

enum ENUM_MARKET_REGIME {
    REGIME_RANGING,     // 1. 횡보/응축 (ADX < 17) -> Wall Bounce (SQUEEZE 대신
                        // RANGING 사용)
    REGIME_TRENDING,    // 2. 추세 시작 (ADX > 30) -> Singularity Breakout
                        // (BREAKOUT 대신 TRENDING 사용)
    REGIME_OVEREXTEND,  // 3. 추세 과열 (밴드 밖 장대) -> Reversal (신규 로직)
    REGIME_UNCERTAIN    // 4. 불확실/관망 (ADX 17~30 사이 또는 에러)
};
enum ENUM_MARKET_BIAS { BIAS_BUY, BIAS_SELL, BIAS_NEUTRAL };
enum ENUM_TRADE_DIRECTION { BUY_ONLY, SELL_ONLY, BOTH };
enum ENUM_LOT_CALCULATE_METHOD { FIXED, VOL_PER_BALANCE, VOL_PER_EQUITY };

input group "--- General Settings ---";
input ulong MagicNumber = 20251021;                          // 매직 넘버
input double LotSize = 0.01;                                 // 랏수
input ENUM_LOT_CALCULATE_METHOD LotCalculateMethod = FIXED;  // 랏 계산 방법
input double FixedLotSize = 0.01;  // FIXED 선택 시 고정 랏 수
input double BalancePerLotStep =
    1000.0;  // VOL_PER_BALANCE 선택 시 0.01 랏 비율

input group "--- Master Trend Filter ---";
input ENUM_TRADE_DIRECTION TradeDirection = BOTH;  // 거래 방향 설정
input ENUM_TIMEFRAMES MasterMaTimeframe =
    PERIOD_D1;                   // 거시적 방향 설정 (이동평균선)
input int MasterMaPeriod = 200;  // 이평선 기간
input double CandleTrendGapPoints = 2000.0;

input group "--- Bollinger Bands Settings ---";
input int BandsPeriod = 20;  // 볼린저 밴드 기간
input double BandsDeviation = 2.0;

input group "--- ADX Settings ---";
input int AdxPeriod = 14;  // adx 기간
input int AdxTrendingThreshold = 30;
input int AdxRangingThreshold = 17;

input group "--- Grid Management ---";
input string GridDistances =
    "177, 198, 223, 238, 238, 238, 238";  // 마틴게일 그리드 진입 거리 (1차,
                                          // 2차, ...)
int GridDistancePoints = 150;
int GridDistanceIncrease = 50;
input int GridMaxTrades = 7;  // 마틴게일 그리드 최대 진입 수
double BasketProfitUSD = 10.0;
input double BasketProfitSingle = 3.5;  // 단일 포지션 익절 USD
input double BasketProfitGridAdd =
    7.25;  // 포지션 추가 진입 시 단일 포지션 USD에 추가
input string BasketProfitGridAddComment =
    "예를들어 단일 포지션 익절이 3.5, 추가 usd가 7.25면 (단일 포지션 익절 + "
    "추가진입 * n)";

input group "--- Risk Management ---";
int StopLossPoints = 0;
int TakeProfitPoints = 0;

class CSingularityEngine {
   private:
    ulong magicNumber;
    double lotSize;
    int bandsPeriod;
    double bandsDeviation;
    int adxPeriod;
    int adxTrendingThreshold;
    int adxRangingThreshold;
    int stopLossPoints;
    int takeProfitPoints;
    double trendCandleGapPoints;

    ENUM_LOT_CALCULATE_METHOD lotCalcMethod;
    double fixedLotSize;
    double balancePerLotStep;
    double currentCycleLotSize;

    string gridDistances;
    int gridDistanceArray[100];
    int gridDistancesCount;
    int gridMaxTrades;
    double basketProfitSingle;
    double basketProfitGridAdd;

    int gridDistancePoints;
    int gridDistanceIncrease;
    double basketProfitUSD;

    int masterMaHandle;
    int bbHandle;
    int adxHandle;

    ENUM_MARKET_BIAS currentBias;
    ENUM_MARKET_REGIME currentRegime;
    ENUM_TRADE_DIRECTION tradeDirection;

    CTrade trade;
    CPositionInfo positionInfo;
    string symbol;
    ENUM_TIMEFRAMES period;

    ENUM_TIMEFRAMES masterMaTimeframe;
    int masterMaPeriod;

    double point;
    int digits;

    ENUM_MARKET_BIAS getMarketBias();
    ENUM_MARKET_REGIME getMarketRegime();
    double getDynamicLotSize();
    void checkSingularityBreakout(ENUM_ORDER_TYPE orderType,
                                  double tradeLotSize);
    void checkWallBounce(ENUM_ORDER_TYPE orderType, double tradeLotSize);
    void executeOrder(ENUM_ORDER_TYPE orderType, double tradeLotSize);
    void checkReversal(ENUM_ORDER_TYPE orderType, double tradeLotSize);
    void checkGridLogic();

    void closeAllPositions(string comment);
    void parseGridDistances();

   public:
    CSingularityEngine();
    ~CSingularityEngine();

    bool init(string sym, ENUM_TIMEFRAMES per, ulong magic,
              ENUM_LOT_CALCULATE_METHOD calcMethod, double lot,
              double balPerLot, int bPeriod, double bDev, int aPeriod,
              int aTrendTh, int aRangeTh, int slPoints, int tpPoints,
              ENUM_TIMEFRAMES mastMaTf, int mastMaPer,
              ENUM_TRADE_DIRECTION tradeDir, string gridDistStr, int gridMax,
              double basketSingle, double basketGridAdd, double trendGapPoints);
    void drawIndicatorsToChart(long chartID);
    void run();
    void checkEmergencyExit();
};

CSingularityEngine::CSingularityEngine() {
    bbHandle = INVALID_HANDLE;
    adxHandle = INVALID_HANDLE;
    masterMaHandle = INVALID_HANDLE;
}

CSingularityEngine::~CSingularityEngine() {
    if (bbHandle != INVALID_HANDLE) IndicatorRelease(bbHandle);
    if (adxHandle != INVALID_HANDLE) IndicatorRelease(adxHandle);
    if (masterMaHandle != INVALID_HANDLE) IndicatorRelease(masterMaHandle);
}

bool CSingularityEngine::init(string sym, ENUM_TIMEFRAMES per, ulong magic,
                              ENUM_LOT_CALCULATE_METHOD calcMethod, double lot,
                              double balPerLot, int bPeriod, double bDev,
                              int aPeriod, int aTrendTh, int aRangeTh,
                              int slPoints, int tpPoints,
                              ENUM_TIMEFRAMES mastMaTf, int mastMaPer,
                              ENUM_TRADE_DIRECTION tradeDir, string gridDistStr,
                              int gridMax, double basketSingle,
                              double basketGridAdd, double trendGapPoints) {
    symbol = sym;
    period = per;

    magicNumber = magic;
    lotSize = lot;
    lotCalcMethod = calcMethod;
    fixedLotSize = lot;
    balancePerLotStep = balPerLot;
    currentCycleLotSize = fixedLotSize;

    trendCandleGapPoints = trendGapPoints;

    bandsPeriod = bPeriod;
    bandsDeviation = bDev;
    adxPeriod = aPeriod;
    adxTrendingThreshold = aTrendTh;
    adxRangingThreshold = aRangeTh;
    stopLossPoints = slPoints;
    takeProfitPoints = tpPoints;

    gridDistances = gridDistStr;
    gridMaxTrades = gridMax;
    basketProfitSingle = basketSingle;
    basketProfitGridAdd = basketGridAdd;

    tradeDirection = tradeDir;

    masterMaTimeframe = mastMaTf;
    masterMaPeriod = mastMaPer;

    point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

    trade.SetExpertMagicNumber(magicNumber);
    // positionInfo.Symbol(symbol);

    parseGridDistances();

    bbHandle =
        iBands(symbol, period, bandsPeriod, 0, bandsDeviation, PRICE_CLOSE);
    adxHandle = iADX(symbol, period, adxPeriod);
    masterMaHandle = iMA(symbol, masterMaTimeframe, masterMaPeriod, 0, MODE_SMA,
                         PRICE_CLOSE);

    if (bbHandle == INVALID_HANDLE || adxHandle == INVALID_HANDLE ||
        masterMaHandle == INVALID_HANDLE) {
        Print("Error creating indicator handles - error:", GetLastError());
        return (false);
    }
    return true;
}

void CSingularityEngine::run() {
    static datetime lastBarTime = 0;
    datetime currentBarTime =
        (datetime)SeriesInfoInteger(symbol, period, SERIES_LASTBAR_DATE);

    bool isNewBar = false;
    if (lastBarTime < currentBarTime) {
        lastBarTime = currentBarTime;
        isNewBar = true;
    }

    //--- 2. 포지션이 있을 때 (그리드)
    if (PositionSelect(symbol)) {
        checkGridLogic();
    }
    //--- 1. 포지션이 없을 때 (첫 진입)
    else if (isNewBar)  // 포지션이 없고, 새 봉일 때만
    {
        currentCycleLotSize = getDynamicLotSize();
        if (currentCycleLotSize <= 0) {
            Print("Lot size calculation failed or result is 0. No trade.");
            return;
        }

        currentBias = getMarketBias();
        if (currentBias == BIAS_NEUTRAL) return;

        currentRegime = getMarketRegime();  // 4가지 상태 진단

        // [신규] 3-Way 분기
        if (currentBias == BIAS_BUY) {
            if (currentRegime == REGIME_OVEREXTEND) {
                // '상승 과열' -> 매도(Reversal) 신호 포착
                checkReversal(ORDER_TYPE_SELL, currentCycleLotSize);
            } else if (currentRegime == REGIME_TRENDING) {
                // '상승 추세' -> 매수(Breakout) 신호 포착
                double plusDI[1], minusDI[1];
                if (CopyBuffer(adxHandle, 1, 1, 1, plusDI) < 1 ||
                    CopyBuffer(adxHandle, 2, 1, 1, minusDI) < 1)
                    return;
                if (plusDI[0] > minusDI[0])
                    checkSingularityBreakout(ORDER_TYPE_BUY,
                                             currentCycleLotSize);
            } else if (currentRegime == REGIME_RANGING) {
                // '횡보' -> 매수(Wall Bounce) 신호 포착
                checkWallBounce(ORDER_TYPE_BUY, currentCycleLotSize);
            }
            // (REGIME_UNCERTAIN일 경우 아무것도 안 함)

        } else {  // (currentBias == BIAS_SELL)
            if (currentRegime == REGIME_OVEREXTEND) {
                // '하락 과열' -> 매수(Reversal) 신호 포착
                checkReversal(ORDER_TYPE_BUY, currentCycleLotSize);
            } else if (currentRegime == REGIME_TRENDING) {
                // '하락 추세' -> 매도(Breakout) 신호 포착
                double plusDI[1], minusDI[1];
                if (CopyBuffer(adxHandle, 1, 1, 1, plusDI) < 1 ||
                    CopyBuffer(adxHandle, 2, 1, 1, minusDI) < 1)
                    return;
                if (minusDI[0] > plusDI[0])
                    checkSingularityBreakout(ORDER_TYPE_SELL,
                                             currentCycleLotSize);
            } else if (currentRegime == REGIME_RANGING) {
                // '횡보' -> 매도(Wall Bounce) 신호 포착
                checkWallBounce(ORDER_TYPE_SELL, currentCycleLotSize);
            }
        }
    }
}

ENUM_MARKET_BIAS CSingularityEngine::getMarketBias() {
    if (tradeDirection == BUY_ONLY) return BIAS_BUY;
    if (tradeDirection == SELL_ONLY) return BIAS_SELL;

    double maValue[1];
    if (CopyBuffer(masterMaHandle, 0, 1, 1, maValue) < 1) {
        Print("Error copying Master MA buffer");
        return BIAS_NEUTRAL;
    }
    double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
    if (currentPrice == 0) return BIAS_NEUTRAL;

    if (currentPrice > maValue[0])
        return BIAS_BUY;
    else if (currentPrice < maValue[0])
        return BIAS_SELL;

    return BIAS_NEUTRAL;
}

ENUM_MARKET_REGIME CSingularityEngine::getMarketRegime() {
    // 1. 캔들 및 밴드 정보 가져오기
    MqlRates rates[2];
    if (CopyRates(symbol, period, 1, 2, rates) < 2) return REGIME_UNCERTAIN;

    double barClose = rates[0].close;
    double barRange = rates[0].high - rates[0].low;

    double bbUpper[1], bbLower[1];
    if (CopyBuffer(bbHandle, 1, 1, 1, bbUpper) < 1 ||
        CopyBuffer(bbHandle, 2, 1, 1, bbLower) < 1)
        return REGIME_UNCERTAIN;

    // 2. 상태 진단

    // [신규] 2-A. '과열(OVEREXTEND)' 상태
    // (님의 아이디어) "직전 캔들(장대)이 밴드 밖에서 마감했다"
    if ((barClose > bbUpper[0] && barRange >= trendCandleGapPoints * point) ||
        (barClose < bbLower[0] && barRange >= trendCandleGapPoints * point)) {
        Comment("Market Regime: OVEREXTEND");
        return REGIME_OVEREXTEND;
    }

    // 2-B. ADX 값 가져오기 (과열 상태가 아닐 때만)
    double adxValue[1];
    if (CopyBuffer(adxHandle, 0, 1, 1, adxValue) < 1) return REGIME_UNCERTAIN;

    // 2-C. '추세(TRENDING)' 상태
    if (adxValue[0] > adxTrendingThreshold)  // (ADX > 30)
    {
        Comment("Market Regime: TRENDING (Breakout)");
        return REGIME_TRENDING;
    }

    // 2-D. '횡보(RANGING)' 상태
    if (adxValue[0] < adxRangingThreshold)  // (ADX < 17)
    {
        Comment("Market Regime: RANGING (Squeeze)");
        return REGIME_RANGING;
    }

    // 2-E. 그 외는 '불확실'
    Comment("Market Regime: UNCERTAIN (ADX: " + (string)adxValue[0] + ")");
    return REGIME_UNCERTAIN;
}

double CSingularityEngine::getDynamicLotSize() {
    double newLot = 0.01;

    if (lotCalcMethod == FIXED) {
        newLot = fixedLotSize;
    }

    else if (lotCalcMethod == VOL_PER_BALANCE) {
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double lotStep = 0.01;

        if (balancePerLotStep > 0) {
            newLot = MathFloor(balance / balancePerLotStep) * lotStep;
        }
    }

    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

    if (newLot < minLot) newLot = minLot;
    if (newLot > maxLot) newLot = maxLot;

    newLot = NormalizeDouble(newLot - fmod(newLot, stepLot), 2);

    return newLot;
}

void CSingularityEngine::checkSingularityBreakout(ENUM_ORDER_TYPE orderType,
                                                  double tradeLotSize) {
    MqlRates rates[2];
    if (CopyRates(symbol, period, 1, 2, rates) < 2) return;

    double prevBarLow = rates[0].low;
    double prevBarHigh = rates[0].high;
    double prevBarClose = rates[0].close;

    double currentPriceBuy = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double currentPriceSell = SymbolInfoDouble(symbol, SYMBOL_BID);

    double bbUpper[1];
    double bbLower[1];
    double bbMiddle[1];
    if (CopyBuffer(bbHandle, 1, 1, 1, bbUpper) < 1 ||
        CopyBuffer(bbHandle, 2, 1, 1, bbLower) < 1 ||
        CopyBuffer(bbHandle, 0, 1, 1, bbMiddle) < 1)
        return;

    double currentMiddle = bbMiddle[0];
    double currentUpper = bbUpper[0];
    double currentLower = bbLower[0];

    if (orderType == ORDER_TYPE_BUY) {
        if (prevBarClose > currentMiddle && currentPriceBuy > currentMiddle) {
            Print("Singularity Breakout (Realtime Cross) BUY!");
            executeOrder(ORDER_TYPE_BUY, tradeLotSize);
        }
    } else if (orderType == ORDER_TYPE_SELL) {
        if (prevBarClose < currentMiddle && currentPriceSell < currentMiddle) {
            Print("Singularity Breakout (Realtime Cross) SELL!");
            executeOrder(ORDER_TYPE_SELL, tradeLotSize);
        }
    }
}

void CSingularityEngine::checkWallBounce(ENUM_ORDER_TYPE orderType,
                                         double tradeLotSize) {
    MqlRates rates[3];
    if (CopyRates(symbol, period, 1, 3, rates) < 3) return;
    double barClose = rates[0].close;
    double prevBarClose = rates[1].close;

    double bbUpper[2], bbLower[2];
    if (CopyBuffer(bbHandle, 1, 1, 2, bbUpper) < 2 ||
        CopyBuffer(bbHandle, 2, 1, 2, bbLower) < 2)
        return;
    double barLowerBand = bbLower[0];
    double prevBarLowerBand = bbLower[1];
    double barUpperBand = bbUpper[0];
    double prevBarUpperBand = bbUpper[1];

    double bbMiddle[1];
    if (CopyBuffer(bbHandle, 0, 0, 1, bbMiddle) < 1) return;
    double currentMiddle = bbMiddle[0];

    double currentPriceBuy = SymbolInfoDouble(symbol, SYMBOL_ASK);
    if (currentPriceBuy == 0) return;

    if (orderType == ORDER_TYPE_BUY) {
        // [버그 수정] (이전) barClose < barLowerBand && currentPriceBuy <
        // currentMiddle (수정) 하단 밴드 '복귀' + 중앙선 '회복'
        if (prevBarClose < prevBarLowerBand && barClose > barLowerBand &&
            currentPriceBuy > currentMiddle) {
            executeOrder(ORDER_TYPE_BUY, tradeLotSize);
        }
    } else if (orderType == ORDER_TYPE_SELL) {
        // [버그 수정] (이전) barClose > barUpperBand && currentPriceSell >
        // currentMiddle (수정) 상단 밴드 '복귀' + 중앙선 '회복 실패'
        if (prevBarClose > prevBarUpperBand && barClose < barUpperBand &&
            currentPriceBuy < currentMiddle) {
            executeOrder(ORDER_TYPE_SELL, tradeLotSize);
        }
    }
}

void CSingularityEngine::executeOrder(ENUM_ORDER_TYPE orderType,
                                      double tradeLotSize) {
    double price = 0;
    double sl = 0;
    double tp = 0;

    if (orderType == ORDER_TYPE_BUY) {
        price = SymbolInfoDouble(symbol, SYMBOL_ASK);
        // sl = (stopLossPoints > 0) ? price - stopLossPoints * point : 0;
        // tp = (takeProfitPoints > 0) ? price + takeProfitPoints * point : 0;
        trade.Buy(tradeLotSize, symbol, price, sl, tp,
                  "Singularity Engine Buy");
    } else if (orderType == ORDER_TYPE_SELL) {
        price = SymbolInfoDouble(symbol, SYMBOL_BID);
        // sl = (stopLossPoints > 0) ? price + stopLossPoints * point : 0;
        // tp = (takeProfitPoints > 0) ? price - takeProfitPoints * point : 0;
        trade.Sell(tradeLotSize, symbol, price, sl, tp,
                   "Singularity Engine Sell");
    }
}

void CSingularityEngine::checkReversal(ENUM_ORDER_TYPE orderType,
                                       double tradeLotSize) {
    MqlRates rates[4];
    if (CopyRates(symbol, period, 1, 4, rates) < 4) return;

    MqlRates barNow = rates[0];     // 직전 캔들 (확인용)
    MqlRates barPrev = rates[1];    // 그 전 캔들 (꼬리용)
    MqlRates barSignal = rates[2];  // 그 전전 캔들 (장대용)

    // 밴드 값 정의
    double bbUpper[3], bbLower[3];
    if (CopyBuffer(bbHandle, 1, 1, 3, bbUpper) < 3 ||
        CopyBuffer(bbHandle, 2, 1, 3, bbLower) < 3)
        return;

    if (orderType == ORDER_TYPE_SELL) {
        // 1. (장대) '그전전 캔들'이 장대양봉(+최소크기)이며 밴드 상단을 뚫고
        // 마감
        bool isBreakout =
            (barSignal.close > barSignal.open) &&
            (barSignal.high - barSignal.low >= trendCandleGapPoints * point) &&
            (barSignal.close > bbUpper[2]);

        // 2. (꼬리) '그 전 캔들'이 윗꼬리가 길다 (예: 캔들 몸통보다 꼬리가
        // 길다)
        double upperWick = barPrev.high - MathMax(barPrev.open, barPrev.close);
        double body = MathAbs(barPrev.open - barPrev.close);
        bool isWick = (upperWick > body);  // (꼬리가 몸통보다 길다)

        // 3. (확인) '직전 캔들'이 밴드 안으로 복귀
        bool isInside = (barNow.close < bbUpper[0]);

        if (isBreakout && isWick && isInside) {
            Print("Reversal Signal SELL!");
            executeOrder(ORDER_TYPE_SELL, tradeLotSize);
        }
    } else if (orderType == ORDER_TYPE_BUY) {
        // (위와 반대로 구현)
        bool isBreakout =
            (barSignal.close < barSignal.open) &&
            (barSignal.high - barSignal.low >= trendCandleGapPoints * point) &&
            (barSignal.close < bbLower[2]);

        double lowerWick = MathMin(barPrev.open, barPrev.close) - barPrev.low;
        double body = MathAbs(barPrev.open - barPrev.close);
        bool isWick = (lowerWick > body);

        bool isInside = (barNow.close > bbLower[0]);

        if (isBreakout && isWick && isInside) {
            Print("Reversal Signal BUY!");
            executeOrder(ORDER_TYPE_BUY, tradeLotSize);
        }
    }
}

void CSingularityEngine::checkEmergencyExit() {
    // 1. 현재 이 심볼에 내 매직넘버로 진입한 포지션이 있는지 확인
    if (!PositionSelect(symbol)) return;
    if (PositionGetInteger(POSITION_MAGIC) != magicNumber) return;

    // 2. 볼린저 밴드 데이터 가져오기 (현재 캔들 0번 기준)
    double bbUpper[1], bbLower[1];
    
    // Buffer 1: Upper Band, Buffer 2: Lower Band
    if (CopyBuffer(bbHandle, 1, 0, 1, bbUpper) < 1 || CopyBuffer(bbHandle, 2, 0, 1, bbLower) < 1) {
        return; // 데이터 복사 실패 시 패스
    }

    double currentUpper = bbUpper[0];
    double currentLower = bbLower[0];
    
    double currentBid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);

    long type = PositionGetInteger(POSITION_TYPE);

    // 3. 조건 비교 및 청산 실행
    
    // [BUY 포지션] 가격이 밴드 하단(Lower) 밑으로 뚫고 내려가면 손절
    if (type == POSITION_TYPE_BUY) {
        if (currentBid < currentLower) {
            Print("🚨 EMERGENCY EXIT: Price dropped below BB Lower Band!");
            closeAllPositions("Stop Loss (BB Lower Break)");
        }
    }
    // [SELL 포지션] 가격이 밴드 상단(Upper) 위로 뚫고 올라가면 손절
    else if (type == POSITION_TYPE_SELL) {
        if (currentAsk > currentUpper) {
            Print("🚨 EMERGENCY EXIT: Price broke above BB Upper Band!");
            closeAllPositions("Stop Loss (BB Upper Break)");
        }
    }
}

void CSingularityEngine::checkGridLogic() {
    double totalProfit = 0;
    int totalPositions = 0;
    double lastPrice = 0;
    ulong lastTicket = 0;
    ENUM_POSITION_TYPE positionType = POSITION_TYPE_BUY;

    // 1. 현재 포지션 상태 확인
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (positionInfo.SelectByIndex(i)) {
            if (positionInfo.Symbol() == symbol &&
                positionInfo.Magic() == magicNumber) {
                totalPositions++;
                totalProfit += positionInfo.Profit() + positionInfo.Swap();
                positionType = positionInfo.PositionType();

                // 마지막 진입 가격 찾기 (물타기용)
                if (positionInfo.Ticket() > lastTicket) {
                    lastTicket = positionInfo.Ticket();
                    lastPrice = positionInfo.PriceOpen();
                }
            }
        }
    }

    if (totalPositions == 0) return;

    // ================================================================
    // [긴급 추가] 추세 이탈 시 전량 손절 (Emergency Exit)
    // ================================================================
    double maValue[1];
    // 현재 캔들(0번)이나 직전 캔들(1번) 기준 MA 값 가져오기
    if (CopyBuffer(masterMaHandle, 0, 0, 1, maValue) < 1) return;

    double currentBid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);

    // CASE 1: 매수(BUY) 포지션인데, 가격이 이평선(Master MA) 밑으로 추락함 ->
    // 손절!
    if (positionType == POSITION_TYPE_BUY) {
        if (currentBid < maValue[0]) {
            closeAllPositions("Emergency Exit: Trend Broken (Price < MA)");
            return;  // 종료
        }
    }
    // CASE 2: 매도(SELL) 포지션인데, 가격이 이평선 위로 급등함 -> 손절!
    else if (positionType == POSITION_TYPE_SELL) {
        if (currentAsk > maValue[0]) {
            closeAllPositions("Emergency Exit: Trend Broken (Price > MA)");
            return;  // 종료
        }
    }
    // ================================================================

    // 2. 익절(Take Profit) 로직
    double currentTargetProfit = 0;
    if (totalPositions == 1)
        currentTargetProfit = basketProfitSingle;
    else if (totalPositions > 1)
        currentTargetProfit =
            basketProfitSingle + (basketProfitGridAdd * (totalPositions - 1));

    if (totalProfit >= currentTargetProfit) {
        closeAllPositions(StringFormat("Basket TP Hit ($%.2f)", totalProfit));
        return;
    }

    // 3. 물타기(Grid) 로직
    if (totalPositions >= gridMaxTrades) return;
    if (totalPositions - 1 >= gridDistancesCount) return;

    int currentGridDistance = gridDistanceArray[totalPositions - 1];
    bool distanceReached = false;

    if (positionType == POSITION_TYPE_BUY) {
        if (currentBid <= lastPrice - currentGridDistance * point)
            distanceReached = true;
    } else {
        if (currentAsk >= lastPrice + currentGridDistance * point)
            distanceReached = true;
    }

    if (distanceReached) {
        double nextLotSize = currentCycleLotSize;
        // (원한다면 여기서 랏수 배수 적용 가능)

        double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        if (nextLotSize > maxLot) nextLotSize = maxLot;

        ENUM_ORDER_TYPE orderType = (positionType == POSITION_TYPE_BUY)
                                        ? ORDER_TYPE_BUY
                                        : ORDER_TYPE_SELL;
        executeOrder(orderType, nextLotSize);
    }
}
void CSingularityEngine::closeAllPositions(string comment) {
    Print("Closing all positions: ", comment);
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (positionInfo.SelectByIndex(i)) {
            if (positionInfo.Symbol() == symbol &&
                positionInfo.Magic() == magicNumber) {
                trade.PositionClose(positionInfo.Ticket());
            }
        }
    }
}

void CSingularityEngine::parseGridDistances() {
    ArrayInitialize(gridDistanceArray, 0);
    gridDistancesCount = 0;

    ushort separator = (ushort)',';
    string str = gridDistances;

    string currentValue;
    for (int i = 0; i < StringLen(str); i++) {
        ushort charCode = StringGetCharacter(str, i);
        if (charCode == separator) {
            if (gridDistancesCount < 100) {
                gridDistanceArray[gridDistancesCount] =
                    (int)StringToInteger(currentValue);
                gridDistancesCount++;
                currentValue = "";
            }
        } else {
            currentValue += StringFormat("%c", charCode);
        }
    }
    if (currentValue != "" && gridDistancesCount < 100) {
        gridDistanceArray[gridDistancesCount] =
            (int)StringToInteger(currentValue);
        gridDistancesCount++;
    }

    Print("Grid distances parsed. Total levels: ", gridDistancesCount);
}

void CSingularityEngine::drawIndicatorsToChart(long chartID) {
    if (!ChartIndicatorAdd(chartID, 0, bbHandle)) {
        Print("Failed to add BB to chart!");
        return;
    }
    if (!ChartIndicatorAdd(chartID, 1, adxHandle)) {
        Print("Failed to add ADX to chart!");
        return;
    }

    string bbName = ChartIndicatorName(chartID, 0, 0);
    string adxName = ChartIndicatorName(chartID, 1, 0);

    if (bbName == "" || adxName == "") {
        Print("Failed to get indicator object names on chart!");
        return;
    }

    ObjectSetInteger(chartID, bbName, OBJPROP_COLOR, 0, clrWhite);
    ObjectSetInteger(chartID, bbName, OBJPROP_COLOR, 1, clrWhite);
    ObjectSetInteger(chartID, bbName, OBJPROP_COLOR, 2, clrWhite);

    ObjectSetInteger(chartID, adxName, OBJPROP_COLOR, 0, clrDeepSkyBlue);
    ObjectSetInteger(chartID, adxName, OBJPROP_COLOR, 1, clrLime);
    ObjectSetInteger(chartID, adxName, OBJPROP_COLOR, 2, clrGold);

    ObjectSetInteger(chartID, adxName, OBJPROP_LEVELS, 2);

    ObjectSetDouble(chartID, adxName, OBJPROP_LEVELVALUE, 0,
                    adxTrendingThreshold);
    ObjectSetInteger(chartID, adxName, OBJPROP_LEVELCOLOR, 0, clrGray);
    ObjectSetInteger(chartID, adxName, OBJPROP_LEVELSTYLE, 0, STYLE_DOT);

    ObjectSetDouble(chartID, adxName, OBJPROP_LEVELVALUE, 1,
                    adxRangingThreshold);
    ObjectSetInteger(chartID, adxName, OBJPROP_LEVELCOLOR, 1, clrGray);
    ObjectSetInteger(chartID, adxName, OBJPROP_LEVELSTYLE, 1, STYLE_DOT);

    ChartRedraw(chartID);
}

CSingularityEngine GEngine;

int OnInit() {
    if (MQLInfoInteger(MQL_VISUAL_MODE)) {
        // TesterHideIndicators(true);
        // GEngine.drawIndicatorsToChart(0);
    }

    if (!GEngine.init(_Symbol, _Period, MagicNumber, LotCalculateMethod,
                      FixedLotSize, BalancePerLotStep, BandsPeriod,
                      BandsDeviation, AdxPeriod, AdxTrendingThreshold,
                      AdxRangingThreshold, StopLossPoints, TakeProfitPoints,
                      MasterMaTimeframe, MasterMaPeriod, TradeDirection,
                      GridDistances, GridMaxTrades, BasketProfitSingle,
                      BasketProfitGridAdd, CandleTrendGapPoints)) {
        Print("Engine initialization failed.");
        return (INIT_FAILED);
    }

    Print("Singularity Engine v", GVersion, " initialized successfully.");
    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { Print("Singularity Engine deinitialized."); }

void OnTick() {
    // GEngine.checkEmergencyExit();
    GEngine.run();
}