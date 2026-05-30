//+------------------------------------------------------------------+
//|                                             CandleBodyAlert.mq5  |
//|                   Alert when candle body exceeds threshold pips  |
//+------------------------------------------------------------------+
#property copyright "Grid Trading EA"
#property version   "1.00"

input double ThresholdPips = 40.0; // Threshold (pips)
input bool   AlertUpMove   = true; // Alert on bullish candle
input bool   AlertDownMove = true; // Alert on bearish candle

datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
    lastBarTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
    datetime currentBarTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
    if(currentBarTime == lastBarTime) return;
    lastBarTime = currentBarTime;

    double barOpen  = iOpen(_Symbol, _Period, 1);
    double barClose = iClose(_Symbol, _Period, 1);
    if(barOpen == 0 || barClose == 0) return;

    double pipSize  = (_Digits == 5 || _Digits == 3) ? _Point * 10.0 : _Point;
    double threshold = ThresholdPips * pipSize;
    double diff      = barClose - barOpen;

    if(AlertUpMove && diff >= threshold)
    {
        SendNotification(StringFormat("%s %s: Bullish candle body %.1f pips (threshold %.1f)",
                                     _Symbol, EnumToString(_Period), diff / pipSize, ThresholdPips));
    }
    else if(AlertDownMove && diff <= -threshold)
    {
        SendNotification(StringFormat("%s %s: Bearish candle body %.1f pips (threshold %.1f)",
                                     _Symbol, EnumToString(_Period), MathAbs(diff) / pipSize, ThresholdPips));
    }
}
