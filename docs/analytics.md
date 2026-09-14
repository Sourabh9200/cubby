# Analytics: what to build, in what order, and where it would lie to you

A plan, not a description. For what exists today, see
the [root README](../README.md) and the per-package READMEs.

**Status: Tier 0 (2.1–2.6), Tier 1 (3.1–3.8) and two of Tier 3's three screens
(5.1 Reports, 5.2 Year in review) are built** — each item below says where it landed,
and the caveat it was supposed to carry. Tier 2 needs schema work and 5.3 (the
calendar) is still a plan. The status markers below are the only part of this
document that describes shipped code.

One decision shaped all of Tier 1: **the deeper figures do not get more cards.**
The overview and trends screens were already long, so each new figure is one of
three things — a line where its question is already being asked, a tap away (a
bottom sheet, a screen of its own) or a question to the assistant. Nothing in
Tier 1 added a card to either screen. Tier 3's screens are reached the same way:
one app-bar icon on Trends for a report, one link inside a *year* report for the
review.

This document is deliberately organised **by cost, not by appeal**. Each tier is
a different kind of work:

| Tier | Kind of work | Schema change | Rough cost per item |
|------|--------------|---------------|--------------------|
| **0** | A new arrangement of figures that already exist | none | a widget and a pure function |
| **1** | New arithmetic over the same rows | none | a pure function, a card, real tests |
| **2** | Facts the ledger cannot currently express | **yes — migration** | days each, with the v3 discipline |
| **3** | A screen of its own | none | layout and navigation |

## 1. The ground this stands on

### What exists today

| Surface | Already shows |
|---------|---------------|
| **Overview** | Period selector (week/month/quarter/year) · spent · income · net · spending pace · category donut · budget bars · investment targets · biggest hits |
| **Trends** | Monthly bars · savings rate history · investing breakdown · highest/lowest month on record · income by source · month-over-month category movement |
| **Ledger** | Day subtotals · search · filter by kind · edit · delete |
| **Budgets** | Per-category limits and targets, including custom categories |
| **Reports** | Any period from a day to a year, plus a range you pick: all three totals, composition, top categories and payees, budget outcomes, and the change against the previous period · a year in review |
| **Assistant** | Four local insight intents: `budget_check`, `biggest_expense`, `comparison`, `savings_rate` |

### Why new analytics are cheap here

1. **One snapshot, one set of pure functions.** `data/period_views.dart` and
   `data/snapshot_analytics.dart` derive everything from rows already in memory.
   A new figure is a pure function plus a card plus a test — no plumbing.
2. **The period engine is already generic.** `StatsRange.containing(StatsPeriod.year, now)`
   works today, and `monthsCovered`, `step(-1)` and `elapsedFraction` are in place.
3. **One computation can land twice.** The house pattern is function → card →
   assistant intent (`comparison` reads `expenseChangeFor`, `savings_rate` reads
   `currentSavingsRate`). A new analytic therefore ships a card *and* an answer.
4. **Recurring rules unlocked forecasting.** Committed spend, upcoming dues and
   safe-to-spend all depend on knowing which outflows repeat — which the v3 work
   now records.

### The contract every new figure must meet

- **A pure function of `FinanceSnapshot`**, in `period_views.dart` (range-shaped)
  or `snapshot_analytics.dart` (history-shaped), never in a widget. Screens do not
  aggregate.
- **Tested against fake snapshots**, no database, no widget, in the style of
  `test/period_view_test.dart`.
- **One implementation.** A month-shaped and a week-shaped figure must be the same
  arithmetic over different bounds; if a monthly-only method is added, it delegates.
- **`dart format`, `flutter analyze --fatal-infos`, and the three suites green**
  (assistant / db / app), plus a device check for anything visual.
- **Docs updated in the same change**: the status bullets and counts in this repo's
  READMEs are load-bearing.
- **No invented numbers.** If the data cannot support a figure honestly, the
  correct output is "not enough history", not an estimate.

## 2. Tier 0 — a new arrangement of figures that already exist

No new arithmetic, no migration. Highest value per line of code in this document.

### 2.1 Composition of a period — *income vs investment vs expense* (the example that started this)

