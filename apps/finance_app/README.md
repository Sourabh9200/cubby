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

Screens never aggregate. They call the derived views in `data/snapshot_views.dart`
(`spendByCategory`, `budgetStatuses`, `investmentTargets`, `investedByCategory`,
`cumulativeDailySpend`, …) and the comparisons in `data/snapshot_analytics.dart`
(`expenseChangePercent`, `categoryMovement`, `savingsRateHistory`). Both files are
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
| **Overview** | Month totals, spending pace, category donut, invested card, budget bars, biggest hits |
| **Ledger** | Entries grouped by day with subtotals; search, kind filters, edit and delete |
| **Trends** | Spend/received/invested bars, savings rate, investing breakdown, category movement |
| **Ask** | Local assistant engine plus a disclosure of what a hosted model would receive |
| **Settings** | Encryption status, sample-data controls, categories & budgets, roadmap |

## Testing

```sh
flutter test        # 32 tests
```

- `app_smoke_test.dart` — screens render, tabs exist, nothing crashes on a fresh
  install
- `end_to_end_test.dart` — recording, deleting, sample load/erase, and agreement
  between the derived views
- `categories_and_editing_test.dart` — custom categories, editing, and the
  investing invariants
- `budgets_and_dates_test.dart` — budget editing and back-dated entries
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
