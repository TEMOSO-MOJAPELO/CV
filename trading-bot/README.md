# XAUUSD Breakout Straddle EA (MetaTrader 5)

A breakout bot for **Gold (XAUUSD)** built for **JustMarkets MT5 (standard
account)**, sized for a **$10 deposit** on high leverage (e.g. **1:3000**).
Works on any chart timeframe; **M5–M15** recommended.

It places a **Buy Stop above** and a **Sell Stop below** a recent price range.
Whichever side breaks out triggers the trade; the other order is cancelled
automatically (OCO). Every trade carries a Stop Loss and a Take Profit, then the
stop is moved to **break-even + a locked profit** and **trailed** to stretch the
winner. Built-in filters keep the number of trades low to avoid over-trading.

> ⚠️ **Risk warning.** Trading XAUUSD on 1:3000 leverage is high risk. A $10
> account can be wiped out quickly. This code is provided for educational use.
> **Forward-test on a DEMO account for several weeks before risking real money.**

> 💡 **$10 on a STANDARD account:** the minimum lot (`0.01`) is the only lot you
> can trade, so your risk is controlled **only by the stop-loss distance**. The
> defaults use a tight ~$3 stop. See [§4](#4-the-10-standard-account--how-risk-works).

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

## 4. The $10 standard account — how risk works

On a **standard** account the smallest trade is `0.01` lots, where roughly
**$1 of gold movement = $1 of P/L**. With only $10 you can't go below `0.01`, so
the lot is fixed and **your risk per trade is set entirely by the stop-loss
distance**:

| Stop-loss | ≈ Risk at 0.01 lot | % of a $10 account |
|----------:|-------------------:|-------------------:|
| 300 pts ($3) — default | ~$3 | ~30% |
| 200 pts ($2) | ~$2 | ~20% |
| 500 pts ($5) | ~$5 | ~50% |

The defaults use a **tight $3 stop** and a **2:1 target (~$6)** so one winner
covers two losers, plus break-even/trailing to protect and stretch profit. Be
clear-eyed: a $10 standard gold account has very little room for a losing run —
**a few consecutive stops can end it.** Trade the smallest sensible stop, keep
`InpMaxSetupsPerDay` low, and demo-test first.

### Suggested settings ($10 standard, M5–M15)

Conservative starting points — tune in the Strategy Tester, don't just trust them.

| Input | Suggested | Notes |
|-------|-----------|-------|
| `InpRiskMode` | `RISK_FIXED_LOT` | $10 standard is pinned at the min lot anyway |
| `InpFixedLot` | `0.01` | the minimum / only realistic lot |
| `InpRangeBars` | `12` | 1h of range on M5, 3h on M15 |
| `InpBufferPoints` | `80` | $0.80 beyond the range to confirm the break |
| `InpMinRangePoints` | `150` | low enough that **M5 still triggers** |
| `InpMaxRangePoints` | `8000` | skip if it already moved $80 |
| `InpMaxSpreadPoints` | `60` | skip news-spike spreads |
| `InpStopLossPoints` | `300` | ~$3 stop (your main risk lever) |
| `InpTakeProfitPts` | `0` | use R:R below |
| `InpRewardRisk` | `2.0` | TP ≈ $6 (2× the stop) |
| `InpBE_TriggerPts` | `150` | break-even armed after ~$1.50 profit |
| `InpBE_LockPts` | `30` | lock ~$0.30 once at break-even |
| `InpTrailStartPts` | `250` | start trailing after ~$2.50 |
| `InpTrailDistPts` | `200` | trail $2 behind price |
| `InpMaxSetupsPerDay` | `1` | at most one straddle per day |
| `InpUseTimeFilter` | `true` | only set up during liquid hours |
| `InpStartHour` / `InpEndHour` | `7` / `18` | **server time** – adjust! |

### Works on any timeframe (M5–M15)
The EA reads the chart's own timeframe (`_Period`) for everything — range,
new-bar detection, entries — so **it places the straddle no matter which
timeframe you attach it to.** Lower timeframes have smaller ranges, which is why
`InpMinRangePoints` is kept low (150); if you still see no trades on M5, drop it
toward `80`. On higher timeframes you may want a wider stop (the ranges and moves
are bigger), e.g. M15 → `InpStopLossPoints` 400–600.

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
3. Model: **Every tick based on real ticks**, deposit `10`, leverage `1:3000`.
4. Run, then check the report: profit factor, max drawdown, and number of trades.
5. Use the **optimisation** tab to sweep `InpRangeBars`, `InpBufferPoints`,
   `InpRewardRisk`, and the trailing inputs.

Then run it on a **demo account** for a few weeks before going live.

---

## 7. MetaTrader 4?

This is an MQL5 EA. If your JustMarkets terminal is **MT4**, tell me and I'll port
it to MQL4 (the order model and a few API calls differ).
