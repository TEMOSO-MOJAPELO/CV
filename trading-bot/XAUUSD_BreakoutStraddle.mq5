//+------------------------------------------------------------------+
//|                                    XAUUSD_BreakoutStraddle.mq5    |
//|                  Breakout straddle EA for XAUUSD (Gold)           |
//|                  Built for JustMarkets MT5, $10 cent accounts     |
//+------------------------------------------------------------------+
//
//  WHAT IT DOES
//  ------------
//  1. Measures a recent price "range" (high/low of the last N closed bars).
//  2. Places a BUY STOP just above the range and a SELL STOP just below it.
//  3. Whichever side breaks out first triggers; the opposite pending order
//     is immediately deleted (OCO - one cancels the other).
//  4. Every trade gets a Stop Loss and a Take Profit. TP is larger than SL
//     (configurable reward:risk) so winners pay for more than one loss.
//  5. Once price moves a few points in your favor, the stop is pushed to
//     break-even + a small locked profit, then trailed to "stretch" profits.
//
//  OVER-TRADING CONTROLS
//  ---------------------
//  - Max setups per day, an optional trading-hours window, a spread filter,
//    and min/max range filters all reduce the number of trades taken.
//  - Pending orders expire if the breakout does not happen within X minutes.
//
//  IMPORTANT - POINTS vs DOLLARS ON GOLD
//  -------------------------------------
//  Distances below are in PRICE POINTS (SYMBOL_POINT). On a typical
//  2-decimal Gold feed 1 point = 0.01 USD of price, so:
//        100 points  = $1.00 of price movement
//       1000 points  = $10.00 of price movement
//  The EA auto-detects the point size, so it also works on 3-decimal feeds.
//
//  RISK  (READ THIS FOR A $10 ACCOUNT)
//  -----------------------------------
//  Default sizing is RISK-BASED: it computes the lot size from your chosen
//  % of balance and the SL distance. On a tiny $10 balance this matters a lot:
//
//   * STANDARD account: the smallest lot (0.01) already risks ~$1 per $1 of
//     gold movement, so a normal breakout stop would risk most of a $10
//     account in ONE trade. A $10 standard gold account cannot be sized
//     sensibly - it WILL be over-risked. Do not run this there.
//
//   * CENT account (recommended for $10 on JustMarkets): your $10 shows as
//     1000 cents and lots are 1/100 the size, so risk-% sizing produces a
//     genuinely small per-trade risk. The EA reads balance + tick value
//     directly, so the maths is automatically correct on a cent account.
//
//  Trading XAUUSD on 1:3000 leverage is high risk. Forward-test on DEMO first.
//+------------------------------------------------------------------+
#property copyright "Generated for Temoso Mojapelo"
#property version   "1.00"
#property strict
#property description "Buy-Stop / Sell-Stop breakout straddle for XAUUSD with OCO, breakeven and trailing."

#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>

//==================================================================
//                          INPUTS
//==================================================================
enum ENUM_RISK_MODE
  {
   RISK_FIXED_LOT = 0,   // Fixed lot size
   RISK_PERCENT   = 1    // Risk % of balance per trade
  };

input group "=== General ==="
input long           InpMagic          = 990200;     // Magic number (unique per chart)
input string         InpComment        = "XAU_Breakout"; // Order comment
input ulong          InpSlippage       = 30;         // Max slippage / deviation (points)

input group "=== Position sizing / risk ==="
input ENUM_RISK_MODE InpRiskMode       = RISK_PERCENT; // Sizing method
input double         InpFixedLot       = 0.01;       // Fixed lot (if RISK_FIXED_LOT)
input double         InpRiskPercent    = 1.0;        // Risk % of balance (if RISK_PERCENT)

input group "=== Breakout range ==="
input int            InpRangeBars      = 12;         // Bars used to measure the range
input int            InpBufferPoints   = 150;        // Buffer above/below range for entries (points)
input int            InpMinRangePoints = 400;        // Skip if range smaller than this (points)
input int            InpMaxRangePoints = 6000;       // Skip if range larger than this (points)
input int            InpMaxSpreadPoints= 50;         // Skip if spread wider than this (points)

input group "=== Stops & target ==="
input int            InpStopLossPoints = 1000;       // Stop Loss distance from entry (points)
input int            InpTakeProfitPts  = 0;          // Take Profit distance (points). 0 = use R:R below
input double         InpRewardRisk     = 2.0;        // Reward:Risk used when TP points = 0