Answers *"where did the year go?"* — and the allocation is the whole point, not
the total. Three slices plus **unallocated** (income − expense − investment),
which is the number users actually want and no tracker shows.

- **Data:** `totalsFor(range)` already returns all three figures.
- **Surface:** Trends (period-scoped by the selector), donut or stacked bar.
- **Sketch:** `CompositionTotals` model; `compositionFor(StatsRange)` in
  `period_views.dart`; `composition_card.dart`.
- **Caveats:** C1 (investing is not spending — three slices, never "expense +
  investment"), C15 (lumpy income makes a single month's unallocated meaningless;
  lead with the quarter or year).
- **Size:** ~120 lib lines, ~200 test lines, ~8 tests (zero income, zero expense,
  income-only month, investments-only, unallocated negative when spending exceeds
  income, transfers excluded).
- **Built:** `CompositionTotals` in `data/composition.dart`, `compositionFor` in
  `data/period_views.dart`, `CompositionCard` on the **Overview** — period-scoped
  by the selector that already lives there, which is the answer to open question 6
  below: the period question belongs to the overview, history-shaped cards to
  Trends. Unallocated is `cashLeftMinor` by definition, so the card cannot
  disagree with the cash-left tile beside it.

### 2.2 Composition over time

The same three measures as stacked columns, one column per month of the period.
Shows whether investing is *growing* or merely present.

- **Data:** `monthlySummaries`, which already carries expense, income and investment.
- **Caveat:** C6 — the month in progress is partial, so its column must be marked
  as such rather than allowed to read as a collapse in saving.
- **Size:** ~140 lib lines, ~180 test lines.
- **Built:** `CompositionPoint` and `compositionByMonthIn` (one point per month,
  clipped to the range, stopping at the month in progress), drawn by
  `CompositionOverTimeCard` on **Trends**, scoped to the year in progress. A
  partial month is drawn faded *and* labelled with an asterisk, and a month that
  spent and invested more than it earned grows an orange cap rather than a pretend
  income.

### 2.3 Year over year

"This August against last August", for the same three measures.

- **Data:** `expenseChangeForRange` generalised to shift by 12 months.
- **Sketch:** `expenseChangeYearOverYear(StatsRange)`; reuse `step` where the period
  is a year, shift 12 months where it is a month.
- **Caveats:** C7 — with less than a year of history, say so rather than compare
  against a partially-covered month; C6 for the month in progress.
- **Size:** ~60 lib lines, ~120 test lines.
- **Built:** `YearOverYear` in `data/year_over_year.dart`, `yearOverYearFor` and
  `expenseChangeYearOverYear` in `data/period_views.dart`, `StatsRange.oneYearEarlier`
  (calendar arithmetic, so February stays February), and `YearOverYearCard` on
  **Trends** — the current month against the same days of the same month last
  year, all three measures shown apart. Null — "not enough history" — unless the
  whole of the year-earlier window is inside the ledger.

### 2.4 Top payees and merchant history

A category says *what* was bought; a payee says *where*. The `payee` column is
populated on every entry and **no aggregate reads it today**.

- **Data:** `transactions.payee`.
- **Surface:** Trends card ("Top places") and a payee drill-down (tap a payee, see
  its entries and its monthly series).
- **Sketch:** `topPayeesIn(StatsRange, {limit})` → `PayeeTotal` (name, total, count,
  average); `payeeSeries(String payee)`.
- **Caveats:** C8 — payee is free text, so no fuzzy merging; show the strings as
  recorded and let the user recognise their own; C9 if sample rows are in play.
- **Size:** ~130 lib lines, ~200 test lines.
- **Built:** `PayeeTotal`/`PayeeMonthTotal` in `data/payee_totals.dart`,
  `topPayeesIn`/`payeeEntries`/`payeeTotalFor`/`payeeSeries` in
  `data/period_views.dart`, `TopPayeesCard` on **Trends** (year-scoped,
  expenses only, blank payees left out rather than collected under a blank row) and
  `PayeeDetailScreen` as the drill-down — the whole recorded history for that
  name, with no merging of two spellings anywhere.

