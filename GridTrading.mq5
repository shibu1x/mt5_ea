//+------------------------------------------------------------------+
//|                                                  GridTrading.mq5 |
//|                                      Grid Trading Expert Advisor |
//+------------------------------------------------------------------+
#property copyright "Grid Trading EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

// Input Parameters
input group "=== Basic Settings ==="
input int      GridStepPips = 5;            // Grid Step & TP (pips)
input bool     UseTakeProfit = true;        // Use Take Profit
input bool     UseStopOrders = false;       // Use Stop Orders (BuyStop/SellStop)
input double   LotSize = 0.01;              // Lot Size
input int      MagicNumber = 8001;          // Magic Number
input double   GridCenterPrice = 147.53;    // Grid Center Price

input group "=== Sell Grid Settings ==="
input bool     SellEnabled = true;          // Sell Grid Enabled
input int      SellRangePips = 400;         // Sell Grid Range (pips from center)

input group "=== Buy Grid Settings ==="
input bool     BuyEnabled = true;           // Buy Grid Enabled
input int      BuyRangePips = 400;          // Buy Grid Range (pips from center)

// Global Variables
CTrade trade;
int gridStepPrice;
double pointValue;
double cachedLotSize;
int totalBuyOrders = 0;
int totalSellOrders = 0;
int highestBuyPrice = 0;
int lowestBuyPrice = 0;
int highestSellPrice = 0;
int lowestSellPrice = 0;
datetime lastBarTime = 0;

// Calculated grid boundaries (as integers)
int sellLowerInt, sellUpperInt;
int buyLowerInt, buyUpperInt;

// Cached symbol info
int symbolDigits;

//+------------------------------------------------------------------+
//| Convert pips to integer price units                              |
//+------------------------------------------------------------------+
int PipsToInt(int pips)
{
    return pips * ((symbolDigits == 3 || symbolDigits == 5) ? 10 : 100);
}

//+------------------------------------------------------------------+
//| Convert double price to integer price                            |
//+------------------------------------------------------------------+
int PriceToInt(double price)
{
    return (int)MathRound(price / pointValue);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_FOK);

    pointValue    = _Point;
    symbolDigits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    cachedLotSize = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
                    MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), LotSize));
    gridStepPrice = PipsToInt(GridStepPips);

    Print("=== Grid Trading EA Initialization ===");
    Print("Grid Step & TP: ", GridStepPips, " pips (", DoubleToString(gridStepPrice * pointValue, symbolDigits), ")");
    Print("Lot Size: ", cachedLotSize);
    Print("Grid Center Price: ", GridCenterPrice);

    if((SellEnabled || BuyEnabled) && GridCenterPrice <= 0)
    {
        Print("Error: Grid center price is required");
        return INIT_PARAMETERS_INCORRECT;
    }

    int centerInt = PriceToInt(GridCenterPrice);

    if(SellEnabled)
    {
        if(SellRangePips < 0)
        {
            Print("Error: Sell grid range must be non-negative");
            return INIT_PARAMETERS_INCORRECT;
        }
        sellLowerInt = centerInt;
        sellUpperInt = centerInt + PipsToInt(SellRangePips);
        Print("--- Sell Grid ---");
        Print("Price Range: ", DoubleToString(sellLowerInt * pointValue, symbolDigits), " - ", DoubleToString(sellUpperInt * pointValue, symbolDigits), " ", SellRangePips, " pips");
    }

    if(BuyEnabled)
    {
        if(BuyRangePips < 0)
        {
            Print("Error: Buy grid range must be non-negative");
            return INIT_PARAMETERS_INCORRECT;
        }
        buyUpperInt = centerInt;
        buyLowerInt = centerInt - PipsToInt(BuyRangePips);
        if(buyLowerInt <= 0)
        {
            Print("Error: Calculated buy lower price is invalid (", DoubleToString(buyLowerInt * pointValue, symbolDigits), ")");
            return INIT_PARAMETERS_INCORRECT;
        }
        Print("--- Buy Grid ---");
        Print("Price Range: ", DoubleToString(buyLowerInt * pointValue, symbolDigits), " - ", DoubleToString(buyUpperInt * pointValue, symbolDigits), " ", BuyRangePips, " pips");
    }

    Print("Initialization Complete");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("Grid Trading EA Terminated");
}

//+------------------------------------------------------------------+
//| Run grid management for all enabled grids                        |
//+------------------------------------------------------------------+
void RunGridManagement()
{
    UpdateGridStatus();
    if(SellEnabled && SellRangePips > 0) ManageGrid(false);
    else if(SellEnabled) CleanupOrders(false, sellLowerInt, sellUpperInt);
    if(BuyEnabled  && BuyRangePips  > 0) ManageGrid(true);
    else if(BuyEnabled)  CleanupOrders(true,  buyLowerInt,  buyUpperInt);
}

//+------------------------------------------------------------------+
//| Trade event handler                                              |
//+------------------------------------------------------------------+
void OnTrade()
{
    static int lastPositionCount = 0;
    int currentPositionCount = 0;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
        currentPositionCount++;
    }

    if(lastPositionCount > currentPositionCount)
    {
        Print("Position Closed Detected - Executing Grid Update");
        RunGridManagement();
    }

    lastPositionCount = currentPositionCount;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(currentBarTime == lastBarTime) return;
    lastBarTime = currentBarTime;

    Print("Bar Updated");
    RunGridManagement();
}

