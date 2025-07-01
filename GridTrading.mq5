//+------------------------------------------------------------------+
//|                                                  GridTrading.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "2.00"

//--- include files
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Constants
#define PRICE_TOLERANCE 0.5
#define DEVIATION_POINTS 10
#define INVALID_TICKET 0

//--- input parameters
input group "=== Basic Settings ==="
input double LotSize = 0.04;                    // Lot size
input int MagicNumber = 123456;                 // Magic number
input string Comment = "GridTrading";           // Comment

input group "=== Buy Grid Settings ==="
input bool EnableBuyGrid = true;                // Enable buy grid
input double BuyUpperLimit = 144.7;             // Buy grid upper limit price
input double BuyLowerLimit = 142;               // Buy grid lower limit price
input double BuyGridStep = 0.05;                // Buy grid step and take profit

input group "=== Sell Grid Settings ==="
input bool EnableSellGrid = true;               // Enable sell grid
input double SellUpperLimit = 148;              // Sell grid upper limit price
input double SellLowerLimit = 144.7;            // Sell grid lower limit price
input double SellGridStep = 0.05;               // Sell grid step and take profit

input group "=== Order Settings ==="
input int MaxStopOrders = 2;                    // Maximum stop orders per side (buy/sell)
input int MaxLimitOrders = 2;                   // Maximum limit orders per side (buy/sell)

input group "=== Trading Time Settings ==="
input string TradingStartTime = "23:00";        // Trading start time (HH:MM)
input string TradingEndTime = "20:30";          // Trading end time (HH:MM)

//--- Grid level management structure
struct GridLevel
{
   double price;
   bool hasOrder;
   bool hasPosition;
   ulong orderTicket;
   ulong positionTicket;
};

//--- Enumerations
enum ENUM_GRID_TYPE
{
   GRID_TYPE_BUY,
   GRID_TYPE_SELL
};

enum ENUM_ORDER_ZONE
{
   ORDER_ZONE_STOP,
   ORDER_ZONE_LIMIT,
   ORDER_ZONE_OUTSIDE
};

//--- Global variables
CTrade trade;
CPositionInfo positionInfo;
COrderInfo orderInfo;

//--- Grid arrays
GridLevel buyGridLevels[];
GridLevel sellGridLevels[];

