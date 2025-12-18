#property copyright "Copyright 2025, p3pwp3p"
#property link      "https://github.com/hayan2"
#property version   "0.22" // Fixed all declaration and pointer call bugs

const string GVersion = "0.22";

#include <Trade/Trade.mqh>

input group "--- General Settings ---";
input ulong  MagicNumber = 20251021;
input double LotSize = 0.01;

input group "--- Bollinger Bands Settings ---";
input int    BandsPeriod = 20;
input double BandsDeviation = 2.0;

input group "--- ADX Settings ---";
input int    AdxPeriod = 14; // <-- ADX Period input 추가됨

input group "--- Regime Filter Settings ---";
input double BandwidthThreshold = 0.005;

input group "--- Risk Management ---";
input int    StopLossPoints = 200;
input int    TakeProfitPoints = 400;

//--- Enums (전역)
enum ENUM_MARKET_REGIME { REGIME_TRENDING, REGIME_RANGING, REGIME_UNCERTAIN };
enum ENUM_MARKET_BIAS { BIAS_BUY, BIAS_SELL, BIAS_NEUTRAL };

//+------------------------------------------------------------------+
//| CSingularityEngine 클래스 정의
//+------------------------------------------------------------------+
class CSingularityEngine
{
private:
    ulong    magicNumber;
    double   lotSize;
    int      bandsPeriod;
    double   bandsDeviation;
    double   bandwidthThreshold;
    int      adxPeriod; // <-- adxPeriod 멤버 변수 추가됨
    int      stopLossPoints;
    int      takeProfitPoints;

    int      bbHandle;
    int      adxHandle;

    ENUM_MARKET_BIAS   currentBias;
    ENUM_MARKET_REGIME currentRegime;

    CTrade   trade;
    string   symbol;
    ENUM_TIMEFRAMES period;

    //--- 내부 함수 선언부 (매개변수 일치시킴)
    ENUM_MARKET_BIAS   getMarketBias();
    ENUM_MARKET_REGIME getMarketRegime();
    void     checkSingularityBreakout(ENUM_ORDER_TYPE orderType); // <--- 수정됨
    void     checkWallBounce(ENUM_ORDER_TYPE orderType);          // <--- 수정됨

public:
    CSingularityEngine(string sym, ENUM_TIMEFRAMES per);
    ~CSingularityEngine();

    //--- init 선언부 (매개변수 일치시킴)
    bool     init(ulong magic, double lot, int bPeriod, double bDev, 
                  double bwThreshold, int slPoints, int tpPoints, int aPeriod); // <--- 수정됨

    void     run();
};

//+------------------------------------------------------------------+
//| 클래스 생성자
//+------------------------------------------------------------------+
CSingularityEngine::CSingularityEngine(string sym, ENUM_TIMEFRAMES per)
{
    symbol = sym;
    period = per;
    bbHandle = INVALID_HANDLE;
    adxHandle = INVALID_HANDLE; // adxHandle도 초기화
}

//+------------------------------------------------------------------+
//| 클래스 소멸자
//+------------------------------------------------------------------+
CSingularityEngine::~CSingularityEngine()
{
    if(bbHandle != INVALID_HANDLE)
        IndicatorRelease(bbHandle);

    if(adxHandle != INVALID_HANDLE) // <-- adxHandle 해제 추가됨
        IndicatorRelease(adxHandle);
}

//+------------------------------------------------------------------+
//| EA 초기화 (init 구현부)
//+------------------------------------------------------------------+
bool CSingularityEngine::init(ulong magic, double lot, int bPeriod, double bDev, 
                              double bwThreshold, int slPoints, int tpPoints, int aPeriod) // <--- 수정됨
{
    magicNumber = magic;
    lotSize = lot;
    bandsPeriod = bPeriod;
    bandsDeviation = bDev;
    bandwidthThreshold = bwThreshold;
    stopLossPoints = slPoints;
    takeProfitPoints = tpPoints;
    adxPeriod = aPeriod; // <-- adxPeriod 저장 추가됨

    trade.SetExpertMagicNumber(magicNumber);

    //--- 지표 생성
    bbHandle = iBands(symbol, period, bandsPeriod, 0, bandsDeviation, PRICE_CLOSE);
    adxHandle = iADX(symbol, period, adxPeriod); // <-- 올바른 변수 사용

    if(bbHandle == INVALID_HANDLE || adxHandle == INVALID_HANDLE) // adxHandle 체크 추가
    {
        Print("Error creating indicator handles - error:", GetLastError());
        return (false);
    }

    return true;
}

