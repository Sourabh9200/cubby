# Cubby

Cubby is a local-first personal finance app for Android. Your ledger lives in a
single encrypted SQLite file on your phone. There is no server, no account, and
no sync.

Three properties are treated as non-negotiable, and each is pinned by a test
rather than by a convention:

- **Encrypted at rest.** The file is keyed by SQLite3MultipleCiphers and the key
  is a 32-byte random value held in the Android Keystore. The app reads the file
  header back and reports the truth about it rather than assuming.
- **Nothing leaves the device.** The one component that will eventually need a
  network — the AI layer — lives in a package whose only outward-facing type has
  no field for a payee, a note, an account id, or a transaction id.
- **Money is exact.** Amounts are integers in minor units, never `double`. Months
  are grouped on a local ISO date column, never on UTC epoch seconds.

## Status

**Working end to end, verified on a device:**

- **Dashboard** — a period selector (**week, month, quarter or year**, monthly by
  default) driving every card on the screen: spent/income/net, spending pace with
  **a projection line** (where the period lands, with the working one tap away),
  **composition** (spent / invested / left unallocated), category donut, budgets
  that say when a category is **heading over its limit**, invested, biggest hits,
  and **what recurring rules have already scheduled**. Trends follows the same
  month.
- **Ledger** — grouped by day with subtotals, searchable, filterable by
  kind, and every entry can be **edited** or **deleted**.
- **Trends** — spend/received/invested per month, **composition by month**, **this
  month against the same month last year**, savings rate history, investing
  breakdown, the highest and lowest month on record for each of the three
  measures, income split by source, month-over-month category movement, **top
  payees** with a per-payee drill-down, **spending rhythm** by day of week, and
  **net worth over time, at cost**.
- **Categories & budgets** — a monthly limit or target per category, and
  **custom categories** of any of the three kinds.
