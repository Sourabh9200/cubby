# finance_app

The Flutter UI: five tabs — Overview, Ledger, Trends, Ask, Settings — plus the
screens they push (budgets, a report, a year in review, a payee's history, net worth),
over the encrypted ledger in `packages/finance_db`.

This README covers how the app is put together. For what the app *does*, its
status, and the money arithmetic, see the [root README](../../README.md).

## Running it

```sh
flutter pub get
flutter run                    # debug build on a connected device
flutter build apk --release    # ~62 MB
```

A debug run is fine for UI work, but it is not proof that encryption works:
`flutter test` and debug builds against stock SQLite legitimately skip the cipher.
Only a release build on a device exercises it.

## Startup

`main()` opens the database **before the first frame**, so a failure to decrypt is
reported as a failure rather than surfacing later as mysteriously empty screens:

1. `DatabaseOpener.open()` loads or creates the passphrase in the Android
   Keystore, opens the encrypted database, and returns it.
2. `DriftFinanceRepository` wraps it.
3. `FinanceApp` renders.
4. If the open throws, `_StartupFailure` renders instead: *"Could not open your
   data — the local database could not be decrypted. Your data has not been
   changed or deleted."* That is the one path where a user could otherwise lose
   access to their own records with no explanation.

## How data reaches the screen

```
drift query streams
      │  (the whole snapshot is rebuilt on any write)
      ▼
Stream<FinanceSnapshot>          data/finance_snapshot.dart
      │  (one StreamBuilder at the root)
      ▼
RepositoryScope                  data/repository_scope.dart
      │
      ▼
screens read RepositoryScope.of(context) and derive their own view
```

Three decisions in that chain are load-bearing:

- **The snapshot is rebuilt wholesale** on every database emission rather than by
  zipping five independent query streams. Zipping risks painting a headline total
  from one revision beside a donut from another; rebuilding makes that impossible,
  at the cost of a few local reads that SQLite answers in microseconds.
- **`RepositoryScope` sits *above* `MaterialApp`**, not inside `home`. A modal
  bottom sheet is pushed as a sibling route in `MaterialApp`'s navigator, so a
  scope placed inside `home` is not an ancestor of the sheet and the sheet cannot
  find the repository.
- **The snapshot stream is created once**, on a `late final` field. Building it
  inside `build` would resubscribe to the database on every rebuild.

Screens never aggregate. They call the derived views in `data/period_views.dart`
(`totalsFor`, `spendIn`, `incomeIn`, `investedIn`, `topExpensesIn`,
`budgetStatusesIn`, `cumulativeSpendIn`, `expenseChangeForRange`,
`compositionFor`, `compositionByMonthIn`, `yearOverYearFor`, `topPayeesIn`,
`payeeSeries`, `spendingRhythmIn`, `projectionFor`, `budgetLimitIn`,
`budgetPaceIn`, `netWorthSeries`), the comparisons in
`data/snapshot_analytics.dart` (`categoryMovement`, `monthlyExtremes`,
`savingsRateHistory`, `suggestedLimits`, `recurringCandidates`), and the
recurring-rule sums in `data/scheduled_views.dart` (`committedMonthlyMinor`,
`upcomingDues`, `subscriptions`, `annualSubscriptionsMinor`). All three files are
pure functions of a snapshot, which is what makes the arithmetic testable without
a widget or a database.

## Layout

```
lib/
  main.dart, app.dart        startup, root widget, snapshot subscription
  core/
    format/                  Money formatting (INR grouping), AmountEntry
    theme/                   Theme, semantic money colours, icon-key lookup
    widgets/                 ChipSelector, SectionCard/StatTile, BudgetBar, ChartBar, charts
  data/
    models.dart              the app's own types — no drift type reaches a widget
    finance_repository.dart  the interface the UI depends on
    drift_finance_repository.dart
    row_mapper.dart          storage rows to app models, plus the trend split
    finance_snapshot.dart    the single immutable aggregate
    composition.dart         spent / invested / unallocated, and the per-month points
    payee_totals.dart        one payee's spend, and its monthly series
    spending_rhythm.dart     by weekday, active days, quiet days
    year_over_year.dart      a range against the same window a year earlier
    upcoming_due.dart        a recurring rule's next occurrence
    projection.dart          where a running period lands, and its basis
    budget_pace.dart         a limit read at the pace being spent
    suggested_limit.dart     a limit offered from the user's own months
    subscription.dart        a live rule, annualised
    recurring_candidate.dart a payee that looks like it repeats, as a proposal
    net_worth.dart           liquid, owed and invested, at cost
    statistics.dart          median and percentile, one definition each
    snapshot_views.dart      derived totals (pure)
    snapshot_analytics.dart  comparisons against history (pure)
    scheduled_views.dart     what the recurring rules account for (pure)
    writers/                 TransactionWriter, CategoryWriter, SampleDataWriter
  features/
    shell/                   HomeShell: five tabs in an IndexedStack
    dashboard/ transactions/ trends/ budgets/ settings/ assistant/
```

- `features/*/widgets/` holds the pieces a screen composes, so a screen file stays
  about layout.
- `RepositoryScope.of(context)` is the read side; `RepositoryScope.actions(context)`
  is the write side.
- `FinanceRepository` is an interface. That is what let the demo repository be
  replaced by the encrypted one without touching a widget, and what lets a test
  inject a fixed snapshot.

## Screens

| Screen | What it shows |
|---|---|
| **Overview** | Period selector (week / month / quarter / year), totals for that period, spending pace with a **projection line** whose working is a tap away, composition of the period, category donut, invested card, budget bars scaled to the period — with a row saying when a category is **heading over its limit** — what recurring rules have already scheduled, biggest hits |
| **Ledger** | Entries grouped by day with subtotals; search, kind filters, edit and delete |
| **Trends** | Spend/received/invested bars, composition by month, this month against the same month last year, savings rate, investing breakdown (with the link to **net worth at cost**), highest and lowest month per measure, top payees (tapping one opens its own history), spending rhythm, income by source, category movement |
| **Ask** | Local assistant engine plus a disclosure of what a hosted model would receive; its intents include the projection, what repeats, the places money went, and this month against last year |
| **Reports** | Reached from an icon in the Trends app bar. Any period from a day to a year, plus a range you pick: totals for all three measures with the change against the previous period, composition, top categories, top payees (tapping one opens its history), budget outcomes · **Year in review** for the whole year as a handful of sentences |
| **Settings** | Encryption status, **encrypted backup & restore** to a single passphrase-protected file, **a screen-level app lock** (fingerprint or the phone's PIN), sample-data controls, categories & budgets, recurring rules **annualised** with **rule proposals** when a payee looks like it repeats, roadmap |

## Backup

The database key lives in the platform keystore, which is what makes the file
unreadable to anything else on the device — and also what makes it die with the
app. An uninstall takes the ledger with it, and no OS-level backup can help:
Android's Auto Backup would restore the encrypted file but not the keystore key,
producing a database that can never be opened again. `allowBackup` is therefore
off deliberately, which also keeps the app's privacy promise intact — nothing is
uploaded anywhere.

Durability is a file the user keeps instead. Settings → Backup & restore writes
everything to one file: AES-256-GCM under a key derived from a passphrase the
user chooses (PBKDF2-HMAC-SHA256, 210,000 rounds), with the salt and iteration
count stored in the header so the cost can be raised later without making older
backups unreadable. Restore replaces the ledger in a single transaction, so a
wrong passphrase or a foreign file fails while the existing data is still
intact.

The passphrase is a *second*, independent secret rather than the database key.
The database key is 256 random bits that no one can memorise, and that is
precisely what makes it useless as the thing a backup depends on.

## App lock

Settings → App lock puts a lock screen in front of the app: the platform's
fingerprint, face or device-PIN prompt, raised through `local_auth`. It is a
**screen-level gate, not a second layer of cryptography** — the ledger is
encrypted independently, with a key in the platform keystore — and the UI says so
rather than implying the lock is what protects the file.

Three decisions worth not undoing:

- **The toggle proves the unlock before it changes anything,** in both
  directions. Turning the lock on without a working unlock would lock someone out
  of their own ledger; turning it off without a check would let whoever is holding
  the phone remove it, which is the whole thing the lock exists to prevent.
- **Re-lock happens on `paused`, never on `inactive`.** The biometric prompt
  itself makes the app inactive, so locking on that would re-lock the instant the
  user answered it and ask them forever.
- **A thirty-second grace period** means choosing a backup file, or glancing at a
  notification, does not cost a fingerprint — while a pocketed phone still
  re-locks.

The gate is installed through `MaterialApp.builder`, so it sits above the
navigator: a pushed report or an open sheet is covered too, not just the tab it
was opened from. The app stays mounted underneath, so unlocking returns you to
the screen you left.

## Testing

```sh
flutter test        # 209 tests
```

- `app_smoke_test.dart` — screens render, tabs exist, nothing crashes on a fresh
  install
- `end_to_end_test.dart` — recording, deleting, sample load/erase, and agreement
  between the derived views
- `analytics_cards_test.dart` — the Tier 0 cards as the user meets them: the
  composition split and its monthly caveat, the scheduled-spend card, the trends
  history cards, and a top payee opening its own history
- `analytics_layout_test.dart` — the charts draw bars with real area on a 347 dp
  phone, and a twelve-column year chart does not overflow when its month labels
  wrap. Both failures were found by a device run, not by a semantics assertion
- `app_lock_test.dart` — the gate: a locked app shows the lock screen and asks
  once, a dismissed prompt keeps it locked with a retry, a phone with no screen
  lock is told rather than prompted, leaving the app re-locks it while a quick trip
  out and back does not, and the setting authenticates before it changes either way
- `backup_crypto_test.dart` — a backup opens with its own passphrase and nothing
  else: the wrong passphrase, a file that is not ours, and a single flipped bit
  in the body are all refused
- `backup_flow_test.dart` — the property the feature exists for: a ledger that is
  wiped comes back from a backup, a wrong passphrase leaves it untouched, and the
  card refuses a passphrase that is too short or mistyped twice
- `tier1_cards_test.dart` — the Tier 1 surfaces, and the guard on not bloating
  the screens: the projection is one line that opens a sheet, a budget row swaps
  one figure for another only when a category is heading over, the suggestion is
  applied only on tap, and the proposals card does not exist when there is
  nothing to propose
- `reports_test.dart` — a day covering one day and stepping across a month, a
  custom range stepping by its own length, a comparison withheld when the earlier
  window is only half covered, and a year in review whose figures match the
  screens it summarises
- `reports_screen_test.dart` — a report of a month and of a single day, the date
  picker for a custom range, the year in review one tap from a year report, and
  both screens laid out on a 347 dp phone with every chip's list scrolled to its
  end
- `projection_test.dart` — where a period lands, what is still to post, the basis
  it rests on, and no projection at all for a closed period
- `budget_pace_test.dart` — a limit read at the pace being spent, and suggested
  limits that need six months of history before they say anything
- `subscriptions_test.dart` — recurring rules annualised, and the total
- `recurring_candidates_test.dart` — the proposal heuristic's tolerances: same
  payee, similar amount, roughly monthly, and not a habit that stopped
- `net_worth_test.dart` — the replay agreeing with the balance the query
  computes, an investment moving money sideways rather than changing net worth,
  and a line that starts at the ledger rather than before it
- `assistant_intents_test.dart` — the new intents match the right question, and
  the handlers state their basis, refuse to compare without a year behind them,
  and show payee names exactly as recorded
- `composition_test.dart` — a period split three ways, the per-month columns
  (including the month in progress), and a transfer counted in none of them
- `year_over_year_test.dart` — the same month a year earlier, last year scaled
  while the period runs, and no comparison at all when the window is not covered
- `payees_test.dart` — top payees ranked by spend, no fuzzy merging of names, and
  one payee's entries, series and total
- `rhythm_test.dart` — spend by weekday, days that have happened, and quiet days
  counted as *nothing recorded*
- `committed_spend_test.dart` — the recurring-rule sums and the thirty-day due
  window, against a hand-built snapshot so the real clock cannot move it
- `categories_and_editing_test.dart` — custom categories, editing, and the
  investing invariants
- `budgets_and_dates_test.dart` — budget editing and back-dated entries
- `period_view_test.dart` — the week/month/quarter/year selector: period
  boundaries (a week starts on Monday and can span a year), a quarter equalling
  the sum of its months, budget limits scaling by whole months, and the weekly
  view reporting no budgets at all
- `backdated_category_test.dart` — the month selector: a category spent from in a
  past month appears in that month's biggest hits, budget rows and movement, and
  a category with no limit is shown rather than hidden
- `category_visibility_test.dart` — how a category stays reachable from the
  overview: the budget card's ordering, and a donut legend that lists every
  category even when the ring merges the tail
- `income_and_records_test.dart` — income split by source, and the highest and
  lowest month per measure
- `recurring_rules_test.dart` — a rule schedules the month after the entry it came
  from and carries that entry's direction; making an *existing* entry recurring
  starts next month instead of posting the months since; stopping one keeps what it
  recorded
- `sample_isolation_test.dart` — "remove sample data" cannot touch your own rows
- `support/fixture.dart` — a real drift stack, in memory, with a fixed clock

Two rules for adding tests here:

- **Widget tests must not start real database writes.** They deadlock the harness
  rather than exercising the code. Persistence is asserted with plain `test`s
  against the real schema that `support/fixture.dart` provides; `testWidgets`
  asserts the UI contract only.
- **Scope your finders.** `HomeShell` keeps every tab alive in an `IndexedStack`,
  so text from the dashboard is in the tree behind an open sheet: `find.text('Income')`
  matches both the dashboard's tile and an open sheet's chip. Use
  `find.descendant(of: find.byType(SomeSheet), matching: ...)`.

There is also a guard on sheet layout. Adding a third category kind once pushed
the numeric pad below the viewport, so tapping a digit silently missed and the
sheet appeared to ignore input. `the entry sheet keeps the pad and Save reachable`
now runs at a realistic phone size and fails if that regresses.

## Rules worth not breaking

- **Money is an integer in minor units, always** — never a `double`. Amounts are
  stored positive and `TxDirection` carries the sign, so a bug cannot silently
  flip a spend into income.
- **A monthly limit scales by whole months, and a week gets no bars.** The
  overview can show a week, a month, a quarter or a year, and every card follows
  one `StatsRange`. Budgets are monthly, so a quarter's limit is three months of
  it and a year's is twelve — `StatsPeriod.monthsCovered` — while a week holds no
  whole month and therefore shows none rather than a limit stretched over seven
  days. The same rule governs investing targets. A report adds two more lengths —
  a single **day** and a **range the user picked** — and both report
  `monthsCovered == 0`, so a report says "budgets are monthly" rather than drawing
  a monthly limit over a span nobody agreed to.
- **A report compares against the period before it only when that window is whole.**
  `previousPeriodComparison` returns null unless the earlier span is wholly inside
  the ledger, and scales the earlier figures while the current period is still
  running (C6, C7). `expenseChangeForRange` is deliberately looser — it is the
  overview's nudge beside a headline — so the two are not interchangeable, and the
  report uses the strict one because it states the change as a fact.
- **A year in review says nothing rather than zero.** Every figure in
  `YearInReview` is nullable, and the screen reads null as "nothing here": no
  biggest month, no top payee, no savings rate without income. Its streak counts
  only months in which a *limited* category was actually spent from, because a
  fresh install ships limits already set and counting empty months would report a
  streak that never happened — and it is stated as "inside today's limits", since
  the app keeps no budget history (C4).
- **The month-shaped views are adapters, not implementations.** `spendByCategory`,
  `budgetStatuses` and friends delegate to the period views, so the weekly and
  monthly figures are the same arithmetic over different bounds and cannot
  disagree. The trend charts, the category averages and the assistant still ask
  monthly questions because the *rules* they describe are monthly: a budget
  repeats every month and a "best month on record" is a month.
- **A recurring rule is a template, never a row dated in the future.** Occurrences
  are written into the ledger on the day they fall due, so every aggregate sees
  ordinary entries and no chart has to know that a rule exists. The rule's first
  occurrence is the month *after* the entry it was created from, because that entry
  is already in the ledger.
- **A commitment figure is always a month, and a silent day is never a spend.**
  `committedMonthlyMinor` and `upcomingDues` describe recurring rules, so they are
  monthly whichever period is on screen and they say *scheduled*, never *owed*
  (C14); investing rules are listed apart from spending rules (C1). Rhythm and
  quiet-day figures say "recorded", because cash does not pass through this app
  between deposits (C11).
- **Composition is a re-arrangement of the totals, not a second sum.**
  `compositionFor(range)` is built from `totalsFor(range)`, so the three slices and
  the headline cannot disagree, and the month-in-progress column is marked rather
  than drawn like a whole one (C6).
- **A comparison against a part window does not exist.** `yearOverYearFor` returns
  null unless the ledger covers the whole of the year-earlier window, and scales
  last year by the elapsed fraction while the period is still running (C6, C7).
  "Not enough history" is the output — never an estimate.
- **A chart bar is a `ChartBar`, and a chart reserves height for its bars, not for
  its labels.** A `Container` given only a height collapses to zero width inside a
  `Column` — it wraps a childless box in a `LimitedBox(maxWidth: 0)` — so a bar
  built that way is invisible with no error, nothing in the semantics tree, and
  nothing for a test that is not looking at geometry to catch. Both that and a
  19-pixel overflow from wrapped month labels on a 347 dp phone were found by a
  device run and are now pinned by `analytics_layout_test.dart`. Labels are scaled
  down with `FittedBox` instead of wrapping into the bars' height.
- **Payee names are matched exactly and never merged.** "AMAZON INDIA" and "Amazon"
  are two payees (C8), and an entry with no payee is left out of the top list rather
  than collected under a blank row.
- **A projection is one line, then a sheet.** The pace card carries the figure and
  the working-out — spent, still to post, expected, the basis, and what each
  remaining day may spend — is behind a tap. It is not drawn at all when there is
  no basis, and never for a closed period (C5, C11), and the assistant's
  `forecast` intent reads the same two functions rather than recomputing them.
- **A pace replaces a figure; it does not add a row.** A budget row says "heading
  for ₹X" *instead of* "₹Y left" only when the pace takes that category past its
  limit. A category comfortably inside its limit renders exactly as it did before
  any of this existed.
- **A suggestion is offered and never applied.** `suggestedLimits` says nothing
  unless the whole window is inside the ledger and skips a category whose median
  is zero (C7); the chip fills the field only when tapped, and the sheet states
  that a figure read off someone's spending is not a budget they agreed to (C4).
- **Candidate rules are proposals, and they state their tolerances.** Same payee,
  about the same amount, three or more occurrences about thirty days apart (±3),
  last seen within two cycles, and no rule already covering that payee. The card
  appears only when there is something to propose, says the false positive out
  loud, and `Add monthly` is the only thing that writes (C14).
- **Net worth is at cost, and starts at the ledger.** Investments are added at
  what was paid for them (C3); the line's first month is the first month with an
  entry, because a month before the app existed would draw an opening balance as
  if it were history (C7). The replay skips transfer legs exactly as the account
  query does, so the line and the balances cannot disagree (C2).
- **The far end of the assistant is intents, not cards.** The projection, what
  repeats, the places money went and this month against last year are reachable by
  asking. The local reply may name what the user typed; the outbound payload never
  carries a payee, which is what the redaction package's own tests pin (C12).
- **The two ways of starting a rule are anchored differently, on purpose.** A new
  entry continues from its own month and *posts the months since* — recording
  August's rent in December should land September through December. Making an entry
  that already existed recurring anchors on today instead, because the months
  before it may already have been entered by hand, and of the two possible
  mistakes only a duplicate is visible on screen.
- **The seeded `Investments` category is a roll-up, not a bucket.** Its row
  reports the month's whole investing total (`investedForCategory`), so money
  funded into a mutual fund appears in it rather than beside it as a ₹0 — the two
  figures used to read as unrelated numbers. Nothing sums those rows into a
  headline, so reporting the total there cannot double-count it, and the trends
  breakdown — where each row is a *share* of the total — still holds only what
  money was actually filed against.
- **A category decides the direction of its entries**, so the user never states
  something the app already knows — and an investing category can never be filed
  as spend.
- **Colours are semantic, not decorative.** `MoneyColors.expense/income/investment`
  are defined per brightness: a green that reads as "positive" in light mode looks
  neon in dark mode.
- **Icons come from stored string keys** via the `categoryIcon` lookups, never
  `IconData(codePoint)`. Flutter's release build tree-shakes the icon font and
  rejects non-constant `IconData`.
- **Money entry goes through `AmountEntry`** with `AmountField`/`NumericKeypad`,
  shared by the entry sheet and the budget editor, so both pads parse identically
  and the 8-digit cap lives in one tested place.
- **Never swallow a failed write.** A snackbar on save, edit, and delete is the
  difference between a bug and a user believing a financial record is stored when
  it is not.
