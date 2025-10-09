# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a MetaTrader 5 (MT5) Expert Advisor (EA) implementing a grid trading strategy. The EA is written in MQL5, which uses C++-like syntax and is compiled for the MT5 platform.

## File Associations

MQL5 files (`.mq5`, `.mqh`) use C++ syntax highlighting. This is configured in `.vscode/settings.json`.

## Grid Trading EA Architecture

### Core Strategy

The EA implements a dynamic dual-grid system with separate buy and sell grids:
- **Buy Grid**: Places buy orders between `BuyLowerPrice` and `BuyUpperPrice`
- **Sell Grid**: Places sell orders between `SellLowerPrice` and `SellUpperPrice`

The grid operates dynamically within a configurable range (`GridRange`) around the current price, placing and removing orders as price moves.

### Grid Parameters

- `GridStepPips`: Distance between grid levels and take profit distance (in pips)
- `GridRange`: Number of grid levels to maintain above and below the reference price
- Reference prices: Ask price for buy grid, Bid price for sell grid
- All orders placed at grid levels within the active range

### Integer Price System

The EA uses integer-based price calculations for precision:
- `PriceToInt(double)`: Converts double prices to integer representation (divides by point value)
- Integer arithmetic used for grid calculations and price comparisons
- Final prices normalized back to double with proper digit precision
- Tolerance for price matching: `gridStepPrice / 2`

### Dynamic Range Management

The grid maintains orders only within an active range around the current price:

**Buy Grid**:
- Reference price: Last Ask price (captured on new bar)
- Upper range: `lastAskPrice + (GridRange * gridStepPrice)`
- Lower range: `lastAskPrice - (GridRange * gridStepPrice)`
- Orders outside this range are automatically deleted

**Sell Grid**:
- Reference price: Last Bid price (captured on new bar)
- Upper range: `lastBidPrice + (GridRange * gridStepPrice)`
- Lower range: `lastBidPrice - (GridRange * gridStepPrice)`
- Orders outside this range are automatically deleted

### Order Type Logic

Orders are placed as STOP or LIMIT based on current price:

**Buy Orders**:
- `BUY_LIMIT`: Grid price < current Ask (order below market)
- `BUY_STOP`: Grid price >= current Ask (order at or above market)

**Sell Orders**:
- `SELL_LIMIT`: Grid price > current Bid (order above market)
- `SELL_STOP`: Grid price <= current Bid (order at or below market)

### Event Handling Flow

1. **OnTick()**: Executes only on new bar confirmation
   - Captures reference prices (Ask/Bid) at bar open
   - Updates grid status (counts positions, tracks price levels)
   - Manages buy and sell grids

2. **OnTrade()**: Handles position closure events
   - Detects when position count decreases
   - Updates grid status
   - Re-runs grid management to place replacement orders

### Key Functions

- `ManageBuyGrid(ask, bid)`: Manages buy grid orders within dynamic range
- `ManageSellGrid(ask, bid)`: Manages sell grid orders within dynamic range
- `UpdateGridStatus()`: Scans open positions and updates global counters
- `CheckOrderExists(gridPrice, isBuy)`: Checks if position or pending order exists at grid level
- `CleanupOrders(lower, upper, isBuy, lowerPrice, upperPrice)`: Removes orders outside active range
- `PlaceOrder(orderType, priceInt, level, isBuy)`: Generic order placement with TP
- `PriceToInt(price)`: Converts double price to integer for calculations

### Grid Status Tracking

Global variables track the current grid state:
- `totalBuyOrders` / `totalSellOrders`: Count of open positions
- `highestBuyPrice` / `lowestBuyPrice`: Price extremes for buy positions
- `highestSellPrice` / `lowestSellPrice`: Price extremes for sell positions
- `lastAskPrice` / `lastBidPrice`: Reference prices captured on new bar

## Development Notes

### Testing and Compilation

MQL5 files must be compiled in MetaTrader 5. There is no standalone build system in this repository.

To compile and test:
1. Open MetaEditor (from MT5 platform)
2. Open `GridTrading.mq5`
3. Press F7 to compile
4. Test using MT5 Strategy Tester or attach to a live/demo chart

### Code Structure

- Single-file implementation: All code is in `GridTrading.mq5`
- Uses standard MQL5 library: `CTrade` from `<Trade\Trade.mqh>`
- No custom `.mqh` header files
- Grid operations unified with boolean `isBuy` parameter to reduce code duplication

### Important Constants and Settings

- `DEVIATION_POINTS`: 10 points allowed price deviation for order execution (set in `OnInit()`)
- `ORDER_FILLING_FOK`: Fill-or-Kill execution mode
- Price tolerance: `gridStepPrice / 2` (used in `CheckOrderExists()`)
- Symbol info cached at initialization: `symbolDigits`, `symbolMinLot`, `symbolMaxLot`

### New Bar Detection

The EA uses bar time comparison to execute once per bar:
```cpp
datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
if(currentBarTime == lastBarTime) return;
lastBarTime = currentBarTime;
```

This ensures grid management runs only when a new candle forms, preventing excessive order modifications.