- **Investments** — a third kind of money movement, tracked apart from spending
  (see [Investments are not spending](#investments-are-not-spending)).
- **Recurring** — record an entry with Repeat switched on and it is posted again
  on the same day every month, including for months the app was not opened. The
  chip is on the edit sheet too, for making an entry you already have recurring.
  Rules are listed and stopped under Settings, **annualised** there (₹18,000 a
  month is ₹2.2L a year), and Settings **proposes** a rule when the same payee,
  for about the same amount, appears three or more times about a month apart —
  only ever as a proposal.
- **Settings** — encryption status read from the file header, **an encrypted
  backup and restore** to one passphrase-protected file, a **screen-level app
  lock** (fingerprint or the phone's PIN), sample-data load/remove, and
  erase-everything. Budget editors offer a limit derived from the user's own last
  six months.
- **Assistant** — a fully local engine that answers from your own data, with a
  disclosure of exactly what a hosted model would have been sent. Asks include
  the deeper figures: **the projection, what repeats, the places money went, and
  this month against last year**.

**Not built yet** (listed in-app under Settings → "Not built yet"):

- CSV import, PDF export
- Transfers — the `transfer` direction and `transfer_group_id` column exist and
  are excluded from every total, but nothing creates such a row
- Accounts management (three accounts are seeded; there is no UI to add or edit)
- Weekly and yearly recurrence (only monthly rules are built). **Deliberately so
  for annual bills:** an insurance premium is recorded as a single expense in the
  month it is paid, so that month's total is meant to look heavy — see the note in
  [`docs/analytics.md`](docs/analytics.md) §8. Budget alerts, multi-currency,
  likewise
- The remote half of the assistant. Only the local engine and the redaction
  package exist, deliberately: the privacy boundary is worth building and
  testing before anything is allowed to cross it.
- iOS, web, and desktop. Only `android/` is configured.

A tiered plan for the analytics work — period composition, forecasting,
subscriptions, net worth and goals — together with the caveats each figure carries
so it cannot quietly mislead, is kept in [`docs/analytics.md`](docs/analytics.md).
**Tiers 0 and 1 of that plan are built**, along with two of Tier 3's three screens:
composition, composition over time, year over year, top payees, spending rhythm and
committed spend; then the projection and safe-to-spend, budget pace, suggested
limits, annualised subscriptions, recurring-rule proposals, net worth at cost, and
the assistant intents for them; and then a **reports** screen for any period from a
day to a year — the change against the one before it, where the money went, who was
paid, budget outcomes — with a **year in review** written as sentences. The deeper
figures are behind a tap or a question — one line on the pace card, a link on the
investing card, an icon in the Trends app bar, a proposal in Settings — rather than
more cards on the two busiest screens. Tier 2 (goals, tags, splits, budget history,
valuations) and Tier 3's calendar still need schema work or a screen, and are not
built.

## Layout

A pub workspace: three packages, one lockfile, one resolved dependency graph.

| Path | What it is | lib (lines) | Tests |
|------|-----------|------------:|------:|
| [`packages/finance_assistant`](packages/finance_assistant/README.md) | Privacy boundary for LLM calls. Pure Dart, **zero runtime dependencies**. | 1,947 | 88 |
| [`packages/finance_db`](packages/finance_db/README.md) | Drift schema, migrations, aggregation queries, passphrase handling. | 2,026 | 72 |
| [`apps/finance_app`](apps/finance_app/README.md) | Flutter UI: five tabs plus the screens they push (budgets, reports, a payee, net worth) and the shared widgets. | 14,349 | 189 |

`finance_db` line count excludes generated `.g.dart`. Each package README covers
the reasoning behind that package's design; this file is the map.

The dependency direction is one-way and enforced: `finance_app` depends on
`finance_db`; `finance_assistant` depends on **nothing**. That is what makes the
privacy claim structural rather than a promise to remember to sanitize.

## Getting started

### Prerequisites

| | Version used |
|---|---|
| Flutter | 3.47.4 (stable) |
| Dart SDK | `^3.13` — see `environment.sdk` in the workspace pubspec |
| JDK | 17 — `sourceCompatibility` and `jvmTarget` are both 17 |
| Android SDK | Platform 36, build-tools 36.0.0, platform-tools |
| minSdk | 24 (Flutter's default). The NDK builds the native SQLite. |

`flutter doctor` should report the Android toolchain as `[✓]` before anything
below works.

### Build and run

```sh
flutter pub get                 # resolves all three packages at once
cd apps/finance_app
flutter run                     # debug build on a connected device
flutter build apk --release     # ~62 MB; no --split-per-abi yet
```

Two things worth knowing before you change anything here:

- **A release build is the real test of encryption.** `AppDatabase.openEncrypted`
  asserts that the linked SQLite provides `PRAGMA cipher`, and that assert is
  compiled out of release builds. The assert is what catches a debug session
  quietly running on stock SQLite; `isFileEncrypted` is what catches it in
  release, by reading the file header back at runtime and reporting the truth.
  Both exist because the failure mode — `PRAGMA key` silently accepted as a no-op
  and the database written as plaintext — raises no error anywhere.
- **The cipher comes from the `hooks:` block in the root `pubspec.yaml`**
  (`source: sqlite3mc`). It must be declared where the native library is built.
  Moving it into a package pubspec drops the cipher without failing the build.

### Test

Run the suites explicitly. `dart test` at the repository root runs **nothing** —
the root is a workspace, not a package, so it has no `test/` directory, and a
green no-op is easy to mistake for a passing suite.

```sh
cd packages/finance_assistant && dart test      # 88 tests — pure Dart, no Flutter SDK needed
cd packages/finance_db        && flutter test   # 78 tests
cd apps/finance_app           && flutter test   # 209 tests
```

The same three gates CI runs:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
```

### Regenerating code

Only `finance_db` generates code (drift). Run it from that package:

```sh
cd packages/finance_db
dart run build_runner build --delete-conflicting-outputs   # database.g.dart
```

Test fixtures for the checksum-validated PII detectors are generated, not
hand-written, because a plausible-looking Aadhaar number that fails its check
digit produces a red test and tempts you to "fix" a correct detector:

```sh
dart run tool/generate_fixtures.dart    # from the repository root
```

## The database

`finance_db` owns the schema. Two things about changing it matter:

**Drift maps Dart properties to `snake_case` SQL columns.** Hand-written SQL in
the query extensions therefore uses `occurred_on`, `amount_minor`, and so on.
Getting this wrong fails loudly at runtime rather than at compile time, because
custom SQL is a string.

**Every schema change needs a migration test, not just a version bump.**

```sh
cd packages/finance_db

# 1. Bump schemaVersion and add an onUpgrade branch in lib/src/database.dart.
# 2. Snapshot the new schema and regenerate the helpers. The flags are required:
#    without them the generated helpers lose the companions that the migration
#    test inserts its fixture rows through, and it stops compiling.
dart run drift_dev schema dump     lib/src/database.dart drift_schemas/
dart run drift_dev schema generate --data-classes --companions \
    drift_schemas/ test/generated_migrations/

# 3. Extend test/migration_test.dart with the new step, then:
flutter test test/migration_test.dart
```

`schema dump` writes only the current version's file. The older ones are history
and must be kept — deleting `drift_schema_v1.json` removes the ability to test the
upgrade from v1 at all.

`drift_schemas/drift_schema_v*.json` and `test/generated_migrations/` are
**committed on purpose**. They are what let `SchemaVerifier` build a real
database at an old version, run the upgrade against it, and assert both that the
resulting schema is valid and that the rows survived. A migration that drops a
column or mislabels existing rows otherwise corrupts someone's financial history
silently and irreversibly.

There is a worked example of the second half of that in `migration_test.dart`:
a plain `addColumn` would have marked every pre-existing row as the user's, which
made a new "remove sample data" button a no-op for exactly the people who had
already used the app. The migration backfills from the marker that existed at the
time instead.

## Investments are not spending

This is the one place the data model is easy to get subtly wrong, so it is worth
stating outright. A mutual fund contribution is cash out, but it is **not**
consumption — the money is still yours, just less liquid.

| Figure | Formula | Means |
|--------|---------|-------|
| Spent | expenses only | consumed |
| Kept (`netMinor`) | income − expense | saved, including money invested |
| Cash left (`cashLeftMinor`) | income − expense − investment | change in the bank |
| Savings rate | kept ÷ income | standard definition |

Treating an investment as an expense keeps every screen rendering and every
chart drawing while making the spending total and the savings rate wrong by
exactly the amount the user saved. `packages/finance_db/test/investment_test.dart`
exists to make that impossible:

- investments do not count as spending, but do reduce account balances
- investments are excluded from the daily pace curve and the spending donut
  (a diligent saver should not look like a big spender on SIP day)
- the trend query returns spending, income, and investing in **one** read, split
  by direction, so the donut, the income split, and the investing card cannot
  describe different revisions of the ledger

## Money and dates

- **Integers in minor units.** `amountMinor` is paise. There is no `double`
  anywhere near a money value, and amounts are stored positive with an explicit
  `direction`, so no code path can flip a spend into income by dropping a minus.
- **INR formatting is not hand-rolled.** `intl` handles Indian digit grouping
  (`1,23,456.78`), which differs from Western grouping in a way that is subtle
  and wrong in every screenshot if you approximate it.
- **`occurred_on` is authoritative for grouping, and it is a local ISO date
  string.** Drift stores `DateTime` as UTC epoch seconds, so bucketing by month
  with `strftime(..., 'unixepoch')` would misfile a 1st-of-the-month transaction
  into the previous month for anyone east of Greenwich. `occurred_at` is retained
  for future time-of-day analysis and is never used for grouping. ISO strings
  also compare correctly with plain `>=`/`<`, which keeps the range filters
  index-friendly.

## Conventions

- **Aggregation happens in SQL**, against an index. Pulling a growing ledger into
  Dart to total it is what makes a finance app feel slow after two years of use.
- **Every read returns a `Stream` and declares `readsFrom`**, so drift invalidates
  it automatically and the UI refreshes after a write with no manual plumbing.
- **The snapshot is rebuilt wholesale** on any change rather than by zipping
  independent query streams. Zipping risks rendering a total from one revision
  beside a donut from another; rebuilding makes that impossible.
- **Deletes are soft** (`deleted_at`). Hard-deleting a row leaves history
  unreconcilable and gives a future sync nothing to propagate.
- **Icons and colours are stored as string keys**, resolved to constant `IconData`
  and `Color` in the app. Flutter's release build tree-shakes the icon font and
  rejects non-constant `IconData`, so a raw code point in the database would
  break release builds only.
- **`RepositoryScope` sits above `MaterialApp`.** Below it, a modal bottom sheet
  cannot find the repository, because sheets build in a different subtree.
- **Widget tests must not start real database writes.** They fight the harness
  rather than the code, so repository behaviour is asserted with plain `test`s and
  only the UI contract is asserted with `testWidgets`.
- **`late final` in a `State` breaks when the database emits more than once.** Use
  a nullable field assigned with `??=` during build instead.

## Known gaps

- **CI does not build the APK.** It gates formatting, analysis, and the three test
  suites. A packaging or native-linking break would reach a device before CI
  noticed.
- **`sqlite3mc` is only exercised on a device.** `flutter test` runs against a
  stock SQLite build where the cipher pragma legitimately does not exist.
- **Single currency in practice.** The `currency` column exists and is populated
  with `INR`, but no conversion or mixed-currency formatting is implemented.
- **No accounts UI**, so the seeded account names are what you get.
