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
input double   GridStepPips = 5;            // Grid Step & TP (pips)
input double   LotSize = 0.04;              // Lot Size
input int      GridRange = 3;               // Grid Range (number of grids from close price)
input int      MagicNumber = 8001;          // Magic Number

input group "=== Sell Grid Settings ==="
input bool     SellEnabled = true;          // Sell Grid Enabled
input double   SellLowerPrice = 147.53;     // Sell Grid Lower Price (required)
input double   SellRangePips = 400;         // Sell Grid Range (pips from lower price)

input group "=== Buy Grid Settings ==="
input bool     BuyEnabled = true;           // Buy Grid Enabled
input double   BuyUpperPrice = 147.53;      // Buy Grid Upper Price (required)
input double   BuyRangePips = 400;          // Buy Grid Range (pips from upper price)

// Global Variables
CTrade trade;
int gridStepPrice;
int takeProfitPrice;
double pointValue;
int totalBuyOrders = 0;
int totalSellOrders = 0;
int highestBuyPrice = 0;
int lowestBuyPrice = 0;
int highestSellPrice = 0;
int lowestSellPrice = 0;
datetime lastBarTime = 0;
int lastBidPrice = 0;
int lastAskPrice = 0;

// Calculated grid boundaries
double sellUpperPrice = 0;
double buyLowerPrice = 0;

// Cached symbol info
int symbolDigits;
double symbolMinLot;
double symbolMaxLot;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Trade object settings
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_FOK);

    // Cache symbol information
    pointValue = _Point;
    symbolDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    symbolMinLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    symbolMaxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

    // Convert pips to price (stored as integer)
    if(symbolDigits == 3 || symbolDigits == 5)
    {
        gridStepPrice = (int)MathRound(GridStepPips * pointValue * 10 / pointValue);
        takeProfitPrice = (int)MathRound(GridStepPips * pointValue * 10 / pointValue);
    }
    else
    {
        gridStepPrice = (int)MathRound(GridStepPips * pointValue * 100 / pointValue);
        takeProfitPrice = (int)MathRound(GridStepPips * pointValue * 100 / pointValue);
    }

    Print("=== Grid Trading EA Initialization ===");
    Print("Grid Step & TP: ", GridStepPips, " pips (", gridStepPrice * pointValue, ")");
    Print("Lot Size: ", LotSize);
    Print("Grid Range: ", GridRange, " grids from close price");

    // Validate and display sell grid settings
    if(SellEnabled)
    {
        if(SellLowerPrice <= 0)
        {
            Print("Error: Sell grid lower price is required");
            return(INIT_PARAMETERS_INCORRECT);
        }
        if(SellRangePips <= 0)
        {
            Print("Error: Sell grid range must be positive");
            return(INIT_PARAMETERS_INCORRECT);
        }

        // Calculate sell upper price from lower price + range pips
        double pipValue;
        if(symbolDigits == 3 || symbolDigits == 5)
            pipValue = SellRangePips * pointValue * 10;
        else
            pipValue = SellRangePips * pointValue * 100;

        sellUpperPrice = SellLowerPrice + pipValue;

        Print("--- Sell Grid ---");
        Print("Lower Price: ", SellLowerPrice);
        Print("Range: ", SellRangePips, " pips");
        Print("Upper Price (calculated): ", sellUpperPrice);
    }

    // Validate and display buy grid settings
    if(BuyEnabled)
    {
        if(BuyUpperPrice <= 0)
        {
            Print("Error: Buy grid upper price is required");
            return(INIT_PARAMETERS_INCORRECT);
        }
        if(BuyRangePips <= 0)
        {
            Print("Error: Buy grid range must be positive");
            return(INIT_PARAMETERS_INCORRECT);
        }

        // Calculate buy lower price from upper price - range pips
        double pipValue;
        if(symbolDigits == 3 || symbolDigits == 5)
            pipValue = BuyRangePips * pointValue * 10;
        else
            pipValue = BuyRangePips * pointValue * 100;

        buyLowerPrice = BuyUpperPrice - pipValue;

        if(buyLowerPrice <= 0)
        {
            Print("Error: Calculated buy lower price is invalid (", buyLowerPrice, ")");
            return(INIT_PARAMETERS_INCORRECT);
        }

        Print("--- Buy Grid ---");
        Print("Upper Price: ", BuyUpperPrice);
        Print("Range: ", BuyRangePips, " pips");
        Print("Lower Price (calculated): ", buyLowerPrice);
    }

    Print("Initialization Complete");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("Grid Trading EA Terminated");
}