### 2.5 Spending rhythm

Day-of-week profile, a calendar heatmap, no-spend days, and average per *active*
day. Cheap, and rare in this category.

- **Data:** `transactions`, `dailySpendByMonth`.
- **Sketch:** `spendByWeekdayIn(range)`, `noSpendDaysIn(range)`,
  `dailyAverageActiveIn(range)`.
- **Caveats:** C11 — "no spend" is really "nothing recorded"; label it that way and
  never present it as a behavioural fact; C6 for partial periods.
- **Size:** ~150 lib lines, ~250 test lines.
- **Built:** `WeekdaySpend` and `SpendingRhythm` in `data/spending_rhythm.dart`,
  `spendingRhythmIn` in `data/period_views.dart`, `SpendingRhythmCard` on
  **Trends**. Each weekday carries how many of it the range covers, so a partial
  first week cannot make a Monday look quiet for free; the quiet-day figure says
  "nothing recorded" and the footnote says why.

### 2.6 Upcoming dues and committed spend

"₹1,20,000 of this month is already spoken for" — from `recurringRules`, the sum of
active expense rules, plus their due dates in the next 30 days.

- **Data:** `recurringRules` (amount, direction, category, `nextDueOn`).
- **Surface:** Overview (a line under the headline) and/or Trends (a card).
- **Sketch:** `committedMonthlyMinor`; `upcomingDues(DateTime from, {int days})`.
- **Caveats:** C14 — a rule describes habit, not obligation; a stopped rule must
  leave the figure immediately (it will, because rules are soft-deleted and the
  snapshot only carries live rows); C10 if any rule is in another currency.
- **Size:** ~110 lib lines, ~180 test lines. **This is the foundation for Tier 1.1–1.2.**
- **Built:** `UpcomingDue` in `data/upcoming_due.dart`, `committedMonthlyMinor`
  (expense rules only), `committedInvestmentMinor`, `committedIncomeMinor` and
  `upcomingDues` in `data/scheduled_views.dart`, shown by `CommittedSpendCard` on
  the **Overview**. Always a month, whichever period is on screen, and the wording
  is *scheduled* throughout. Tested against a hand-built snapshot, because the
  writer advances a rule's due date against the real clock.

## 3. Tier 1 — new arithmetic over the same rows

### 3.1 End-of-period projection

"At this rate, the month lands at ₹84,000." Two parts, shown separately:
**committed** (rules still due before the period ends) and **projected variable**
(trailing median daily spend × days remaining).

- **Caveats:** C5 (it is a projection of *recorded* data, never a promise — label it
  and show its basis: "based on 6 months and 4 rules"); C11 (empty cash history makes
  it confidently wrong); no projection at all for a closed period.
- **Size:** ~180 lib lines, ~300 test lines (the interesting cases: rules only, history
  only, both, a closed period, a period whose rules exceed its income).
- **Built:** `PeriodProjection` in `data/projection.dart`, `projectionFor` and
  `budgetLimitIn` in `data/period_views.dart`. One line on the pace card opens
  `ProjectionSheet`, which shows the three parts, the basis (months, recorded
  days, rules), the daily allowance and the C5 label. Null for a closed period; no
  line at all when there is no basis. The assistant's `forecast` intent reads the
  same two functions.
  The daily rate is the median day *that carried an entry*, discounted by how
  often days carry one — the doc's "trailing median daily spend", with the
  discount added because a median over calendar days collapses to zero for anyone
  who does not record every single day (C11). The window is clipped to the
  ledger's own life, so a three-week-old install is not dragged toward zero.

### 3.2 Safe to spend

Projection minus budget, floored at zero: "₹2,300 a day keeps you inside your plan."