//--- State variables
datetime lastCandleTime = 0;
int startHour = 9;
int startMinute = 0;
int endHour = 17;
int endMinute = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize trade class
   if(!InitializeTrade())
   {
      Print("Failed to initialize trade class");
      return(INIT_FAILED);
   }
   
   // Parse and validate trading time settings
   if(!ParseAndValidateTradingTimes())
   {
      Print("Failed to parse trading times");
      return(INIT_FAILED);
   }
   
   // Initialize grid system
   if(!InitializeGridSystem())
   {
      Print("Failed to initialize grid system");
      return(INIT_FAILED);
   }
   
   Print("GridTrading EA initialized successfully");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{   
   Print("GridTrading EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new candle confirmation
   if(!IsNewCandle())
      return;
   
   // Handle trading hours
   if(!IsWithinTradingHours())
   {
      HandleOutsideTradingHours();
      return;
   }
   
   // Execute grid management
   ExecuteGridManagement();
}

//+------------------------------------------------------------------+
//| Check if new candle is confirmed                                 |
//+------------------------------------------------------------------+
bool IsNewCandle()
{
   datetime currentCandleTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   if(lastCandleTime != currentCandleTime)
   {
      lastCandleTime = currentCandleTime;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Parse trading time settings                                      |
//+------------------------------------------------------------------+
bool ParseTradingTimes()
{
   // Parse start time
   string startParts[];
   if(StringSplit(TradingStartTime, ':', startParts) == 2)
   {
      startHour = (int)StringToInteger(startParts[0]);
      startMinute = (int)StringToInteger(startParts[1]);
   }
   else
   {
      Print("Invalid start time format. Using default 09:00");
      startHour = 9;
      startMinute = 0;
   }
   
   // Parse end time
   string endParts[];
   if(StringSplit(TradingEndTime, ':', endParts) == 2)
   {
      endHour = (int)StringToInteger(endParts[0]);
      endMinute = (int)StringToInteger(endParts[1]);
   }
   else
   {
      Print("Invalid end time format. Using default 17:00");
      endHour = 17;
      endMinute = 0;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                   |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);
   
   int currentMinutes = currentTime.hour * 60 + currentTime.min;
   int startMinutes = startHour * 60 + startMinute;
   int endMinutes = endHour * 60 + endMinute;
   
   // Handle case where trading hours span midnight
   if(startMinutes <= endMinutes)
   {
      // Normal case: start and end on same day
      return (currentMinutes >= startMinutes && currentMinutes <= endMinutes);
   }
   else
   {
      // Trading hours span midnight
      return (currentMinutes >= startMinutes || currentMinutes <= endMinutes);
   }
}

//+------------------------------------------------------------------+
//| Initialize grid levels                                           |
//+------------------------------------------------------------------+
void InitializeGridLevels()
{
   InitializeGridLevelsForType(GRID_TYPE_BUY);
   InitializeGridLevelsForType(GRID_TYPE_SELL);
}

//+------------------------------------------------------------------+
//| Initialize grid levels for specific type                        |
//+------------------------------------------------------------------+
void InitializeGridLevelsForType(ENUM_GRID_TYPE gridType)
{
   if(gridType == GRID_TYPE_BUY && !EnableBuyGrid)
      return;
   if(gridType == GRID_TYPE_SELL && !EnableSellGrid)
      return;
   
   double upperLimit = (gridType == GRID_TYPE_BUY) ? BuyUpperLimit : SellUpperLimit;
   double lowerLimit = (gridType == GRID_TYPE_BUY) ? BuyLowerLimit : SellLowerLimit;
   double gridStep = GetGridStep(gridType);
   
   int levels = (int)((upperLimit - lowerLimit) / gridStep) + 1;
   
   if(gridType == GRID_TYPE_BUY)
   {
      ArrayResize(buyGridLevels, levels);
      for(int i = 0; i < levels; i++)
         InitializeGridLevel(buyGridLevels[i], lowerLimit + (i * gridStep));
   }
   else
   {
      ArrayResize(sellGridLevels, levels);
      for(int i = 0; i < levels; i++)
         InitializeGridLevel(sellGridLevels[i], lowerLimit + (i * gridStep));
   }
}

//+------------------------------------------------------------------+
//| Initialize single grid level                                    |
//+------------------------------------------------------------------+
void InitializeGridLevel(GridLevel& level, double price)
{
   level.price = NormalizeDouble(price, Digits() - 1);
   level.hasOrder = false;
   level.hasPosition = false;
   level.orderTicket = INVALID_TICKET;
   level.positionTicket = INVALID_TICKET;
}



//+------------------------------------------------------------------+
//| Initialize trade class                                           |
//+------------------------------------------------------------------+
bool InitializeTrade()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(DEVIATION_POINTS);
   return true;
}

//+------------------------------------------------------------------+
//| Parse and validate trading times                                 |
//+------------------------------------------------------------------+
bool ParseAndValidateTradingTimes()
{
   if(!ParseTradingTimes())
   {
      Print("Failed to parse trading times");
      return false;
   }
   
   Print("Trading hours set: ", IntegerToString(startHour, 2, '0'), ":", 
         IntegerToString(startMinute, 2, '0'), " - ", 
         IntegerToString(endHour, 2, '0'), ":", 
         IntegerToString(endMinute, 2, '0'));
   
   return true;
}

//+------------------------------------------------------------------+
//| Initialize grid system                                           |
//+------------------------------------------------------------------+
bool InitializeGridSystem()
{
   // Cancel all existing pending orders
   CancelAllPendingOrders();
   
   // Initialize grid levels
   InitializeGridLevels();
   
   // Scan existing positions
   ScanExistingPositions();
   
   return true;
}

//+------------------------------------------------------------------+
//| Handle outside trading hours                                     |
//+------------------------------------------------------------------+
void HandleOutsideTradingHours()
{
   static bool outsideHoursMessageShown = false;
   
   if(!outsideHoursMessageShown)
   {
      Print("Outside trading hours - cancelling all pending orders");
      outsideHoursMessageShown = true;
   }
   
   CancelAllPendingOrders();
}

//+------------------------------------------------------------------+
//| Execute grid management                                          |
//+------------------------------------------------------------------+
void ExecuteGridManagement()
{
   if(EnableBuyGrid)
      ManageGrid(GRID_TYPE_BUY);
   
   if(EnableSellGrid)
      ManageGrid(GRID_TYPE_SELL);
}

//+------------------------------------------------------------------+
//| Unified grid management function                                 |
//+------------------------------------------------------------------+
void ManageGrid(ENUM_GRID_TYPE gridType)
{
   int gridSize = (gridType == GRID_TYPE_BUY) ? ArraySize(buyGridLevels) : ArraySize(sellGridLevels);
   
   if(gridSize == 0)
      return;
   
   double currentPrice = GetCurrentPrice(gridType);
   double gridStep = GetGridStep(gridType);
   
   // Calculate price limits
   double stopLimit, limitLimit;
   CalculatePriceLimits(currentPrice, gridType, stopLimit, limitLimit);
   
   // Cancel orders outside range
   CancelOrdersOutsideRange(gridType, gridSize, currentPrice, stopLimit, limitLimit);
   
   // Count existing orders
   int stopCount, limitCount;
   CountExistingOrders(gridType, gridSize, currentPrice, stopLimit, limitLimit, stopCount, limitCount);
   
   // Place new orders
   PlaceNewOrders(gridType, gridSize, currentPrice, stopLimit, limitLimit, stopCount, limitCount);
}

//+------------------------------------------------------------------+
//| Trade event processing                                           |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                       const MqlTradeRequest& request,
                       const MqlTradeResult& result)
{
   if(trans.symbol != _Symbol)
      return;
   
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      HandleTradeTransaction(trans);
   }
}

