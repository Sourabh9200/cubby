# finance_db

Local encrypted storage for Cubby: drift tables, aggregation queries,
migrations, and the passphrase handling that keys SQLite3MultipleCiphers.

**Everything the UI knows about money comes from here.** The app never sees a
drift type — a mapper converts rows into the app's own models, so the storage
layer could be replaced without touching a widget.

## Why drift

Every read in this app is an aggregate over a ledger that grows forever. drift is
a typed layer over SQLite rather than an ORM that hides SQL, so the aggregation
and the window functions the charts depend on stay available, while the schema,
the migration path, and the generated row classes are checked at compile time.

Custom SQL is a string and therefore not checked, which is a real trade-off. It is
mitigated by keeping it in one place (`src/queries/`) with a test per query, and
by the undocumented-footgun rule below.

> **drift maps Dart properties to `snake_case` columns.** `occurredOn` is the
> `occurred_on` column; `amountMinor` is `amount_minor`. Hand-written SQL must use
> the SQL names, and getting it wrong fails at runtime rather than at compile
> time.

## The encryption guarantee, and how it is checked

Encryption is only real if the linked SQLite build supports it. If it does not,
`PRAGMA key` is accepted as a **no-op** and the database is written as plaintext
with no error raised anywhere — the worst possible failure mode for a feature
whose entire purpose is confidentiality.

Two independent checks guard against it:

1. **`AppDatabase.openEncrypted` asserts `PRAGMA cipher` exists** before it
   applies the key. This runs in debug builds, so a developer finds out
   immediately. It is deliberately switchable, because `flutter test` runs
   against a plain SQLite build where the pragma legitimately does not exist.
2. **`isFileEncrypted` reads the file header** and confirms it is *not* the
   `SQLite format 3\0` magic. This one runs in release too, so the app can tell
   the user the truth instead of assuming it.

The cipher itself is linked by the `hooks:` block in the **root** `pubspec.yaml`
(`source: sqlite3mc`). That has to be declared where the native library is built;
moving it into this package's pubspec drops the cipher without failing the build.

The passphrase is 32 random bytes in the platform keystore via
`flutter_secure_storage`, not in shared preferences, so reading files off a rooted
device does not yield the key. `InMemoryPassphraseStore` exists for tests.

## Schema

Five tables: `accounts`, `categories`, `transactions`, `recurring_rules`,
`settings_entries`.

Decisions worth not undoing:

- **UUID text primary keys, not autoincrement integers.** Imported data and any
  future multi-device sync can then never collide on a key.
- **Soft deletes everywhere** (`deleted_at`). Hard-deleting a row that other rows
  reference either cascades unexpectedly or orphans history, and gives a future
  sync nothing to propagate.
- **`occurred_on` — a local ISO date string — is authoritative for grouping.**
  This column exists to avoid one specific silent bug. drift stores `DateTime` as
  UTC epoch seconds, so `strftime(..., 'unixepoch')` would bucket transactions by
  UTC months; for anyone east of Greenwich that misfiles a 1st-of-the-month entry
  into the previous month, and it is invisible until a total disagrees with a bank
  statement. `occurred_at` is kept for future time-of-day analysis and is never
  used for grouping.
- **`transactions.is_sample`** rather than a marker in the free-text note. Erasing
  the demo set must never touch a row the user typed, and keying that off text the
  user can also write would eventually delete real data.
- **Amounts are always positive**, with `direction` carrying the sign, so no code
  path can record a spend as income by omitting a minus.
- **Icons and colours are stored as string keys** (`icon_key`, `color_key`),
  resolved to constant `IconData`/`Color` in the app. Flutter's release build
  tree-shakes the icon font and rejects non-constant `IconData`, so a raw code
  point in the database would break release builds only.

## Investing is a third kind, not a flavour of expense

`CategoryKind` and `EntryDirection` both have an `investment` member. Money moved
into an asset is cash out but *not* consumption, so it is counted apart from
spending in every aggregate. `test/investment_test.dart` pins the invariants;
the root README explains the arithmetic.

Adding a value to either enum needs **no migration**: drift stores `textEnum`
columns as plain `TEXT` with no `CHECK` constraint (only the boolean columns get
one). Rows are a different matter — a database seeded before the kind existed has
no investment category, and no schema migration can add one. That is what the
seed version is for.

## Aggregates

`src/queries/` holds four extensions over `AppDatabase`. Each method returns a
`Stream` and declares `readsFrom`, so drift invalidates it automatically when the
underlying tables change — that is what refreshes the UI after a write with no
manual plumbing.

Aggregation happens in SQL against an index. Pulling a whole ledger into Dart to
total it is what makes a finance app feel slow after a couple of years of real use.

## Recurring rules

`recurring_rules` holds a **template**, not a set of pre-written future entries.
Rows dated in the future would distort the month they land in from the moment the
rule was created — the opposite of what "this repeats" means — and every aggregate
would have to learn to exclude them. Instead `materialiseDueRecurring` writes an
occurrence into `transactions` when it falls due, so the ledger stays the single
source of truth and every existing query, chart and total keeps working on
ordinary entries.