input group "=== Break-even ==="
input bool           InpUseBreakeven   = true;       // Move SL to break-even once in profit
input int            InpBE_TriggerPts  = 400;        // Profit (points) needed to arm break-even
input int            InpBE_LockPts     = 80;         // Points locked in beyond entry at break-even

input group "=== Trailing stop (stretch profits) ==="
input bool           InpUseTrailing    = true;       // Enable trailing stop
input int            InpTrailStartPts  = 800;        // Profit (points) before trailing starts
input int            InpTrailDistPts   = 500;        // Trailing distance behind price (points)
input int            InpTrailStepPts   = 50;         // Minimum step to move the trail (points)

input group "=== Pending order handling ==="
input int            InpExpiryMinutes  = 120;        // Delete untriggered pending orders after X min (0 = never)

input group "=== Over-trading controls ==="
input int            InpMaxSetupsPerDay= 1;          // Max straddle setups placed per day
input bool           InpUseTimeFilter  = true;       // Restrict setup placement to a time window
input int            InpStartHour       = 7;         // Setup window start hour (server time, 0-23)
input int            InpEndHour         = 18;        // Setup window end hour (server time, 0-23)

//==================================================================
//                       GLOBALS
//==================================================================
CTrade        trade;
CSymbolInfo   sym;

datetime      g_lastBarTime   = 0;       // for new-bar detection
int           g_setupsToday   = 0;       // straddle setups placed today
int           g_currentDay    = -1;      // day-of-year tracker for the daily reset
double        g_point         = 0.0;
int           g_digits        = 0;

//==================================================================
//                       INIT
//==================================================================
int OnInit()
  {
   if(!sym.Name(_Symbol))
     {
      Print("ERROR: cannot init symbol ", _Symbol);
      return(INIT_FAILED);
     }
   sym.Refresh();
   sym.RefreshRates();

   g_point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   // ---- input sanity checks ----
   if(InpRangeBars < 2)
     { Print("ERROR: InpRangeBars must be >= 2"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpStopLossPoints <= 0)
     { Print("ERROR: InpStopLossPoints must be > 0"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpRiskMode == RISK_PERCENT && InpRiskPercent <= 0.0)
     { Print("ERROR: InpRiskPercent must be > 0"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpRiskMode == RISK_FIXED_LOT && InpFixedLot <= 0.0)
     { Print("ERROR: InpFixedLot must be > 0"); return(INIT_PARAMETERS_INCORRECT); }

   if(StringFind(_Symbol, "XAU") < 0)
      Print("WARNING: this EA is tuned for XAUUSD but is running on ", _Symbol);

   PrintFormat("XAUUSD_BreakoutStraddle initialised. Point=%.5f Digits=%d", g_point, g_digits);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason) { }

//==================================================================
//                       MAIN TICK
//==================================================================
void OnTick()
  {
   sym.RefreshRates();

   ResetDailyCounterIfNeeded();

   // Manage anything already live (runs every tick for responsiveness)
   EnforceOCO();          // if a position opened, cancel the leftover pending
   ManageOpenPositions(); // break-even + trailing
   ExpireStalePendings(); // remove untriggered pending orders past expiry

   // Only evaluate new setups once per completed bar - cheaper and avoids noise
   if(!IsNewBar())
      return;

   TryPlaceStraddle();
  }

//==================================================================
//                  NEW-BAR / DAILY HELPERS
//==================================================================
bool IsNewBar()
  {
   datetime t = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if(t != g_lastBarTime)
     {
      g_lastBarTime = t;
      return true;
     }
   return false;
  }

void ResetDailyCounterIfNeeded()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_year != g_currentDay)
     {
      g_currentDay  = dt.day_of_year;
      g_setupsToday = 0;
     }
  }

//==================================================================
//                  COUNTING / FILTERS
//==================================================================
int CountMyPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
         n++;
     }
   return n;
  }

int CountMyPendings()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_MAGIC) == InpMagic)
         n++;
     }
   return n;
  }

