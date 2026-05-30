# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MetaTrader 5 (MT5) Expert Advisor and scripts implementing a grid trading strategy in MQL5 (C++-like syntax).

**Files:**
- `GridTrading.mq5` — Main EA (grid trading)
- `ModifyTakeProfit.mq5` — EA to bulk-modify TP on open positions
- `CandleBodyAlert.mq5` — EA for candle body size alerts

MQL5 files must be compiled in MetaTrader 5 (MetaEditor, F7). No standalone build system.

## Grid Trading Architecture

### Strategy

Dual-grid system with fixed outer boundaries set at `OnInit()` from `GridCenterPrice` ± range pips:
- Sell grid: `GridCenterPrice` to `GridCenterPrice + SellRangePips`
- Buy grid: `GridCenterPrice - BuyRangePips` to `GridCenterPrice`

Orders fill every grid level within bounds. When `RangePips` is 0, `CleanupOrders` runs but no new orders are placed.

### Integer Price System

All price math uses integers (`price / _Point`) to avoid floating-point drift. Tolerance for grid level matching: `gridStepPrice / 2`. Final prices normalized back via `NormalizeDouble(priceInt * pointValue, digits)`.

`PipsToInt`: multiplies by 10 for 3/5-digit symbols, 100 otherwise.

### Event Flow

- **OnTick()**: triggers only on new bar → `RunGridManagement()`
- **OnTrade()**: triggers on position count decrease → `RunGridManagement()`
- **RunGridManagement()**: `UpdateGridStatus()` → `ManageGrid()` for each enabled grid

### Non-obvious Behaviors

- Price deviation: 10 points (hardcoded)
- Execution: `ORDER_FILLING_FOK`
- Pending orders: `ORDER_TIME_GTC`
- `cachedLotSize` is clamped to symbol min/max volume at `OnInit()`
- Buy order uses Ask; sell order uses Bid for current price comparison
