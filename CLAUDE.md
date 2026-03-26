# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MetaTrader 5 (MT5) Expert Advisor implementing a grid trading strategy in MQL5 (C++-like syntax, compiled in MT5).

## File Associations

MQL5 files (`.mq5`, `.mqh`) use C++ syntax highlighting, configured in `.vscode/settings.json`.

## Grid Trading EA Architecture

### Core Strategy

Dual-grid system with fixed outer boundaries and a dynamic active window:

- **Fixed outer boundaries**: Calculated from `GridCenterPrice` ± range pips at `OnInit()`
  - Sell grid: `GridCenterPrice` (lower) to `GridCenterPrice + SellRangePips` (upper)
  - Buy grid: `GridCenterPrice - BuyRangePips` (lower) to `GridCenterPrice` (upper)
- **Dynamic active window**: `GridRange` levels above/below `lastAskPrice`/`lastBidPrice`
- Orders are placed only within the **intersection** of fixed boundaries and the active window

### Input Parameters

| Parameter | Description |
|-----------|-------------|
| `GridStepPips` | Distance between grid levels and take profit distance (pips) |
| `GridRange` | Number of grid levels to maintain above/below reference price |
| `GridCenterPrice` | Center price dividing buy and sell grids |
| `SellEnabled` / `BuyEnabled` | Enable/disable each grid |
| `SellRangePips` / `BuyRangePips` | Grid extent from center price (pips) |
| `UseTakeProfit` | Enable/disable take profit on orders |
| `LotSize` | Order lot size |
| `MagicNumber` | EA identifier for order management |

### Integer Price System

All price calculations use integer representation for precision:
- `PriceToInt(double)`: Converts price to integer (divides by `_Point`)
- Grid calculations, comparisons, and range checks use integers
- Final prices normalized back to double via `NormalizeDouble(priceInt * pointValue, symbolDigits)`
- Tolerance for price matching: `gridStepPrice / 2`

### Order Type Logic

**Buy Orders**: `BUY_LIMIT` if grid price < current Ask; `BUY_STOP` if >= current Ask

**Sell Orders**: `SELL_LIMIT` if grid price > current Bid; `SELL_STOP` if <= current Bid

### Event Handling Flow

1. **OnTick()**: Executes only on new bar (bar time comparison)
   - Captures `lastAskPrice` / `lastBidPrice` as integers at bar open
   - Calls `UpdateGridStatus()`, then `ManageSellGrid()` / `ManageBuyGrid()`

2. **OnTrade()**: Handles position closure
   - Detects position count decrease, re-runs grid management to place replacement orders

### Key Functions

- `ManageBuyGrid(ask, bid)` / `ManageSellGrid(ask, bid)`: Place orders within active window ∩ fixed bounds; clean up out-of-range pending orders
- `UpdateGridStatus()`: Scans open positions, updates global counters and price extremes
- `CheckOrderExists(gridPrice, isBuy)`: Checks positions and pending orders at grid level (with tolerance)
- `CleanupOrders(lower, upper, isBuy, lowerPrice, upperPrice)`: Deletes pending orders outside active range or fixed bounds
- `PlaceOrder(orderType, priceInt, level, isBuy)`: Places order with optional TP
- `PriceToInt(price)`: Converts double price to integer

### Global State

```
int lastAskPrice, lastBidPrice     // Reference prices (as integers) captured on new bar
int totalBuyOrders, totalSellOrders
int highestBuyPrice, lowestBuyPrice
int highestSellPrice, lowestSellPrice
double sellLowerPrice, sellUpperPrice, buyLowerPrice, buyUpperPrice  // Fixed outer bounds
```

### Important Constants

- `DEVIATION_POINTS`: 10 points price deviation (set in `OnInit()`)
- `ORDER_FILLING_FOK`: Fill-or-Kill execution mode
- `ORDER_TIME_DAY`: Pending orders expire at end of day

## Development Notes

MQL5 files must be compiled in MetaTrader 5 (MetaEditor, F7). No standalone build system.

- Single-file implementation: `GridTrading.mq5`
- Uses `CTrade` from `<Trade\Trade.mqh>`
- Grid operations unified with `isBuy` boolean parameter