Four decisions in that engine are load-bearing:

- **Idempotent by construction, not by a flag.** Posting an occurrence advances
  `next_due_on` in the same batch that inserts the rows, so a restart, a crash, or
  an app opened twice cannot post the same month's rent twice. A "already ran"
  marker would be a second thing to keep in step with the first.
- **It runs on open**, before the first read, so no screen can render a month that
  is missing rent which has already been paid. It catches up every month that fell
  due, because a missing month in a household ledger is harder to notice than a
  wrong total.
- **Short months clamp.** A rule on the 31st posts on the 30th in April and the
  28th in February. Skipping the month would silently lose a payment; rolling into
  the 1st would file it under the wrong month.
- **There is a cap** (`maxOccurrencesPerRule`) because one bad due date — a rule
  made from a heavily back-dated entry, or a device switched off for years — could
  otherwise write thousands of rows on launch. A capped rule stays due, so the
  remainder posts on the next run rather than being lost.

Stopping a rule is a soft delete of the rule only. Occurrences it already posted
are ordinary ledger entries: "not again" is not "erase the rent you already paid".

## Migrations

`schemaVersion` is **3** today. v1 → v2 added `transactions.is_sample`; v2 → v3
added `recurring_rules`.

The v2 → v3 step is additive on purpose, and the test says so: it inserts a ledger
row at v2, migrates, and asserts the row is untouched and the new table starts
empty. An upgrade must never rewrite a ledger row — that is the only thing in the
database that cannot be reconstructed — and it must not materialise anything
either, because an install predating the feature has no rules and inventing
entries would put money in a ledger that never moved.

`drift_schemas/drift_schema_v*.json` and `test/generated_migrations/` are
**committed on purpose**. They are what let `SchemaVerifier` construct a real
database at an old version, run the upgrade against it, and assert both that the
resulting schema is valid and that existing rows survived. Without them, a
migration that drops a column or mislabels existing rows corrupts a user's
financial history silently and irreversibly.

```sh
# after bumping schemaVersion and adding an onUpgrade branch:
dart run drift_dev schema dump     lib/src/database.dart drift_schemas/
dart run drift_dev schema generate --data-classes --companions \
    drift_schemas/ test/generated_migrations/
dart run build_runner build --delete-conflicting-outputs
flutter test test/migration_test.dart
```

Two traps in those commands:

- **`schema dump` writes only the current version's file.** It does not rewrite the
  older ones, and it must not: `drift_schema_v1.json` is history, and deleting it
  removes the ability to test the upgrade from v1 at all.
- **`--data-classes --companions` are required, not cosmetic.** Without them the
  generated helpers come out stripped of the `…Data` and `…Companion` classes, and
  `migration_test.dart` — which inserts v1 rows through `v1.AccountsCompanion` and
  `v1.CategoriesCompanion` — stops compiling. The default output is roughly a
  quarter the size, so the mistake looks like a successful regeneration.

The v1 → v2 step is a worked example of why the data backfill matters as much as
the DDL. A plain `addColumn` would have left every pre-existing row classified as
the user's own, which turned the new "remove sample data" button into a no-op for
exactly the people who had already used the app — the fix would have looked broken
to the one person who reported it. The migration backfills from the marker that
existed at the time (`note = 'Sample data'`), which was unambiguous before the
column existed. Two tests cover it: one asserts legacy rows are *not* marked
sample, the other asserts the backfill still catches the old demo rows.

## Seeding

`seedDefaults` runs from `onCreate`, so it happens exactly once per database
lifetime: three accounts, ten expense categories, four investment categories,
`Income`, and the currency/month-start settings.

`seedMissingDefaults` runs from `beforeOpen` whenever the stored `seed_version`
is behind `currentSeedVersion`. It uses `INSERT OR IGNORE` against the primary
keys, so a row that already exists is left completely alone. That matters because
the user may have renamed a seeded category or changed its budget, and a top-up
that overwrote those would silently undo their edits **on every launch** — a bug
that only becomes visible once someone has data they care about.

This is the only mechanism that can add *rows* to an existing install. A schema
migration changes structure; it cannot invent a category. That is why adding the
investment kind required a seed version bump and no schema change at all, and why
`seeding_test.dart` and `migration_test.dart` both cover the top-up.

## Testing

```sh
flutter test        # 72 tests
```

- `ledger_test.dart`, `category_spend_test.dart`, `time_series_test.dart`,
  `investment_test.dart` — the aggregates, asserted against a real in-memory
  schema via `test_helpers.dart`
- `migration_test.dart` — schema validity, row survival, the sample-data backfill,
  and the seed top-up's idempotency
- `seeding_test.dart` — what a new install starts with
- `date_helpers_test.dart` — month boundaries, leap days, ISO round-tripping, and
  the encryption header check

Tests run against `AppDatabase.forTesting()`, which is an in-memory **unencrypted**
database with the fast pragmas set. The cipher is only exercised on a device,
because `flutter test` links stock SQLite.