//+------------------------------------------------------------------+
//| EA 메인 로직 (run)
//+------------------------------------------------------------------+
void CSingularityEngine::run()
{
    static datetime lastBarTime = 0;
    datetime currentBarTime = (datetime)SeriesInfoInteger(symbol, period, SERIES_LASTBAR_DATE);

    if(lastBarTime >= currentBarTime)
        return;
    lastBarTime = currentBarTime;
    
    // 포지션이 없을 때만 신규 진입 로직 실행
    if(!PositionSelect(symbol))
    {
        currentBias = getMarketBias();
        if(currentBias == BIAS_NEUTRAL) return;

        currentRegime = getMarketRegime();
        if(currentRegime == REGIME_UNCERTAIN) return;

        if(currentBias == BIAS_BUY)
        {
            if(currentRegime == REGIME_TRENDING) checkSingularityBreakout(ORDER_TYPE_BUY);
            else checkWallBounce(ORDER_TYPE_BUY);
        }
        else // (currentBias == BIAS_SELL)
        {
            if(currentRegime == REGIME_TRENDING) checkSingularityBreakout(ORDER_TYPE_SELL);
            else checkWallBounce(ORDER_TYPE_SELL);
        }
    }
}

//+------------------------------------------------------------------+
//| [빈 함수] 시장 방향성 진단
//+------------------------------------------------------------------+
ENUM_MARKET_BIAS CSingularityEngine::getMarketBias()
{
    // (다음 단계에서 채울 예정)
    return BIAS_NEUTRAL; // 임시
}

//+------------------------------------------------------------------+
//| [수정됨] 시장 국면 진단 (ADX 기반으로 변경)
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME CSingularityEngine::getMarketRegime()
{
    // *** 참고: BandwidthThreshold 로직 대신 ADX 강도로 변경하는 것을 제안합니다. ***
    // (일단은 기존 코드를 유지)
    
    double bbUpper[1];
    double bbLower[1];
    double bbMiddle[1];

    if(CopyBuffer(bbHandle, 1, 1, 1, bbUpper) < 1 || CopyBuffer(bbHandle, 2, 1, 1, bbLower) < 1 ||
       CopyBuffer(bbHandle, 0, 1, 1, bbMiddle) < 1)
    {
        return REGIME_UNCERTAIN;
    }

    if(bbMiddle[0] == 0)
        return REGIME_UNCERTAIN;

    double bandwidth = (bbUpper[0] - bbLower[0]) / bbMiddle[0];

    if(bandwidth > bandwidthThreshold)
    {
        Comment("Market Regime: TRENDING (Bandwidth)");
        return REGIME_TRENDING;
    }
    else
    {
        Comment("Market Regime: RANGING (Bandwidth)");
        return REGIME_RANGING;
    }
}

//+------------------------------------------------------------------+
//| [빈 함수] 추세 진입 로직
//+------------------------------------------------------------------+
void CSingularityEngine::checkSingularityBreakout(ENUM_ORDER_TYPE orderType)
{
    // (다음 단계에서 채울 예정)
}

//+------------------------------------------------------------------+
//| [빈 함수] 역추세 진입 로직
//+------------------------------------------------------------------+
void CSingularityEngine::checkWallBounce(ENUM_ORDER_TYPE orderType)
{
    // (다음 단계에서 채울 예정)
}


//+------------------------------------------------------------------+
//| MQL5 메인 함수들 (전역)
//+------------------------------------------------------------------+
CSingularityEngine *GEngine;

int OnInit()
{
    GEngine = new CSingularityEngine(_Symbol, _Period);
    if(GEngine == NULL)
    {
        Print("Error creating CSingularityEngine object - critical memory error");
        return (INIT_FAILED);
    }

    //--- GEngine->init() 호출 (화살표 -> 사용 및 AdxPeriod 전달)
    if(!GEngine->init(MagicNumber, LotSize, BandsPeriod, BandsDeviation, 
                      BandwidthThreshold, StopLossPoints, TakeProfitPoints, AdxPeriod)) // <--- 수정됨
    {
        Print("Engine initialization failed.");
        return (INIT_FAILED);
    }

    Print("Singularity Engine v", GVersion, " initialized successfully.");
    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
    if(GEngine != NULL)
    {
        delete GEngine;
        GEngine = NULL;
    }
    Print("Singularity Engine deinitialized.");
}

void OnTick()
{
    if(GEngine != NULL)
        GEngine->run(); // <--- 수정됨 (.) -> (->)
}