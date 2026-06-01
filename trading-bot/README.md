# XAUUSD Breakout Straddle EA (MetaTrader 5)

A breakout bot for **Gold (XAUUSD)** built for **JustMarkets MT5**, sized for
small accounts (from **$200**) running high leverage (e.g. **1:3000**).

It places a **Buy Stop above** and a **Sell Stop below** a recent price range.
Whichever side breaks out triggers the trade; the other order is cancelled
automatically (OCO). Every trade carries a Stop Loss and a Take Profit, then the
stop is moved to **break-even + a locked profit** and **trailed** to stretch the
winner. Built-in filters keep the number of trades low to avoid over-trading.

> ⚠️ **Risk warning.** Trading XAUUSD on 1:3000 leverage is high risk. A small
> account can be wiped out quickly. This code is provided for educational use.
> **Forward-test on a DEMO account for several weeks before risking real money.**

---

## 1. How the strategy works

1. **Range** – every new bar the EA measures the high/low of the last
   `InpRangeBars` closed bars.
2. **Straddle** – it places a Buy Stop at `rangeHigh + buffer` and a Sell Stop at
   `rangeLow − buffer`.
3. **OCO** – when one side fills, the opposite pending order is deleted.
4. **Protection** – SL is fixed distance; TP is larger (default **2:1**), so one
   win covers more than one loss.
5. **Break-even** – once price is `InpBE_TriggerPts` in profit, SL jumps to
   entry **+ a small locked profit** (`InpBE_LockPts`).
6. **Trailing** – beyond `InpTrailStartPts` profit, SL trails price by
   `InpTrailDistPts` to capture extended moves.
7. **Anti-over-trading** – max setups/day, a trading-hours window, spread filter,
   range size filters, and pending-order expiry.

---

## 2. Points vs dollars on Gold (read this!)

All distances are in **price points** (`SYMBOL_POINT`). On a typical 2-decimal
gold feed **1 point = 0.01 USD** of price:

| Points | Price move |
|-------:|-----------:|
| 100    | $1.00      |
| 500    | $5.00      |
| 1000   | $10.00     |
| 2000   | $20.00     |

The EA auto-detects the point size, so it also works on 3-decimal feeds.

---

## 3. Install on JustMarkets MT5

1. In MT5: **File → Open Data Folder**.
2. Go to `MQL5/Experts/`.
3. Copy **`XAUUSD_BreakoutStraddle.mq5`** there.
4. In the **Navigator** panel, right-click **Expert Advisors → Refresh**.
5. Open the editor (F4) and **Compile** the file (no errors expected), *or* just
   drag it onto a chart and MT5 compiles it for you.
6. Open a **XAUUSD, M15** chart (M5–M30 all work; see below).
7. Drag the EA onto the chart. On the **Common** tab tick **Allow Algo Trading**.
8. Make sure the **Algo Trading** button in the toolbar is green.

> JustMarkets gold may be named `XAUUSD`, `XAUUSD.`, `GOLD`, etc. The EA works on
> whatever gold symbol the chart uses; it just prints a warning if the symbol
> name doesn't contain `XAU`.

---

## 4. Suggested settings for a $200 account

Start on **M15**. These are conservative starting points — tune with the
Strategy Tester, don't just trust them.

| Input | Suggested | Notes |
|-------|-----------|-------|
| `InpRiskMode` | `RISK_PERCENT` | sizes the lot from balance + SL distance |
| `InpRiskPercent` | `0.5`–`1.0` | 1% of $200 = **$2 risk per trade** |
| `InpRangeBars` | `12` | ~3h of range on M15 |
| `InpBufferPoints` | `150` | $1.50 beyond the range to confirm the break |
| `InpMinRangePoints` | `400` | skip dead/choppy ranges |
| `InpMaxRangePoints` | `6000` | skip if it already moved $60 |
| `InpMaxSpreadPoints` | `50` | skip news-spike spreads |
| `InpStopLossPoints` | `1000` | $10 stop |
| `InpTakeProfitPts` | `0` | use R:R below |
| `InpRewardRisk` | `2.0` | TP = $20 (2× the stop) |
| `InpBE_TriggerPts` | `400` | arm break-even after $4 in profit |
| `InpBE_LockPts` | `80` | lock ~$0.80 once at break-even |
| `InpTrailStartPts` | `800` | start trailing after $8 |
| `InpTrailDistPts` | `500` | trail $5 behind price |
| `InpMaxSetupsPerDay` | `1` | at most one straddle per day |
| `InpUseTimeFilter` | `true` | only set up during liquid hours |
| `InpStartHour` / `InpEndHour` | `7` / `18` | **server time** – adjust! |

### Why risk-based sizing matters here
With `RISK_PERCENT`, lot size = `(balance × risk%) ÷ money-lost-if-SL-hit`. So at
1% on $200 with a $10 stop the EA sizes to roughly **0.01–0.02 lots** and your
loss is capped near $2 regardless of the 1:3000 leverage. Leverage only changes
the *margin* required, not your risk per trade — that's controlled by SL + lot.

---

## 5. Tuning notes

- **Fewer trades?** Lower `InpMaxSetupsPerDay`, narrow the hours window, or raise
  `InpMinRangePoints`.
- **Bigger winners?** Raise `InpRewardRisk` (e.g. 3.0) and/or widen
  `InpTrailDistPts` so you don't get stopped on noise.
- **Break-even too early/jumpy?** Raise `InpBE_TriggerPts`.
- **Server-time hours:** MT5 server time is usually NOT your local time. Check the
  Market Watch clock and set `InpStartHour`/`InpEndHour` to cover the
  London/New-York overlap (the most reliable gold breakouts).

---

## 6. Backtest first

1. **View → Strategy Tester** (Ctrl+R).
2. Expert: `XAUUSD_BreakoutStraddle`, Symbol: your gold symbol, TF: M15.
3. Model: **Every tick based on real ticks**, deposit `200`, leverage `1:3000`.
4. Run, then check the report: profit factor, max drawdown, and number of trades.
5. Use the **optimisation** tab to sweep `InpRangeBars`, `InpBufferPoints`,
   `InpRewardRisk`, and the trailing inputs.

Then run it on a **demo account** for a few weeks before going live.

---

## 7. MetaTrader 4?

This is an MQL5 EA. If your JustMarkets terminal is **MT4**, tell me and I'll port
it to MQL4 (the order model and a few API calls differ).