- **Caveats:** C4 (limits are today's, and must be scaled by whole months — C6), C5.
- **Size:** ~80 lib lines on top of 3.1.
- **Built:** `PeriodProjection.safePerDayMinor` and `overshoots`, spread over the
  days remaining and floored at zero, shown inside the projection sheet rather than
  as its own line. `budgetLimitIn` scales the limits by whole months, so a week
  offers no allowance instead of inventing one.

### 3.3 Subscription list, with the annual figure

Active expense rules as a list: amount, cadence, next due, and **₹/year**. The
annualisation is what makes anyone act.

- **Caveats:** C14, and rules are not proof of a subscription — a monthly
  reimbursement is also a rule.
- **Size:** ~120 lib lines, ~150 test lines.
- **Built:** `Subscription` in `data/subscription.dart`, `subscriptions` and
  `annualSubscriptionsMinor` in `data/scheduled_views.dart`. The Settings recurring
  list shows ₹/year on every row and a total under the list — no new card, since
  that list already *is* the subscription list. `Subscription.periodsPerYear` is
  the single place the monthly-only assumption lives, which is what a future
  cadence would change.

### 3.4 Candidate-rule detection

Same payee, similar amount, roughly monthly spacing, three or more occurrences →
*"this looks recurring — add it?"* A **proposal**, never a silent write.

- **Caveats:** C8 (free-text payee, no fuzzy merge); the known false positive is two
  payments to the same place on the same day each month — state the tolerance in the
  UI rather than hiding it; C9.
- **Size:** ~200 lib lines, ~300 test lines. The trickiest heuristic in Tier 1.
- **Built:** `RecurringCandidate` in `data/recurring_candidate.dart`,
  `recurringCandidates` in `data/snapshot_analytics.dart`, and a "Looks recurring"
  card in Settings that exists **only** when there is something to propose. Its
  tolerances (three or more occurrences, 30 ± 3 days, amounts within 10% of the
  median, last seen within two cycles, exact payee match, skipped when a rule
  already covers that payee) are stated in the card and pinned by tests, and
  `Add monthly` is the only thing that writes — anchored on the last occurrence, so
  the months since post exactly as a back-dated entry with Repeat would.

### 3.5 Budget pace and projected overshoot

Per category: spend so far ÷ elapsed fraction of the period, against the scaled
limit → "Groceries is heading for ₹18,000 against ₹15,000", in time to act.

- **Data:** `budgetStatusesIn` plus `elapsedFraction`.
- **Caveats:** C4, C6.
- **Size:** ~90 lib lines, ~150 test lines.
- **Built:** `BudgetPace` in `data/budget_pace.dart`, `budgetPaceIn` in
  `data/period_views.dart` and the month-shaped `budgetPace` adapter. A budget row
  says "heading for ₹X" *instead of* its "₹Y left" figure, and only when the pace
  takes it past its limit — so a category doing fine is untouched, which is the
  anti-bloat rule in miniature. The Budgets screen adds what each remaining day may
  spend, and the editor sheet carries the same projection.

### 3.6 Suggested limits

Median or p90 of the last six months per category, offered as a proposal.

- **Caveats:** C4 (a suggestion derived from spending is not a budget the user agreed
  to — it must be confirmed); C7 (minimum six recording months, or say nothing).
- **Size:** ~100 lib lines, ~180 test lines.
- **Built:** `SuggestedLimit` in `data/suggested_limit.dart`, `suggestedLimits`
  and the shared `medianOf`/`percentileOf` in `data/statistics.dart`. Offered as
  two chips in the budget editor (the median, and the p90 when the window has a
  spread), applied only on tap, with the C4 sentence beside them. Says nothing at
  all unless the whole six-month window is inside the ledger, and skips a category
  whose median is zero — one expensive month in six is a one-off, not a monthly
  habit.

### 3.7 Liquid net worth over time

Bank + cash + wallet − card balances, reconstructed by replaying
`openingBalanceMinor` and every movement.

- **Sketch:** `balanceSeries(StatsRange)`, `liquidNetWorthIn(range)`; a line chart.
- **Caveats:** **C3 — this is the one figure that cannot be fully honest offline.**
  Investment rows record *contributions*, not market value. The honest version is
  liquid net worth with investments at cost, or at a value the user types in
  (Tier 2.5). Showing a market value would need a price feed, which the app's own
  privacy card rules out, and a stale price is worse than none.
- **Size:** ~220 lib lines, ~320 test lines.
- **Built:** `NetWorthPoint` in `data/net_worth.dart`, `netWorthSeries` and
  `currentNetWorth` in `data/period_views.dart` (which needed the account's opening
  balance carried into the app model), and `NetWorthScreen` — a screen rather than a
  card, reached from one link on the Investing card, because C3's caveat has to be
  read. Liquid, card and invested-at-cost are shown apart, the line starts at the
  ledger's first month, and the month in progress is today's balance rather than a
  fraction of one (a balance is a stock, so C6 does not apply to it).
  A test pins the property that matters most: the replay's liquid + card equals the
  balance the SQL query computes, transfer legs included.

### 3.8 Insight digest and new assistant intents

`forecast`, `subscriptions`, `payees`, `year_over_year`, plus anomalies: an amount
above three times its category's median, price creep on a recurring payee, a drop in
income.

- **Caveats:** **C12 — this is where privacy has to be checked**, because payee names
  are exactly the strings the redaction package promises never leave the device. A new
  intent's payload must carry figures, never merchant names.
- **Size:** ~150 lib lines per intent family, plus a handler test each.
- **Built (the four intents this item lists, not the anomaly detectors):**
  `forecast`, `subscriptions`, `payees` and `yearOverYear` in
  `intent_matcher.dart` and `local_engine_insight_handlers.dart`, plus four
  prompts in `LocalEngine.suggestions` so each is reachable by tapping. The matcher
  tests the more specific phrasings first — "will I be over budget" is a projection
  question, "top places" is a payee question — and a test asserts that every
  suggestion lands on a real intent. The local replies name payees (the biggest
  expense handler always did); what stays free of them is the outbound payload,
  which the redaction package's own tests pin (C12). The three anomaly detectors
  this item also asks for — an amount above three times its category's median,
  price creep on a recurring payee, a drop in income — remain unbuilt.

## 4. Tier 2 — schema changes (the v3 discipline, repeated)

Everything here needs a migration, so each item costs the same ceremony the recurring
work did:

```sh
dart run drift_dev schema dump     lib/src/database.dart drift_schemas/
dart run drift_dev schema generate --data-classes --companions \
    drift_schemas/ test/generated_migrations/
dart run build_runner build --delete-conflicting-outputs
flutter test test/migration_test.dart
```

…plus: bump `schemaVersion`, add the `onUpgrade` branch, **backfill any column added
to a table that already has rows**, never delete an older dump, and add a
previous→new test asserting old rows survive and new tables start empty.

### 4.1 Goals

A `goals` table: name, target amount, target date, and an optional link to a category,
an account, or a recurring rule. Unlocks progress, "at this rate you arrive in N
months" (reusing 3.1's arithmetic), and SIP-funded goals. Cannot be faked from
categories: a limit is a ceiling per month, a goal is an amount by a date — the two
do not imply one another.

### 4.2 Tags

`tags` plus `transaction_tags`. Answers "what did the Goa trip cost?" across
categories. Additive, touches no existing aggregate, and the analytics are a filter
over rows the snapshot already holds.

### 4.3 Splits

One purchase, several categories (₹1,200 at a supermarket: ₹800 groceries, ₹400
household). **The most invasive item in this document**: the ledger row stops being
one category, so `_byCategory` and every budget figure would have to become
split-aware, and the invariant that a row's amount equals the sum of its parts needs
its own test. Only worth it if the user asks for it.

### 4.4 Budget history

A budget is currently a single current value (`monthly_budget_minor`), which means
"you stayed within budget for four months" would retro-apply *today's* limit to
months that had a different one — a quiet lie (C4). A `category_budget_history`
table (category, effective from, amount) fixes it, backfilled from today's value, and
makes both 3.5 and 3.6 honest across time.

### 4.5 Account valuations

`account_valuations` (account, as-of date, value). For investment accounts only;
net worth then uses the latest valuation at or before the date, falling back to cost.
The number is the user's own statement, so it stays honest without a price feed —
this is what would let 3.7 report a real net worth rather than one at cost.

### 4.6 Balance snapshots

A cache of monthly balances so net-worth history does not replay the whole ledger.
**A cache, never a source of truth**: rebuildable from the ledger, with a command in
Settings that proves it.

## 5. Tier 3 — screens of their own

### 5.1 Reports

Pick any period (day → year, plus custom) and get a summary: totals by all three
measures, composition, top categories and payees, budget outcomes, and the change
against the previous period. Export as CSV/PDF is already on the roadmap, and this is
the screen it would hang off.

**Built:** `features/reports/reports_screen.dart`, reached from an icon in the Trends
app bar (one icon, no card anywhere). The period engine gained `StatsPeriod.day` and
`StatsPeriod.custom` — Tiers 0 and 1 only needed the four calendar lengths, and a
report is the first screen to ask for a single day or for two dates the user chose.
Three rules carried over rather than being re-decided:

- **A day and a custom range hold no whole month** (`monthsCovered == 0`), so
  `budgetStatusesIn` returns nothing and the card says why instead of scaling a
  monthly limit to a span nobody agreed to (C4). A custom range's step is its own
  length, so its predecessor is the same number of days.
- **The comparison is stricter than the overview's delta.** `previousPeriodComparison`
  returns null unless the earlier window is *wholly* inside the ledger, where
  `expenseChangeForRange` answers regardless — that one is the overview's nudge beside
  a headline, and this one is a figure a report states as a fact (C7).
- **The three measures stay apart**, with the previous figure named beside the change
  ("12% more than the previous month"), because a percentage on its own hides what it
  is a percentage of.

Composition is the *same card* the overview shows, over these dates: one
implementation, two sets of bounds, which is what stops a report from disagreeing
with the screen beside it.

### 5.2 Year in review

A narrative annual summary — biggest month, savings rate, most-used category, most
frequent payee, longest budget streak, committed spend. Almost entirely presentation
over Tiers 0 and 1, which is why it belongs late: it is the reward for the arithmetic,
not a reason to write it.

**Built:** `features/reports/year_in_review_screen.dart`, one link inside a year
report. `SnapshotAnalytics.yearInReview(year)` is a reading of figures that already
exist — `totalsFor`, `spendIn`, `payeeTotalsIn`, `monthlySummaries`,
`budgetStatusesIn`, `committedMonthlyMinor` — so nothing here is a new sum. Every
figure is nullable and the screen reads null as "nothing here": a review that said
"biggest month: ₹0" would describe the absence of data as a fact about the year.

Two things this item's wish-list implied are deliberately *not* claimed:

- **"Longest budget streak" is stated as months inside today's limits**, with the
  caveat in the row, because the app keeps no budget history — a limit edited last
  week is applied to January here (C4). Months are counted only when a limited
  category was actually spent from: a fresh install ships limits already set, and
  counting empty months would report a streak that never happened.
- **Most-used category and most frequent payee are two different questions**, and the
  second row is drawn only when it names a different payee — repeating one name under
  two headings with the same total reads as a bug (C8: payees are never merged).

### 5.3 Calendar

A month grid with a total per day and a heat tint, tapping a day to see its entries.
The natural companion to the pace chart, and the only view that makes a
back-dated entry obvious at a glance.

## 6. Caveats register

The section this document exists for. Each entry is a way an analytics feature in
*this* app can be wrong while looking right.

- **C1 — Investment is not consumption.** Any figure meaning "spending" must read
  `expenseMinor` and exclude `investmentMinor`; any figure meaning "cash out"
  includes it. Folding the two together understates the savings rate by exactly the
  amount invested, which is the error `investment_test.dart` exists to prevent.
- **C2 — Transfers belong in no total.** `signedMinor` sums are tempting and wrong:
  a transfer has two legs in the ledger, so any "money in vs money out" built from
  signed amounts double-counts the moment transfers exist. Go through direction
  switches, as `totalsFor` does.
- **C3 — Contributions are not market value.** Net worth can be reconstructed
  offline; *investment performance* cannot, without a price feed the privacy design
  rules out. Report at cost or at a user-entered valuation, and say which.
- **C4 — Today's limit is not history.** Budgets are a single current value, so any
  "were you within budget" comparison across past months retro-applies it. Either
  frame it explicitly or add history (4.4).
- **C5 — A projection is not a promise.** Forecasts must be labelled, must show their
  basis (how many months, how many rules), must separate committed from projected,
  and must not exist for a closed period at all.
- **C6 — Never compare a part period against a whole one.** `expenseChangeForRange`
  already scales the previous period when the current one is in progress. Every new
  comparison must respect that, or it will read as a saving every single time.
- **C7 — Small samples.** Averages, percentages and year-over-year comparisons need
  minimum history (roughly: two recording months for an average, twelve for a
  year-over-year). Below that, "not enough history" is the correct output.
- **C8 — Payee is free text, and merging invents merchants.** No fuzzy matching:
  "AMAZON INDIA" and "Amazon" are what the user typed, and silently fusing them
  fabricates a merchant identity the ledger never had.

- **C9 — Sample rows contaminate everything.** `transactions.is_sample` marks the
  demo set, and every aggregate today includes it. Someone who loaded sample data and
  then recorded their own year is looking at blended figures. Decide once — exclude
  sample rows from analytics, or warn when any are present — and apply it everywhere.
- **C10 — Single currency in practice.** `currency` exists and is hardcoded to `INR`;
  there is no conversion and no FX source. Group by currency or refuse to total
  across them; never sum them.
- **C11 — "No spend" means "nothing recorded".** Cash is invisible to this ledger
  between deposits. Frame rhythm and no-spend figures as statements about the
  ledger, not about behaviour.
- **C12 — Analytics produce the strings the privacy card promises to keep.** Top
  payees and subscription lists are merchant names. They stay local, and they must
  not enter an assistant payload — the redaction boundary is tested and this is how
  it would be circumvented.
- **C13 — Dates are local civil dates.** `occurred_on` is authoritative, which is why
  the monthly totals are right. It also means a bank import would move a
  posting-dated entry into the wrong month, quarter or year — see the import
  discussion before building one.
- **C14 — A rule describes habit, not obligation.** Rules are what happened before
  repeating; they are not income guarantees or commitments. Committed-spend figures
  should say "scheduled", never "owed".
- **C15 — Income is lumpy; monthly averages mislead.** A single freelance payment can
  double a month. Lead composition and savings-rate figures with the quarter or year,
  and label the monthly ones as monthly.

## 7. Sequencing

Four independently shippable slices. Each ends with the same gate: `dart format`
clean, `flutter analyze --fatal-infos` clean, three suites green, a device check for
anything visual, and the READMEs updated.

**Tier 0 is built** (composition and comparison from A, committed spend from B,
payees and rhythm from C), **Tier 1 is built** (the projection and safe-to-spend
from B, the deeper budget figures and candidate rules from C, net worth from D, and
the four assistant intents from C's last item), and **two of Tier 3's three screens
are built** (5.1 Reports and 5.2 Year in review) — landed as changes rather than in
slice order, because a tier is the cheaper unit here: it shares one set of caveats
and one screen pass. Every gate above was run for each: all three suites,
formatting, analysis, a device check, and the READMEs and this file updated with it.
What each slice lists beyond its Tier 1 items is untouched — Tier 3's calendar, and
the anomaly detectors inside 3.8.

**Two layout guards came out of the Tier 3 pass.** The report and the review are the
longest lists in the app, so `apps/finance_app/test/reports_screen_test.dart` pumps
both at 347 dp and drags every chip's list to its end. That found a *pre-existing*
overflow rather than a new one: the Trends legend was a `Row` of three swatches where
the composition card's legend is a `Wrap`, so it ran 55 px past the screen edge on
that width — the kind of defect that shows as stripes on a phone and as nothing at all
in a semantics tree. Both legends are `Wrap`s now.

**The device check earned its place.** On a 347 dp phone (1216px at density 3.5) it
caught two chart defects that neither the tests nor the semantics tree could show:
a `Container` given only a height collapses to zero width inside a `Column`, which
made every weekday and per-payee bar invisible while the screen still read as
correct; and the twelve month labels of the year chart wrap at twenty dp each,
which overflowed a fixed chart height by 19 pixels. Both are fixed — bars are a
shared `ChartBar`, labels are scaled down rather than wrapping — and both are
pinned by `apps/finance_app/test/analytics_layout_test.dart`, which pumps the
charts at exactly that width and density.

### Slice A — composition and comparison *(Tier 0.1–0.3)*

The yearly income/investment/expense split, stacked months, and year over year.
Pure presentation over the period engine; no new data. New `composition.dart` plus one
chart widget and two cards on Trends. ~320 lib lines, ~500 test lines, ~15 tests.

Open decision: **calendar year or financial year (Apr–Mar)?** The period engine
assumes calendar months today; an Indian user's "year" is often the financial year.
Recommend calendar year first, with the start month read from settings later — that is
a one-line change to `StatsRange.containing(StatsPeriod.year, …)`, but it must be
decided before the label "Year" is committed to. *(Decided: calendar year — see
question 1.)*

### Slice B — what's coming *(Tier 0.6, 1.1–1.2, 1.5)*

Committed vs variable, upcoming dues, end-of-period projection, safe-to-spend, budget
pace. The direct payoff of the recurring work and the highest-value paid-tier feature
in this document. ~500 lib lines, ~800 test lines, ~30 tests.

### Slice C — where the money goes *(Tier 0.4–0.5, 1.3–1.4, 1.8)*

Top payees, rhythm, subscriptions with annualised cost, candidate-rule detection, and
the assistant intents for them. ~700 lib lines, ~1,000 test lines, ~35 tests.

### Slice D — net worth, then goals *(Tier 1.7, then 2.1 and 2.5)*

Liquid net worth at cost first, then the `goals` table and account valuations in one
v4 migration. Deliberately last among the tiers that need no schema change, because
C3 means it ships a caveat the user has to read. ~400 lib lines plus a migration.

### Later — Tier 3

Reports, year in review and the calendar are laid on top of A–C and are mostly
layout. Year in review in particular should wait until there is a year of real data to
review.

## 8. Open questions

1. **Calendar year or financial year** for the yearly period? (Slice A blocks on it.)
   **Decided: calendar year**, because the period engine already is — the selector,
   `StatsRange.containing(StatsPeriod.year, …)` and every Tier 0 figure are
   calendar-based. Reading a start month from settings stays a one-line change for
   the day an Indian financial year is wanted.
2. **Do sample rows participate in analytics?** (C9 — one decision, applied
   everywhere, with a test.) **Still open**, and deliberately not decided here:
   every Tier 0 figure includes sample rows exactly as every existing aggregate
   does, so blended figures are unchanged rather than newly introduced. Deciding it
   is one change across the whole app, not an analytics-only one.
3. **Does the ledger gain a "sample" badge** so blended figures are visible?
4. **Cadence tolerance for candidate rules** — 30 ± 3 days? Two occurrences or three
   before a suggestion appears?
5. **Is net worth wanted at cost**, or is a manual valuation the expectation?
6. **Where do new figures belong, Overview or Trends?** Proposed rule: **Overview is
   period-scoped ("how am I doing now"), Trends is history-shaped ("what is my
   pattern")** — the same split the month selector already enforced.
   **Decided: applied as proposed.** Composition and committed spend are
   period-scoped on the Overview; composition over time, year over year, top payees
   and rhythm are year-scoped history on Trends. The period selector stays where the
   period question already lived, so Trends needs no second selector.
7. **The pace chart's x-axis labels days even for a quarter or a year**, which reads
   oddly once the selector exists. Fix while building Slice A. **Not done**: the
   chart still labels days, and the fix belongs with the pace work rather than with
   the composition cards.
8. **Are annual bills a special case?** (insurance, car servicing)
   **Decided: not for now.** An annual premium is recorded as a *single expense* in
   the month it is paid, and a service like a car's has no schedule at all, so the
   month is *meant* to read heavy: that is what `expenseChangeForRange`, the
   biggest-hits card, the "Against your own average" card and the Year view are
   for. No cadence work (quarterly / half-yearly / yearly rules) and no
   "reserved from income" figure is planned unless asked for. The consequence to
   remember: `committedMonthlyMinor` cannot see a bill that is eight months away,
   so "already spoken for" is never the whole picture in a month that carries one,
   and a budget bar read monthly will look blown in that month by design — the Year
   period is the honest lens for it.