//+------------------------------------------------------------------+
//| Trade event handler                                              |
//+------------------------------------------------------------------+
void OnTrade()
{
    // Check if a position was closed (take profit or other reason)
    static int lastPositionCount = 0;
    int currentPositionCount = 0;

    // Count positions with magic number
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;

        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

        currentPositionCount++;
    }

    // Check if position count decreased (position closed)
    if(lastPositionCount > currentPositionCount)
    {
        // Position was closed, execute grid management
        Print("Position Closed Detected - Executing Grid Update");

        // Update current position status
        UpdateGridStatus();

        // Manage sell grid
        if(SellEnabled)
        {
            ManageSellGrid(lastAskPrice, lastBidPrice);
        }

        // Manage buy grid
        if(BuyEnabled)
        {
            ManageBuyGrid(lastAskPrice, lastBidPrice);
        }
    }

    // Update last position count
    lastPositionCount = currentPositionCount;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if new bar formed
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);

    if(currentBarTime == lastBarTime)
    {
        // Still within same bar, no processing
        return;
    }

    // New bar confirmed, execute processing
    lastBarTime = currentBarTime;

    // Get current prices at bar update (convert to integer)
    lastAskPrice = PriceToInt(SymbolInfoDouble(_Symbol, SYMBOL_ASK));
    lastBidPrice = PriceToInt(SymbolInfoDouble(_Symbol, SYMBOL_BID));
    Print("Bar Updated - Reference Prices - Ask: ", lastAskPrice * pointValue, " Bid: ", lastBidPrice * pointValue);

    // Update current position status
    UpdateGridStatus();

    // Manage sell grid
    if(SellEnabled)
    {
        ManageSellGrid(lastAskPrice, lastBidPrice);
    }

    // Manage buy grid
    if(BuyEnabled)
    {
        ManageBuyGrid(lastAskPrice, lastBidPrice);
    }
}

//+------------------------------------------------------------------+
//| Update grid status                                               |
//+------------------------------------------------------------------+
void UpdateGridStatus()
{
    totalBuyOrders = 0;
    totalSellOrders = 0;
    highestBuyPrice = 0;
    lowestBuyPrice = 999999999;
    highestSellPrice = 0;
    lowestSellPrice = 999999999;

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
            if(openPrice < lowestBuyPrice) lowestBuyPrice = openPrice;
        }
        else if(type == POSITION_TYPE_SELL)
        {
            totalSellOrders++;
            if(openPrice > highestSellPrice) highestSellPrice = openPrice;
            if(openPrice < lowestSellPrice) lowestSellPrice = openPrice;
        }
    }
}

//+------------------------------------------------------------------+
//| Manage sell grid                                                 |
//+------------------------------------------------------------------+
void ManageSellGrid(double ask, double bid)
{
    if(lastBidPrice <= 0) return;

    // Get current Bid price for order type determination (convert to integer)
    int currentBid = PriceToInt(SymbolInfoDouble(_Symbol, SYMBOL_BID));

    // Sell grid uses last Bid price as reference for range
    // Calculate range based on last Bid price
    int upperRange = lastBidPrice + (GridRange * gridStepPrice);
    int lowerRange = lastBidPrice - (GridRange * gridStepPrice);

    // Process all grid levels within range
    int gridPrice = PriceToInt(SellLowerPrice);

    // Find nearest grid level at or above lower range
    while(gridPrice < lowerRange)
    {
        gridPrice += gridStepPrice;
    }

    // Place orders at all grid levels within range
    while(gridPrice <= PriceToInt(sellUpperPrice) && gridPrice <= upperRange)
    {
        if(!CheckOrderExists(gridPrice, false))
        {
            int level = (int)(gridPrice - PriceToInt(SellLowerPrice)) / (int)gridStepPrice;

            // Determine order type based on current Bid price
            if(gridPrice > currentBid)
                PlaceOrder(ORDER_TYPE_SELL_LIMIT, gridPrice, level, false);
            else
                PlaceOrder(ORDER_TYPE_SELL_STOP, gridPrice, level, false);
        }
        gridPrice += gridStepPrice;
    }

    // Remove unnecessary pending orders (outside range)
    CleanupOrders(lowerRange, upperRange, false, SellLowerPrice, sellUpperPrice);
}

//+------------------------------------------------------------------+
//| Manage buy grid                                                  |
//+------------------------------------------------------------------+
void ManageBuyGrid(double ask, double bid)
{
    if(lastAskPrice <= 0) return;

    // Get current Ask price for order type determination (convert to integer)
    int currentAsk = PriceToInt(SymbolInfoDouble(_Symbol, SYMBOL_ASK));

    // Buy grid uses last Ask price as reference for range
    // Calculate range based on last Ask price
    int upperRange = lastAskPrice + (GridRange * gridStepPrice);
    int lowerRange = lastAskPrice - (GridRange * gridStepPrice);

    // Process all grid levels within range
    int gridPrice = PriceToInt(BuyUpperPrice);

    // Find nearest grid level at or below upper range
    while(gridPrice > upperRange)
    {
        gridPrice -= gridStepPrice;
    }

    // Place orders at all grid levels within range
    while(gridPrice >= PriceToInt(buyLowerPrice) && gridPrice >= lowerRange)
    {
        if(!CheckOrderExists(gridPrice, true))
        {
            int level = (int)(PriceToInt(BuyUpperPrice) - gridPrice) / (int)gridStepPrice;

            // Determine order type based on current Ask price
            if(gridPrice < currentAsk)
                PlaceOrder(ORDER_TYPE_BUY_LIMIT, gridPrice, level, true);
            else
                PlaceOrder(ORDER_TYPE_BUY_STOP, gridPrice, level, true);
        }
        gridPrice -= gridStepPrice;
    }

    // Remove unnecessary pending orders (outside range)
    CleanupOrders(lowerRange, upperRange, true, buyLowerPrice, BuyUpperPrice);
}