//==================================================================
//                  STRADDLE PLACEMENT
//==================================================================
void TryPlaceStraddle()
  {
   // Don't add to existing exposure
   if(CountMyPositions() > 0 || CountMyPendings() > 0)
      return;

   // Daily over-trading cap
   if(InpMaxSetupsPerDay > 0 && g_setupsToday >= InpMaxSetupsPerDay)
      return;

   // Time-of-day window
   if(InpUseTimeFilter && !WithinTradingWindow())
      return;

   // Spread filter
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(InpMaxSpreadPoints > 0 && spread > InpMaxSpreadPoints)
     {
      return;
     }

   // ---- measure the range from the last N CLOSED bars (shift 1..N) ----
   int hiIdx = iHighest(_Symbol, _Period, MODE_HIGH, InpRangeBars, 1);
   int loIdx = iLowest(_Symbol, _Period, MODE_LOW,  InpRangeBars, 1);
   if(hiIdx < 0 || loIdx < 0)
      return;

   double rangeHigh = iHigh(_Symbol, _Period, hiIdx);
   double rangeLow  = iLow(_Symbol, _Period, loIdx);
   if(rangeHigh <= 0.0 || rangeLow <= 0.0)
      return;

   double rangePts = (rangeHigh - rangeLow) / g_point;
   if(rangePts < InpMinRangePoints || rangePts > InpMaxRangePoints)
      return; // range too tight (chop) or too wide (already moved) -> skip

   double buffer = InpBufferPoints * g_point;
   double buyEntry  = NormalizePrice(rangeHigh + buffer);
   double sellEntry = NormalizePrice(rangeLow  - buffer);

   // Respect broker minimum stop distance between price and pending entry
   double minStop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point;
   double ask = sym.Ask();
   double bid = sym.Bid();
   if(buyEntry - ask < minStop)  buyEntry  = NormalizePrice(ask + minStop + g_point);
   if(bid - sellEntry < minStop) sellEntry = NormalizePrice(bid - minStop - g_point);

   double slDist = InpStopLossPoints * g_point;
   double tpDist = (InpTakeProfitPts > 0)
                   ? InpTakeProfitPts * g_point
                   : InpStopLossPoints * InpRewardRisk * g_point;

   double buySL  = NormalizePrice(buyEntry  - slDist);
   double buyTP  = NormalizePrice(buyEntry  + tpDist);
   double sellSL = NormalizePrice(sellEntry + slDist);
   double sellTP = NormalizePrice(sellEntry - tpDist);

   double buyLot  = CalcLot(slDist);
   double sellLot = CalcLot(slDist);
   if(buyLot <= 0.0 || sellLot <= 0.0)
     {
      Print("Lot calculation returned 0 - check risk inputs / free margin. Setup skipped.");
      return;
     }

   datetime expiry = 0;
   ENUM_ORDER_TYPE_TIME timeType = ORDER_TIME_GTC;
   if(InpExpiryMinutes > 0)
     {
      expiry  = TimeCurrent() + InpExpiryMinutes * 60;
      timeType = ORDER_TIME_SPECIFIED;
     }
   trade.SetTypeTime(timeType);

   bool ok1 = trade.BuyStop(buyLot, buyEntry, _Symbol, buySL, buyTP, timeType, expiry, InpComment);
   bool ok2 = trade.SellStop(sellLot, sellEntry, _Symbol, sellSL, sellTP, timeType, expiry, InpComment);

   if(ok1 && ok2)
     {
      g_setupsToday++;
      PrintFormat("Straddle placed #%d/day | range=%.0f pts | BuyStop %.*f (SL %.*f TP %.*f) | SellStop %.*f (SL %.*f TP %.*f) | lot=%.2f",
                  g_setupsToday, rangePts,
                  g_digits, buyEntry,  g_digits, buySL,  g_digits, buyTP,
                  g_digits, sellEntry, g_digits, sellSL, g_digits, sellTP, buyLot);
     }
   else
     {
      // If only one leg went through, remove it so we never run a single-sided straddle
      PrintFormat("Straddle placement incomplete (buy=%s sell=%s). Cleaning up.",
                  ok1 ? "ok" : "FAIL", ok2 ? "ok" : "FAIL");
      DeleteAllMyPendings();
     }
  }

bool WithinTradingWindow()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   if(InpStartHour <= InpEndHour)
      return (h >= InpStartHour && h < InpEndHour);
   // window wraps past midnight
   return (h >= InpStartHour || h < InpEndHour);
  }

