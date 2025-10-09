# Grid Trading Expert Advisor for MetaTrader 5

A dynamic grid trading Expert Advisor (EA) for MetaTrader 5 that implements separate buy and sell grids with automatic order management and take profit functionality.

## Features

- **Dual Grid System**: Independent buy and sell grids operating simultaneously
- **Dynamic Range Management**: Automatically places and removes orders based on current price movement
- **Flexible Order Types**: Automatically uses STOP or LIMIT orders depending on price position
- **Built-in Take Profit**: Each order includes automatic take profit at grid step distance
- **New Bar Execution**: Grid management executes only on new candle formation to reduce order modifications
- **Automatic Replacement**: When a position closes at take profit, a new order is automatically placed at that grid level

## Parameters

### Basic Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| `GridStepPips` | 5 | Distance between grid levels and take profit distance (in pips) |
| `LotSize` | 0.04 | Lot size for all orders |
| `GridRange` | 3 | Number of grid levels to maintain above and below the reference price |
| `MagicNumber` | 8001 | Unique identifier for this EA's orders |

### Buy Grid Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| `BuyEnabled` | true | Enable/disable buy grid |
| `BuyUpperPrice` | 147.53 | Upper price limit for buy grid |
| `BuyLowerPrice` | 143.53 | Lower price limit for buy grid |

### Sell Grid Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| `SellEnabled` | true | Enable/disable sell grid |
| `SellUpperPrice` | 151.53 | Upper price limit for sell grid |
| `SellLowerPrice` | 147.53 | Lower price limit for sell grid |

## How It Works

### Grid Placement Logic

The EA maintains a dynamic grid of orders within a configurable range around the current price:

1. **Buy Grid**:
   - Reference price: Current Ask price (captured at bar open)
   - Active range: `GridRange` levels above and below reference price
   - Orders placed at `GridStepPips` intervals within the range
   - Orders outside the active range are automatically deleted

2. **Sell Grid**:
   - Reference price: Current Bid price (captured at bar open)
   - Active range: `GridRange` levels above and below reference price
   - Orders placed at `GridStepPips` intervals within the range
   - Orders outside the active range are automatically deleted

### Order Type Selection

The EA automatically selects the appropriate order type based on current price:

- **Buy Limit**: Placed when grid price is below current Ask (buy below market)
- **Buy Stop**: Placed when grid price is at or above current Ask (buy at/above market)
- **Sell Limit**: Placed when grid price is above current Bid (sell above market)
- **Sell Stop**: Placed when grid price is at or below current Bid (sell at/below market)

### Execution Flow

1. **New Bar Detection**: The EA executes only when a new candle forms
2. **Grid Status Update**: Scans all open positions to track grid state
3. **Order Placement**: Places missing orders within the active range
4. **Order Cleanup**: Removes orders outside the active range or price limits
5. **Position Closure Handling**: When a position closes (TP hit), a replacement order is placed

## Installation

1. Copy `GridTrading.mq5` to your MetaTrader 5 `MQL5/Experts/` folder
2. Open MetaEditor (press F4 in MT5 or click MetaEditor icon)
3. Open `GridTrading.mq5` and press F7 to compile
4. Restart MetaTrader 5 or refresh the Navigator panel
5. Drag the EA from Navigator onto a chart

## Configuration

### Basic Setup

1. **Set Grid Boundaries**:
   - Define `BuyUpperPrice` and `BuyLowerPrice` for buy grid range
   - Define `SellUpperPrice` and `SellLowerPrice` for sell grid range
   - Ensure there's no overlap if you want separate grids

2. **Adjust Grid Spacing**:
   - Set `GridStepPips` based on market volatility and your strategy
   - Smaller values = denser grid, more frequent trades
   - Larger values = wider grid, fewer trades

3. **Configure Active Range**:
   - `GridRange` determines how many levels stay active around current price
   - Smaller values = tighter control, fewer pending orders
   - Larger values = wider coverage, more pending orders

### Example Configurations

**Conservative (Wide Grid)**:
```
GridStepPips = 10
GridRange = 2
LotSize = 0.01
```

**Aggressive (Dense Grid)**:
```
GridStepPips = 3
GridRange = 5
LotSize = 0.05
```

## Risk Warning

Grid trading strategies can accumulate multiple positions and may result in significant drawdown during trending markets. Key risks include:

- **Trending Markets**: Strong trends can trigger all grid orders in one direction
- **Margin Requirements**: Multiple open positions require sufficient account margin
- **Drawdown**: Unrealized losses can accumulate with multiple open positions
- **Take Profit Dependency**: Strategy relies on price retracing to hit take profit levels

**Important**:
- Always test on a demo account first
- Use appropriate lot sizes for your account balance
- Monitor margin levels regularly
- Consider using this EA in ranging or mean-reverting markets

## Testing

### Strategy Tester

1. Open Strategy Tester in MT5 (Ctrl+R)
2. Select `GridTrading` from the Expert Advisor dropdown
3. Configure test parameters (symbol, timeframe, date range)
4. Set input parameters in the "Inputs" tab
5. Run the test and analyze results

### Visual Mode

Enable "Visual mode" in Strategy Tester to watch the EA place orders and manage positions in real-time during backtesting.

## Technical Details

- **Execution Model**: New bar only (executes once per candle)
- **Order Filling**: Fill-or-Kill (FOK) mode
- **Price Deviation**: 10 points allowed for order execution
- **Position Tracking**: Uses magic number to identify EA's orders
- **Take Profit**: Automatically set to `GridStepPips` distance from entry

## Troubleshooting

### No Orders Placed

- Check that grid is enabled (`BuyEnabled`/`SellEnabled`)
- Verify upper price > lower price for each grid
- Ensure current price is within grid boundaries
- Check terminal logs for error messages

### Orders Disappearing

- Orders outside the active range are automatically deleted
- This is normal behavior when price moves away from grid levels
- Increase `GridRange` if you want more persistent orders

### Order Placement Failures

- Check account margin and free margin
- Verify lot size meets broker's minimum/maximum requirements
- Check for broker-specific order restrictions
- Review terminal logs for specific error codes

## License

This Expert Advisor is provided as-is for educational and trading purposes.

## Version History

- **v1.00**: Initial release with dynamic grid management

## Support

For issues, questions, or suggestions, please check the MetaTrader 5 terminal logs for detailed error messages and execution information.
