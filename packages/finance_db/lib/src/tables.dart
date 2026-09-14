import 'package:drift/drift.dart';

/// What kind of account money sits in.
///
/// Kept as an enum rather than free text so a typo cannot create a fourth,
/// silently-empty account type in reports.
enum AccountType { bank, cash, creditCard, wallet }

/// Whether a category represents money going out, coming in, or being set aside.
///
/// `investment` is deliberately a third kind rather than a flavour of expense.
/// Money moved into a mutual fund is not consumed — it is still yours, just held
/// somewhere less liquid. Recording it as an expense would inflate spending and
/// understate the savings rate by exactly the amount invested, which is the
/// single most misleading error a personal finance app can make.
enum CategoryKind { expense, income, investment }

/// Direction of a ledger entry.
///
/// `transfer` exists so the two legs of a credit-card payment can be recorded
/// without counting as both income and expense, which is the single most common
/// way a finance app's totals go wrong.
///
/// `investment` is cash out — it reduces an account balance like an expense — but
/// it is *not* consumption, so every aggregate that means "spending" excludes it
/// and every aggregate that means "cash" includes it. The direction carries that
/// distinction so no query has to join categories to recover it.
enum EntryDirection { expense, income, transfer, investment }

/// Accounts money is held in.
@TableIndex(name: 'idx_accounts_sort', columns: {#sortOrder})
class Accounts extends Table {
  /// UUID v4. Not an autoincrement integer, so that imported data and any
  /// future multi-device sync can never collide on a primary key.
  TextColumn get id => text()();

  TextColumn get name => text().withLength(min: 1, max: 60)();

  TextColumn get type => textEnum<AccountType>()();

  TextColumn get currency => text().withLength(min: 3, max: 3)();

  /// Opening balance in minor units. Signed, because a credit card starts
  /// negative.
  IntColumn get openingBalanceMinor =>
      integer().withDefault(const Constant(0))();

  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft delete. Hard-deleting a row that transactions still reference would
  /// either cascade unexpectedly or orphan history.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Spending and income categories.
@TableIndex(name: 'idx_categories_sort', columns: {#sortOrder})
class Categories extends Table {
  TextColumn get id => text()();

  TextColumn get name => text().withLength(min: 1, max: 60)();

  TextColumn get kind => textEnum<CategoryKind>()();

  /// A lookup key such as `groceries`, resolved to a constant `IconData` in the
  /// app.
  ///
  /// Storing a raw code point would force the UI to build `IconData` at runtime,
  /// and Flutter's release icon tree-shaking rejects non-constant `IconData`.
  /// A string key keeps the build shakable.
  TextColumn get iconKey => text()();

  /// A lookup key for a palette slot, resolved to a `Color` in the app for the
  /// same reason.
  TextColumn get colorKey => text()();

  /// Recurring monthly budget in minor units. Zero means unbudgeted.
  IntColumn get monthlyBudgetMinor =>
      integer().withDefault(const Constant(0))();

  /// System categories ship with the app and cannot be deleted, only renamed.
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// The ledger.
@TableIndex(name: 'idx_txn_occurred_on', columns: {#occurredOn})
@TableIndex(
  name: 'idx_txn_category_occurred',
  columns: {#categoryId, #occurredOn},
)
@TableIndex(
  name: 'idx_txn_account_occurred',
  columns: {#accountId, #occurredOn},
)
class Transactions extends Table {
  TextColumn get id => text()();

  TextColumn get accountId =>
      text().references(Accounts, #id, onDelete: KeyAction.restrict)();

  TextColumn get categoryId =>
      text().references(Categories, #id, onDelete: KeyAction.restrict)();

  /// Always positive. [direction] carries the sign, so no code path can
  /// accidentally record a spend as income by omitting a minus.
  IntColumn get amountMinor => integer().withDefault(const Constant(0))();

  TextColumn get currency => text().withLength(min: 3, max: 3)();

  TextColumn get direction => textEnum<EntryDirection>()();

  /// The authoritative date for grouping and filtering, in **local** time,
  /// formatted `YYYY-MM-DD`.
  ///
  /// This column exists to avoid a specific, silent bug. Drift stores
  /// `DateTime` as UTC epoch seconds, so `strftime(..., 'unixepoch')` would
  /// bucket transactions by UTC months. For anyone east of Greenwich that
  /// misfiles transactions dated the 1st of a month into the previous month,
  /// and it is invisible until a total disagrees with a bank statement.
  ///
  /// ISO date strings also compare correctly with plain `>=`/`<`, so range
  /// filters stay index-friendly.
  TextColumn get occurredOn => text().withLength(min: 10, max: 10)();

  /// Precise instant, retained for future time-of-day analysis. Never used for
  /// month or day grouping; [occurredOn] is authoritative for that.
  DateTimeColumn get occurredAt => dateTime()();

  /// Merchant or counterparty, as free text. This is the field the PII layer
  /// treats as most identifying, which is why it never leaves the device.
  TextColumn get payee => text().withDefault(const Constant(''))();

  TextColumn get note => text().withDefault(const Constant(''))();

  /// Links the two legs of a transfer so neither counts as spend.
  TextColumn get transferGroupId => text().nullable()();

  /// True for rows created by "Load sample data".
  ///
  /// A dedicated column rather than a marker in `note`, because erasing the
  /// sample set must never touch a row the user typed. Keying that decision off
  /// free text the user can also write would eventually delete real data.
  BoolColumn get isSample => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// How often a recurring rule posts.
///
/// Only monthly so far. Rent, a systematic investment plan, a salary and a
/// subscription are all monthly, and weekly or yearly recurrence needs its own
/// anchor arithmetic — day-of-week, leap years — that would be guesswork to add
/// before anyone has asked for it. Stored as text, so adding a second frequency
/// is a data change rather than a migration of every existing rule.
enum RecurrenceFrequency { monthly }

/// A template that posts an entry into the ledger every [frequency].
///
/// A rule rather than a set of pre-written future rows. Rows dated in the future
/// would distort every month total from the moment the rule was created — the
/// exact opposite of what someone means by "this repeats" — and every aggregate
/// would have to learn to exclude them. Instead an occurrence is written into
/// `transactions` when it falls due, so the ledger stays the single source of
/// truth and every existing query, chart and total keeps working unchanged.
class RecurringRules extends Table {
  /// UUID v4, like every other row the user creates.
  TextColumn get id => text()();

  TextColumn get accountId =>
      text().references(Accounts, #id, onDelete: KeyAction.restrict)();

  TextColumn get categoryId =>
      text().references(Categories, #id, onDelete: KeyAction.restrict)();

  /// Always positive. [direction] carries the sign, exactly as on the ledger, so
  /// a rule cannot post an expense as income by losing a minus.
  IntColumn get amountMinor => integer().withDefault(const Constant(0))();

  TextColumn get currency => text().withLength(min: 3, max: 3)();

  /// Derived from the category's kind when the rule is created, then stored: a
  /// rule whose category is later re-kindled should keep posting what the user
  /// set up.
  TextColumn get direction => textEnum<EntryDirection>()();

  TextColumn get payee => text().withDefault(const Constant(''))();

  TextColumn get note => text().withDefault(const Constant(''))();

  TextColumn get frequency => textEnum<RecurrenceFrequency>()();

  /// Day of the month the entry falls on, 1-31.
  ///
  /// A day past the end of a short month clamps to that month's last day, so a
  /// rule on the 31st posts on the 30th in April and the 28th in February rather
  /// than being skipped for a month or sliding into the next one.
  IntColumn get dayOfMonth => integer()();

  /// The next occurrence still to post, as a local ISO date.
  ///
  /// This is the whole idempotency mechanism. Posting an occurrence advances it
  /// in the same transaction that writes the row, so a restart, a crash, or an
  /// app opened twice cannot post the same month's rent twice.
  TextColumn get nextDueOn => text().withLength(min: 10, max: 10)();

  /// When the rule started, for display. Its first posted occurrence is the
  /// month after this — the entry it was created from is already in the ledger.
  TextColumn get startedOn => text().withLength(min: 10, max: 10)();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft delete, which is how a rule is stopped. Occurrences already posted are
  /// ordinary ledger entries and are deliberately left alone: stopping a rule
  /// means "not again", not "erase the rent you already paid".
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Key/value settings.
///
/// A table rather than shared preferences so that settings are covered by the
/// same encrypted file as everything else, and are included in a future
/// encrypted backup without a second mechanism.
class SettingsEntries extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}