//==================================================================
//                  OCO  (one cancels the other)
//==================================================================
void EnforceOCO()
  {
   if(CountMyPositions() > 0 && CountMyPendings() > 0)
      DeleteAllMyPendings();
  }

void DeleteAllMyPendings()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_MAGIC) == InpMagic)
         trade.OrderDelete(ticket);
     }
  }

void ExpireStalePendings()
  {
   if(InpExpiryMinutes <= 0)
      return; // broker-side expiry already handles this; nothing to do
   // Broker honours ORDER_TIME_SPECIFIED, so this is a safety net only.
   datetime now = TimeCurrent();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      datetime setup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      if(now - setup >= InpExpiryMinutes * 60)
         trade.OrderDelete(ticket);
     }
  }

//==================================================================
//          BREAK-EVEN + TRAILING ON OPEN POSITIONS
//==================================================================
void ManageOpenPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      long   type  = PositionGetInteger(POSITION_TYPE);
      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      double step  = InpTrailStepPts * g_point;

      if(type == POSITION_TYPE_BUY)
        {
         double price     = sym.Bid(); // a buy is closed at the bid
         double profitPts = (price - open) / g_point;

         // For a BUY a better (tighter) stop is a HIGHER number.
         double best = curSL; // only ever raise it
         if(InpUseBreakeven && profitPts >= InpBE_TriggerPts)
            best = MathMax(best, NormalizePrice(open + InpBE_LockPts * g_point));
         if(InpUseTrailing && profitPts >= InpTrailStartPts)
            best = MathMax(best, NormalizePrice(price - InpTrailDistPts * g_point));

         // require a meaningful move and keep SL below current price
         if(best > curSL + step - g_point && best < price)
            trade.PositionModify(ticket, best, curTP);
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double price     = sym.Ask(); // a sell is closed at the ask
         double profitPts = (open - price) / g_point;

         // For a SELL a better (tighter) stop is a LOWER number.
         double best = (curSL == 0.0) ? DBL_MAX : curSL; // only ever lower it
         if(InpUseBreakeven && profitPts >= InpBE_TriggerPts)
            best = MathMin(best, NormalizePrice(open - InpBE_LockPts * g_point));
         if(InpUseTrailing && profitPts >= InpTrailStartPts)
            best = MathMin(best, NormalizePrice(price + InpTrailDistPts * g_point));

         if(best != DBL_MAX && best < curSL - step + g_point && best > price)
            trade.PositionModify(ticket, best, curTP);
        }
     }
  }

//==================================================================
//                  LOT SIZE / PRICE HELPERS
//==================================================================
double CalcLot(double slDistancePrice)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double lot = InpFixedLot;

   if(InpRiskMode == RISK_PERCENT)
     {
      double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskMoney = balance * InpRiskPercent / 100.0;

      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0.0 || tickValue <= 0.0)
         return NormalizeLot(minLot, minLot, maxLot, lotStep);

      double lossPerLot = (slDistancePrice / tickSize) * tickValue; // money lost per 1.0 lot if SL hit
      if(lossPerLot <= 0.0)
         return NormalizeLot(minLot, minLot, maxLot, lotStep);

      lot = riskMoney / lossPerLot;
     }

   lot = NormalizeLot(lot, minLot, maxLot, lotStep);

   // Final affordability check against free margin (for a buy of this size)
   double marginNeeded = 0.0;
   if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, sym.Ask(), marginNeeded))
     {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      // we open BOTH legs but only one ever fills (OCO), still keep a buffer
      if(marginNeeded > freeMargin * 0.9)
        {
         // scale down to what is affordable
         while(lot > minLot && marginNeeded > freeMargin * 0.9)
           {
            lot = NormalizeLot(lot - lotStep, minLot, maxLot, lotStep);
            if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, sym.Ask(), marginNeeded))
               break;
           }
        }
     }
   return lot;
  }

double NormalizeLot(double lot, double minLot, double maxLot, double lotStep)
  {
   if(lotStep <= 0.0) lotStep = 0.01;
   lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   return NormalizeDouble(lot, 2);
  }

double NormalizePrice(double price)
  {
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize > 0.0)
      price = MathRound(price / tickSize) * tickSize;
   return NormalizeDouble(price, g_digits);
  }
//+------------------------------------------------------------------+
