# finance_app

The Flutter UI: five screens over the encrypted ledger in `packages/finance_db`.

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
`budgetStatusesIn`, `cumulativeSpendIn`, `expenseChangeForRange`) and the
comparisons in `data/snapshot_analytics.dart` (`categoryMovement`,
`monthlyExtremes`, `savingsRateHistory`). Both files are
pure functions of a snapshot, which is what makes the arithmetic testable without
a widget or a database.

## Layout

```
lib/
  main.dart, app.dart        startup, root widget, snapshot subscription
  core/
    format/                  Money formatting (INR grouping), AmountEntry
    theme/                   Theme, semantic money colours, icon-key lookup
    widgets/                 ChipSelector, SectionCard/StatTile, BudgetBar, charts
  data/
    models.dart              the app's own types — no drift type reaches a widget
    finance_repository.dart  the interface the UI depends on
    drift_finance_repository.dart
    row_mapper.dart          storage rows to app models, plus the trend split
    finance_snapshot.dart    the single immutable aggregate
    snapshot_views.dart      derived totals (pure)
    snapshot_analytics.dart  comparisons against history (pure)
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
| **Overview** | Period selector (week / month / quarter / year), totals for that period, spending pace, category donut, invested card, budget bars scaled to the period (and categories with spend but no limit), biggest hits |
| **Ledger** | Entries grouped by day with subtotals; search, kind filters, edit and delete |
| **Trends** | Spend/received/invested bars, savings rate, investing breakdown, highest and lowest month per measure, income by source, category movement |
| **Ask** | Local assistant engine plus a disclosure of what a hosted model would receive |
| **Settings** | Encryption status, sample-data controls, categories & budgets, recurring rules, roadmap |

## Testing

```sh
flutter test        # 70 tests
```

- `app_smoke_test.dart` — screens render, tabs exist, nothing crashes on a fresh
  install
- `end_to_end_test.dart` — recording, deleting, sample load/erase, and agreement
  between the derived views
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
  days. The same rule governs investing targets.
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