//+------------------------------------------------------------------+
//| Generic order existence check                                    |
//+------------------------------------------------------------------+
bool CheckOrderExists(int gridPrice, bool isBuy)
{
    int tolerance = gridStepPrice / 2;

    // Check positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;

        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        if((isBuy && posType != POSITION_TYPE_BUY) || (!isBuy && posType != POSITION_TYPE_SELL)) continue;

        int openPrice = PriceToInt(PositionGetDouble(POSITION_PRICE_OPEN));
        if(MathAbs(openPrice - gridPrice) < tolerance)
        {
            return true;
        }
    }

    // Check pending orders
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket <= 0) continue;

        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;

        ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

        // Check if order type matches the requested direction
        bool isOrderBuy = (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP);
        bool isOrderSell = (orderType == ORDER_TYPE_SELL_LIMIT || orderType == ORDER_TYPE_SELL_STOP);

        if((isBuy && !isOrderBuy) || (!isBuy && !isOrderSell)) continue;

        int orderPrice = PriceToInt(OrderGetDouble(ORDER_PRICE_OPEN));
        if(MathAbs(orderPrice - gridPrice) < tolerance)
        {
            return true;
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| Generic cleanup function for pending orders                      |
//+------------------------------------------------------------------+
void CleanupOrders(int lowerRange, int upperRange, bool isBuy, double lowerPrice, double upperPrice)
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket <= 0) continue;

        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;

        ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

        // Check if order matches the requested type
        bool isOrderBuy = (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP);
        bool isOrderSell = (orderType == ORDER_TYPE_SELL_LIMIT || orderType == ORDER_TYPE_SELL_STOP);

        if((isBuy && !isOrderBuy) || (!isBuy && !isOrderSell)) continue;

        int orderPrice = PriceToInt(OrderGetDouble(ORDER_PRICE_OPEN));
        int priceLowerInt = PriceToInt(lowerPrice);
        int priceUpperInt = PriceToInt(upperPrice);

        // Delete orders outside range or price limits
        if(orderPrice < lowerRange || orderPrice > upperRange ||
           orderPrice < priceLowerInt || orderPrice > priceUpperInt)
        {
            trade.OrderDelete(ticket);
            Print("Deleted unnecessary ", (isBuy ? "buy" : "sell"), " order: ", EnumToString(orderType), " Price ", orderPrice * pointValue);
        }
    }
}

//+------------------------------------------------------------------+
//| Convert double price to integer price                            |
//+------------------------------------------------------------------+
int PriceToInt(double price)
{
    return (int)MathRound(price / pointValue);
}

//+------------------------------------------------------------------+
//| Generic order placement function                                 |
//+------------------------------------------------------------------+
bool PlaceOrder(ENUM_ORDER_TYPE orderType, int priceInt, int level, bool isBuy)
{
    double lots = MathMax(symbolMinLot, MathMin(symbolMaxLot, LotSize));

    // Convert integer price to double
    double price = NormalizeDouble(priceInt * pointValue, symbolDigits);
    double tp = NormalizeDouble((priceInt + (isBuy ? takeProfitPrice : -takeProfitPrice)) * pointValue, symbolDigits);

    string orderTypeName = "";
    bool result = false;

    switch(orderType)
    {
        case ORDER_TYPE_BUY_STOP:
            result = trade.BuyStop(lots, price, _Symbol, 0, tp, ORDER_TIME_DAY, 0, "Buy Stop #" + IntegerToString(level));
            orderTypeName = "Buy Stop";
            break;
        case ORDER_TYPE_BUY_LIMIT:
            result = trade.BuyLimit(lots, price, _Symbol, 0, tp, ORDER_TIME_DAY, 0, "Buy Limit #" + IntegerToString(level));
            orderTypeName = "Buy Limit";
            break;
        case ORDER_TYPE_SELL_STOP:
            result = trade.SellStop(lots, price, _Symbol, 0, tp, ORDER_TIME_DAY, 0, "Sell Stop #" + IntegerToString(level));
            orderTypeName = "Sell Stop";
            break;
        case ORDER_TYPE_SELL_LIMIT:
            result = trade.SellLimit(lots, price, _Symbol, 0, tp, ORDER_TIME_DAY, 0, "Sell Limit #" + IntegerToString(level));
            orderTypeName = "Sell Limit";
            break;
    }

    if(result)
    {
        Print(orderTypeName, " order success: Level:", level, " Price:", price, " TP:", tp);
    }
    else
    {
        Print(orderTypeName, " order failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }

    return result;
}

//+------------------------------------------------------------------+