//+------------------------------------------------------------------+
//| Handle trade transaction                                         |
//+------------------------------------------------------------------+
void HandleTradeTransaction(const MqlTradeTransaction& trans)
{
   // Handle position closure
   if(trans.position != 0)
   {
      if(HandlePositionClosure(trans, GRID_TYPE_BUY) || 
         HandlePositionClosure(trans, GRID_TYPE_SELL))
         return;
   }
   
   // Handle order execution
   HandleOrderExecution(trans, GRID_TYPE_BUY);
   HandleOrderExecution(trans, GRID_TYPE_SELL);
}

//+------------------------------------------------------------------+
//| Handle position closure                                          |
//+------------------------------------------------------------------+
bool HandlePositionClosure(const MqlTradeTransaction& trans, ENUM_GRID_TYPE gridType)
{
   int gridSize = (gridType == GRID_TYPE_BUY) ? ArraySize(buyGridLevels) : ArraySize(sellGridLevels);
   
   for(int i = 0; i < gridSize; i++)
   {
      bool hasPosition;
      ulong positionTicket;
      double gridPrice;
      
      if(gridType == GRID_TYPE_BUY)
      {
         hasPosition = buyGridLevels[i].hasPosition;
         positionTicket = buyGridLevels[i].positionTicket;
         gridPrice = buyGridLevels[i].price;
      }
      else
      {
         hasPosition = sellGridLevels[i].hasPosition;
         positionTicket = sellGridLevels[i].positionTicket;
         gridPrice = sellGridLevels[i].price;
      }
      
      if(hasPosition && positionTicket == trans.position)
      {
         // Clear position data
         if(gridType == GRID_TYPE_BUY)
         {
            buyGridLevels[i].hasPosition = false;
            buyGridLevels[i].positionTicket = INVALID_TICKET;
         }
         else
         {
            sellGridLevels[i].hasPosition = false;
            sellGridLevels[i].positionTicket = INVALID_TICKET;
         }
         
         Print((gridType == GRID_TYPE_BUY) ? "Buy" : "Sell", " position closed at grid level ", i, 
               " Position ticket: ", trans.position, " Deal type: ", EnumToString(trans.deal_type), 
               " Price: ", trans.price);
         
         // Place new order if within trading hours
         if(IsWithinTradingHours())
         {
            PlaceReplacementOrder(gridPrice, i, gridType);
         }
         
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Handle order execution                                           |
//+------------------------------------------------------------------+
void HandleOrderExecution(const MqlTradeTransaction& trans, ENUM_GRID_TYPE gridType)
{
   int gridSize = (gridType == GRID_TYPE_BUY) ? ArraySize(buyGridLevels) : ArraySize(sellGridLevels);
   
   for(int i = 0; i < gridSize; i++)
   {
      ulong orderTicket = (gridType == GRID_TYPE_BUY) ? buyGridLevels[i].orderTicket : sellGridLevels[i].orderTicket;
      
      if(orderTicket == trans.order)
      {
         if(gridType == GRID_TYPE_BUY)
         {
            buyGridLevels[i].hasOrder = false;
            buyGridLevels[i].hasPosition = true;
            buyGridLevels[i].positionTicket = trans.position;
            buyGridLevels[i].orderTicket = INVALID_TICKET;
         }
         else
         {
            sellGridLevels[i].hasOrder = false;
            sellGridLevels[i].hasPosition = true;
            sellGridLevels[i].positionTicket = trans.position;
            sellGridLevels[i].orderTicket = INVALID_TICKET;
         }
         
         Print((gridType == GRID_TYPE_BUY) ? "Buy" : "Sell", " order filled at grid level ", i, 
               " Position ticket: ", trans.position);
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Place replacement order after position closure                  |
//+------------------------------------------------------------------+
void PlaceReplacementOrder(double gridPrice, int gridIndex, ENUM_GRID_TYPE gridType)
{
   if((gridType == GRID_TYPE_BUY && !EnableBuyGrid) || 
      (gridType == GRID_TYPE_SELL && !EnableSellGrid))
      return;
   
   double currentPrice = GetCurrentPrice(gridType);
   ENUM_ORDER_ZONE zone = GetOrderZone(gridPrice, currentPrice, gridType);
   
   if(zone == ORDER_ZONE_STOP)
      PlaceStopOrder(gridPrice, gridIndex, gridType);
   else if(zone == ORDER_ZONE_LIMIT)
      PlaceLimitOrder(gridPrice, gridIndex, gridType);
}

//+------------------------------------------------------------------+
//| Scan existing positions and update grid arrays                  |
//+------------------------------------------------------------------+
void ScanExistingPositions()
{
   ScanExistingPositionsForType(GRID_TYPE_BUY);
   ScanExistingPositionsForType(GRID_TYPE_SELL);
   
   Print("Existing positions scan and order cleanup completed");
}

//+------------------------------------------------------------------+
//| Scan existing positions for specific grid type                  |
//+------------------------------------------------------------------+
void ScanExistingPositionsForType(ENUM_GRID_TYPE gridType)
{
   if((gridType == GRID_TYPE_BUY && !EnableBuyGrid) || 
      (gridType == GRID_TYPE_SELL && !EnableSellGrid))
      return;
   
   int gridSize = (gridType == GRID_TYPE_BUY) ? ArraySize(buyGridLevels) : ArraySize(sellGridLevels);
   ENUM_POSITION_TYPE posType = (gridType == GRID_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   double gridStep = GetGridStep(gridType);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!positionInfo.SelectByIndex(i))
         continue;
      
      if(positionInfo.Symbol() != _Symbol || 
         positionInfo.Magic() != MagicNumber ||
         positionInfo.PositionType() != posType)
         continue;
      
      double openPrice = positionInfo.PriceOpen();
      ulong positionTicket = positionInfo.Ticket();
      
      // Find corresponding grid level
      int gridIndex = FindGridLevelByPrice(gridType, gridSize, openPrice, gridStep);
      if(gridIndex >= 0)
      {
         if(gridType == GRID_TYPE_BUY)
         {
            buyGridLevels[gridIndex].hasPosition = true;
            buyGridLevels[gridIndex].positionTicket = positionTicket;
            buyGridLevels[gridIndex].hasOrder = false;
            buyGridLevels[gridIndex].orderTicket = INVALID_TICKET;
         }
         else
         {
            sellGridLevels[gridIndex].hasPosition = true;
            sellGridLevels[gridIndex].positionTicket = positionTicket;
            sellGridLevels[gridIndex].hasOrder = false;
            sellGridLevels[gridIndex].orderTicket = INVALID_TICKET;
         }
         
         Print("Found existing ", (gridType == GRID_TYPE_BUY) ? "buy" : "sell", 
               " position at grid level ", gridIndex, " Price: ", openPrice, 
               " Ticket: ", positionTicket);
      }
   }
}

//+------------------------------------------------------------------+
//| Find grid level index for given price                           |
//+------------------------------------------------------------------+
int FindGridLevelByPrice(ENUM_GRID_TYPE gridType, int gridSize, double price, double gridStep)
{
   for(int i = 0; i < gridSize; i++)
   {
      double gridPrice = (gridType == GRID_TYPE_BUY) ? buyGridLevels[i].price : sellGridLevels[i].price;
      
      if(MathAbs(gridPrice - price) < gridStep * PRICE_TOLERANCE)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Find grid level index for given price (legacy function)         |
//+------------------------------------------------------------------+
int FindGridLevel(GridLevel& gridLevels[], int gridSize, double price, double gridStep)
{
   for(int i = 0; i < gridSize; i++)
   {
      if(MathAbs(gridLevels[i].price - price) < gridStep * PRICE_TOLERANCE)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Cancel all existing pending orders                              |
//+------------------------------------------------------------------+
void CancelAllPendingOrders()
{
   int cancelledCount = 0;
   
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!orderInfo.SelectByIndex(i))
         continue;
      
      if(orderInfo.Symbol() != _Symbol || orderInfo.Magic() != MagicNumber)
         continue;
      
      ulong orderTicket = orderInfo.Ticket();
      
      if(trade.OrderDelete(orderTicket))
      {
         Print("Cancelled existing order - Ticket: ", orderTicket, 
               " Price: ", orderInfo.PriceOpen(), 
               " Type: ", EnumToString(orderInfo.OrderType()));
         
         UpdateGridArraysAfterCancellation(orderTicket);
         cancelledCount++;
      }
      else
      {
         Print("Failed to cancel existing order - Ticket: ", orderTicket, 
               " Error: ", GetLastError());
      }
   }
   
   if(cancelledCount > 0)
      Print("Cancelled ", cancelledCount, " pending orders");
}

//+------------------------------------------------------------------+
//| Update grid arrays after order cancellation                     |
//+------------------------------------------------------------------+
void UpdateGridArraysAfterCancellation(ulong orderTicket)
{
   // Update buy grid levels
   if(UpdateGridArrayForCancellation(buyGridLevels, ArraySize(buyGridLevels), orderTicket, "buy"))
      return;
   
   // Update sell grid levels
   UpdateGridArrayForCancellation(sellGridLevels, ArraySize(sellGridLevels), orderTicket, "sell");
}

//+------------------------------------------------------------------+
//| Update specific grid array after cancellation                   |
//+------------------------------------------------------------------+
bool UpdateGridArrayForCancellation(GridLevel& gridLevels[], int gridSize, ulong orderTicket, string gridType)
{
   for(int i = 0; i < gridSize; i++)
   {
      if(gridLevels[i].orderTicket == orderTicket)
      {
         gridLevels[i].hasOrder = false;
         gridLevels[i].orderTicket = INVALID_TICKET;
         Print("Updated ", gridType, " grid level ", i, " - order cancelled");
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get current price for grid type                                 |
//+------------------------------------------------------------------+
double GetCurrentPrice(ENUM_GRID_TYPE gridType)
{
   return (gridType == GRID_TYPE_BUY) ? 
          SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
          SymbolInfoDouble(_Symbol, SYMBOL_ASK);
}

//+------------------------------------------------------------------+
//| Get grid step for grid type                                     |
//+------------------------------------------------------------------+
double GetGridStep(ENUM_GRID_TYPE gridType)
{
   return (gridType == GRID_TYPE_BUY) ? BuyGridStep : SellGridStep;
}

//+------------------------------------------------------------------+
//| Calculate price limits for order placement                      |
//+------------------------------------------------------------------+
void CalculatePriceLimits(double currentPrice, ENUM_GRID_TYPE gridType, 
                         double& stopLimit, double& limitLimit)
{
   double gridStep = GetGridStep(gridType);
   
   if(gridType == GRID_TYPE_BUY)
   {
      stopLimit = currentPrice + (MaxStopOrders * gridStep);
      limitLimit = currentPrice - (MaxLimitOrders * gridStep);
   }
   else
   {
      stopLimit = currentPrice - (MaxStopOrders * gridStep);
      limitLimit = currentPrice + (MaxLimitOrders * gridStep);
   }
}

//+------------------------------------------------------------------+
//| Cancel orders outside price range                               |
//+------------------------------------------------------------------+
void CancelOrdersOutsideRange(ENUM_GRID_TYPE gridType, int gridSize, double currentPrice, 
                             double stopLimit, double limitLimit)
{
   for(int i = 0; i < gridSize; i++)
   {
      if(gridType == GRID_TYPE_BUY)
      {
         if(!buyGridLevels[i].hasOrder)
            continue;
         
         if(ShouldCancelOrder(buyGridLevels[i].price, currentPrice, gridType, stopLimit, limitLimit))
         {
            CancelGridOrder(buyGridLevels[i], i, gridType);
         }
      }
      else
      {
         if(!sellGridLevels[i].hasOrder)
            continue;
         
         if(ShouldCancelOrder(sellGridLevels[i].price, currentPrice, gridType, stopLimit, limitLimit))
         {
            CancelGridOrder(sellGridLevels[i], i, gridType);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if order should be cancelled                              |
//+------------------------------------------------------------------+
bool ShouldCancelOrder(double gridPrice, double currentPrice, ENUM_GRID_TYPE gridType,
                      double stopLimit, double limitLimit)
{
   ENUM_ORDER_ZONE zone = GetOrderZone(gridPrice, currentPrice, gridType);
   
   switch(zone)
   {
      case ORDER_ZONE_STOP:
         return (gridType == GRID_TYPE_BUY) ? (gridPrice > stopLimit) : (gridPrice < stopLimit);
      case ORDER_ZONE_LIMIT:
         return (gridType == GRID_TYPE_BUY) ? (gridPrice < limitLimit) : (gridPrice > limitLimit);
      default:
         return false;
   }
}

//+------------------------------------------------------------------+
//| Get order zone based on price relationship                      |
//+------------------------------------------------------------------+
ENUM_ORDER_ZONE GetOrderZone(double gridPrice, double currentPrice, ENUM_GRID_TYPE gridType)
{
   if(gridType == GRID_TYPE_BUY)
   {
      return (currentPrice < gridPrice) ? ORDER_ZONE_STOP : ORDER_ZONE_LIMIT;
   }
   else
   {
      return (currentPrice > gridPrice) ? ORDER_ZONE_STOP : ORDER_ZONE_LIMIT;
   }
}

//+------------------------------------------------------------------+
//| Cancel specific grid order                                      |
//+------------------------------------------------------------------+
void CancelGridOrder(GridLevel& gridLevel, int gridIndex, ENUM_GRID_TYPE gridType)
{
   if(trade.OrderDelete(gridLevel.orderTicket))
   {
      Print("Cancelled ", (gridType == GRID_TYPE_BUY) ? "buy" : "sell", 
            " order outside price range - Grid level: ", gridIndex, 
            " Price: ", gridLevel.price, " Ticket: ", gridLevel.orderTicket);
      
      gridLevel.hasOrder = false;
      gridLevel.orderTicket = INVALID_TICKET;
   }
   else
   {
      Print("Failed to cancel ", (gridType == GRID_TYPE_BUY) ? "buy" : "sell", 
            " order - Grid level: ", gridIndex, " Ticket: ", gridLevel.orderTicket, 
            " Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Count existing orders in price range                            |
//+------------------------------------------------------------------+
void CountExistingOrders(ENUM_GRID_TYPE gridType, int gridSize, double currentPrice, 
                        double stopLimit, double limitLimit, int& stopCount, int& limitCount)
{
   stopCount = 0;
   limitCount = 0;
   
   for(int i = 0; i < gridSize; i++)
   {
      double gridPrice;
      bool hasOrder;
      
      if(gridType == GRID_TYPE_BUY)
      {
         hasOrder = buyGridLevels[i].hasOrder;
         gridPrice = buyGridLevels[i].price;
      }
      else
      {
         hasOrder = sellGridLevels[i].hasOrder;
         gridPrice = sellGridLevels[i].price;
      }
      
      if(!hasOrder)
         continue;
      
      ENUM_ORDER_ZONE zone = GetOrderZone(gridPrice, currentPrice, gridType);
      
      if(zone == ORDER_ZONE_STOP && IsWithinStopRange(gridPrice, currentPrice, gridType, stopLimit))
         stopCount++;
      else if(zone == ORDER_ZONE_LIMIT && IsWithinLimitRange(gridPrice, currentPrice, gridType, limitLimit))
         limitCount++;
   }
}

//+------------------------------------------------------------------+
//| Check if price is within stop range                             |
//+------------------------------------------------------------------+
bool IsWithinStopRange(double gridPrice, double currentPrice, ENUM_GRID_TYPE gridType, double stopLimit)
{
   if(gridType == GRID_TYPE_BUY)
      return (currentPrice < gridPrice && gridPrice <= stopLimit);
   else
      return (currentPrice > gridPrice && gridPrice >= stopLimit);
}

//+------------------------------------------------------------------+
//| Check if price is within limit range                            |
//+------------------------------------------------------------------+
bool IsWithinLimitRange(double gridPrice, double currentPrice, ENUM_GRID_TYPE gridType, double limitLimit)
{
   if(gridType == GRID_TYPE_BUY)
      return (currentPrice >= gridPrice && gridPrice >= limitLimit);
   else
      return (currentPrice <= gridPrice && gridPrice <= limitLimit);
}

//+------------------------------------------------------------------+
//| Place new orders within range                                   |
//+------------------------------------------------------------------+
void PlaceNewOrders(ENUM_GRID_TYPE gridType, int gridSize, double currentPrice, 
                   double stopLimit, double limitLimit, int stopCount, int limitCount)
{
   for(int i = 0; i < gridSize; i++)
   {
      bool hasOrder, hasPosition;
      double gridPrice;
      
      if(gridType == GRID_TYPE_BUY)
      {
         hasOrder = buyGridLevels[i].hasOrder;
         hasPosition = buyGridLevels[i].hasPosition;
         gridPrice = buyGridLevels[i].price;
      }
      else
      {
         hasOrder = sellGridLevels[i].hasOrder;
         hasPosition = sellGridLevels[i].hasPosition;
         gridPrice = sellGridLevels[i].price;
      }
      
      if(hasOrder || hasPosition)
         continue;
      
      ENUM_ORDER_ZONE zone = GetOrderZone(gridPrice, currentPrice, gridType);
      
      if(zone == ORDER_ZONE_STOP && 
         IsWithinStopRange(gridPrice, currentPrice, gridType, stopLimit) && 
         stopCount < MaxStopOrders)
      {
         if(PlaceStopOrder(gridPrice, i, gridType))
            stopCount++;
      }
      else if(zone == ORDER_ZONE_LIMIT && 
              IsWithinLimitRange(gridPrice, currentPrice, gridType, limitLimit) && 
              limitCount < MaxLimitOrders)
      {
         if(PlaceLimitOrder(gridPrice, i, gridType))
            limitCount++;
      }
   }
}

//+------------------------------------------------------------------+
//| Place stop order (unified function)                             |
//+------------------------------------------------------------------+
bool PlaceStopOrder(double price, int gridIndex, ENUM_GRID_TYPE gridType)
{
   double sl = 0;
   double tp = CalculateTakeProfit(price, gridType);
   bool success = false;
   
   if(gridType == GRID_TYPE_BUY)
   {
      success = trade.BuyStop(LotSize, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, Comment);
      if(success)
         buyGridLevels[gridIndex].orderTicket = trade.ResultOrder();
   }
   else
   {
      success = trade.SellStop(LotSize, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, Comment);
      if(success)
         sellGridLevels[gridIndex].orderTicket = trade.ResultOrder();
   }
   
   if(success)
   {
      if(gridType == GRID_TYPE_BUY)
         buyGridLevels[gridIndex].hasOrder = true;
      else
         sellGridLevels[gridIndex].hasOrder = true;
      
      Print((gridType == GRID_TYPE_BUY) ? "Buy" : "Sell", " stop order placed at ", price, 
            " TP: ", tp, " Ticket: ", trade.ResultOrder());
   }
   else
   {
      Print("Failed to place ", (gridType == GRID_TYPE_BUY) ? "buy" : "sell", 
            " stop order at ", price, " Error: ", GetLastError());
   }
   
   return success;
}

//+------------------------------------------------------------------+
//| Place limit order (unified function)                            |
//+------------------------------------------------------------------+
bool PlaceLimitOrder(double price, int gridIndex, ENUM_GRID_TYPE gridType)
{
   double sl = 0;
   double tp = CalculateTakeProfit(price, gridType);
   bool success = false;
   
   if(gridType == GRID_TYPE_BUY)
   {
      success = trade.BuyLimit(LotSize, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, Comment);
      if(success)
         buyGridLevels[gridIndex].orderTicket = trade.ResultOrder();
   }
   else
   {
      success = trade.SellLimit(LotSize, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, Comment);
      if(success)
         sellGridLevels[gridIndex].orderTicket = trade.ResultOrder();
   }
   
   if(success)
   {
      if(gridType == GRID_TYPE_BUY)
         buyGridLevels[gridIndex].hasOrder = true;
      else
         sellGridLevels[gridIndex].hasOrder = true;
      
      Print((gridType == GRID_TYPE_BUY) ? "Buy" : "Sell", " limit order placed at ", price, 
            " TP: ", tp, " Ticket: ", trade.ResultOrder());
   }
   else
   {
      Print("Failed to place ", (gridType == GRID_TYPE_BUY) ? "buy" : "sell", 
            " limit order at ", price, " Error: ", GetLastError());
   }
   
   return success;
}

//+------------------------------------------------------------------+
//| Calculate take profit price                                     |
//+------------------------------------------------------------------+
double CalculateTakeProfit(double price, ENUM_GRID_TYPE gridType)
{
   double gridStep = GetGridStep(gridType);
   
   if(gridType == GRID_TYPE_BUY)
      return NormalizeDouble(price + gridStep, Digits() - 1);
   else
      return NormalizeDouble(price - gridStep, Digits() - 1);
}