//+------------------------------------------------------------------+
//| Update grid status                                               |
//+------------------------------------------------------------------+
void UpdateGridStatus()
{
    totalBuyOrders   = 0;
    totalSellOrders  = 0;
    highestBuyPrice  = 0;
    lowestBuyPrice   = 999999999;
    highestSellPrice = 0;
    lowestSellPrice  = 999999999;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

        int openPrice = PriceToInt(PositionGetDouble(POSITION_PRICE_OPEN));
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        if(type == POSITION_TYPE_BUY)
        {
            totalBuyOrders++;
            if(openPrice > highestBuyPrice) highestBuyPrice = openPrice;
            if(openPrice < lowestBuyPrice)  lowestBuyPrice  = openPrice;
        }
        else if(type == POSITION_TYPE_SELL)
        {
            totalSellOrders++;
            if(openPrice > highestSellPrice) highestSellPrice = openPrice;
            if(openPrice < lowestSellPrice)  lowestSellPrice  = openPrice;
        }
    }
}

//+------------------------------------------------------------------+
//| Manage grid (buy or sell)                                        |
//+------------------------------------------------------------------+
void ManageGrid(bool isBuy)
{
    int lowerInt = isBuy ? buyLowerInt : sellLowerInt;
    int upperInt = isBuy ? buyUpperInt : sellUpperInt;

    int currentPrice = isBuy ? PriceToInt(SymbolInfoDouble(_Symbol, SYMBOL_ASK))
                              : PriceToInt(SymbolInfoDouble(_Symbol, SYMBOL_BID));

    int gridPrice = isBuy ? upperInt : lowerInt;
    int step      = isBuy ? -gridStepPrice : gridStepPrice;

    while(isBuy ? gridPrice >= lowerInt : gridPrice <= upperInt)
    {
        if(!CheckOrderExists(gridPrice, isBuy))
        {
            if(isBuy)
            {
                if(gridPrice < currentPrice)
                    PlaceOrder(ORDER_TYPE_BUY_LIMIT, gridPrice, true);
                else if(UseStopOrders)
                    PlaceOrder(ORDER_TYPE_BUY_STOP, gridPrice, true);
            }
            else
            {
                if(gridPrice > currentPrice)
                    PlaceOrder(ORDER_TYPE_SELL_LIMIT, gridPrice, false);
                else if(UseStopOrders)
                    PlaceOrder(ORDER_TYPE_SELL_STOP, gridPrice, false);
            }
        }
        gridPrice += step;
    }

    CleanupOrders(isBuy, lowerInt, upperInt);
}

//+------------------------------------------------------------------+
//| Cleanup pending orders outside fixed grid bounds                 |
//+------------------------------------------------------------------+
void CleanupOrders(bool isBuy, int lowerInt, int upperInt)
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket <= 0) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;

        ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        bool isOrderBuy = (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP);
        if(isBuy != isOrderBuy) continue;

        int orderPrice = PriceToInt(OrderGetDouble(ORDER_PRICE_OPEN));
        if(orderPrice < lowerInt || orderPrice > upperInt)
        {
            trade.OrderDelete(ticket);
            Print("Deleted out-of-range ", (isBuy ? "buy" : "sell"), " order: ", EnumToString(orderType), " Price ", DoubleToString(orderPrice * pointValue, symbolDigits));
        }
    }
}

//+------------------------------------------------------------------+
//| Generic order existence check                                    |
//+------------------------------------------------------------------+
bool CheckOrderExists(int gridPrice, bool isBuy)
{
    int tolerance = gridStepPrice / 2;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        if(isBuy != (posType == POSITION_TYPE_BUY)) continue;

        if(MathAbs(PriceToInt(PositionGetDouble(POSITION_PRICE_OPEN)) - gridPrice) < tolerance)
            return true;
    }

    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket <= 0) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;

        ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        bool isOrderBuy = (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP);
        if(isBuy != isOrderBuy) continue;

        if(MathAbs(PriceToInt(OrderGetDouble(ORDER_PRICE_OPEN)) - gridPrice) < tolerance)
            return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Generic order placement function                                 |
//+------------------------------------------------------------------+
bool PlaceOrder(ENUM_ORDER_TYPE orderType, int priceInt, bool isBuy)
{
    double price = NormalizeDouble(priceInt * pointValue, symbolDigits);
    double tp = UseTakeProfit
        ? NormalizeDouble((priceInt + (isBuy ? gridStepPrice : -gridStepPrice)) * pointValue, symbolDigits)
        : 0;

    bool result = false;
    string typeName;

    switch(orderType)
    {
        case ORDER_TYPE_BUY_STOP:
            result = trade.BuyStop(cachedLotSize, price, _Symbol, 0, tp, ORDER_TIME_GTC, 0, "Buy Stop");
            typeName = "Buy Stop";
            break;
        case ORDER_TYPE_BUY_LIMIT:
            result = trade.BuyLimit(cachedLotSize, price, _Symbol, 0, tp, ORDER_TIME_GTC, 0, "Buy Limit");
            typeName = "Buy Limit";
            break;
        case ORDER_TYPE_SELL_STOP:
            result = trade.SellStop(cachedLotSize, price, _Symbol, 0, tp, ORDER_TIME_GTC, 0, "Sell Stop");
            typeName = "Sell Stop";
            break;
        case ORDER_TYPE_SELL_LIMIT:
            result = trade.SellLimit(cachedLotSize, price, _Symbol, 0, tp, ORDER_TIME_GTC, 0, "Sell Limit");
            typeName = "Sell Limit";
            break;
    }

    if(result)
        Print(typeName, " order success: Price:", DoubleToString(price, symbolDigits), " TP:", DoubleToString(tp, symbolDigits));
    else
        Print(typeName, " order failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());

    return result;
}

//+------------------------------------------------------------------+
