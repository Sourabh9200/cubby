/// Local encrypted storage for the finance app.
///
/// ## Layout
///
/// * [AppDatabase] — drift tables, migrations, and the `PRAGMA key` that makes
///   the file unreadable without the passphrase.
/// * [SecureStoragePassphraseStore] — keeps that passphrase in the platform
///   keystore, not in shared preferences.
/// * Query extensions in `src/queries/` — all aggregation happens in SQL.
///
/// ## The encryption guarantee, and how it is checked
///
/// Encryption is only real if the linked SQLite build supports it. If it does
/// not, `PRAGMA key` is accepted as a **no-op** and the database is written as
/// plaintext with no error raised anywhere — the worst possible failure mode
/// for a feature whose entire purpose is confidentiality.
///
/// Two independent checks guard against it:
///
/// 1. [AppDatabase.openEncrypted] asserts `PRAGMA cipher` exists before it
///    applies the key, in debug builds.
/// 2. [isFileEncrypted] reads the file header and confirms it is *not* the
///    `SQLite format 3\0` magic string. This one runs in release too, so the
///    app can tell the user the truth rather than assume it.
library;

export 'src/database.dart'
    show
        AccountsCompanion,
        AppDatabase,
        CategoriesCompanion,
        RecurringRulesCompanion,
        SettingsEntriesCompanion,
        TransactionsCompanion;
export 'src/database_opener.dart' show DatabaseOpener, OpenResult;
export 'src/passphrase_store.dart'
    show
        InMemoryPassphraseStore,
        PassphraseStore,
        SecureStoragePassphraseStore,
        isFileEncrypted;
export 'src/queries/account_queries.dart' show AccountQueries;
export 'src/queries/category_queries.dart' show CategoryQueries;
export 'src/queries/ledger_queries.dart' show LedgerQueries;
export 'src/queries/month_queries.dart' show MonthQueries;
export 'src/queries/recurring_queries.dart' show RecurringQueries;
export 'src/queries/row_parsing.dart'
    show
        isoDate,
        isoMonth,
        monthEndIso,
        monthStartIso,
        parseRecurrenceFrequency;
export 'src/query_rows.dart'
    show
        AccountRow,
        CategoryRow,
        CategorySpendRow,
        CategoryTrendPoint,
        DailyTotalRow,
        LedgerRow,
        MonthTotalRow,
        RecurringRuleRow;
export 'src/recurring.dart'
    show
        firstOccurrenceAfter,
        materialiseDueRecurring,
        monthlyOccurrence,
        nextOccurrenceAfter;
export 'src/seed_data.dart'
    show currentSeedVersion, seedDefaults, seedMissingDefaults;
export 'src/seed_keys.dart'
    show CategoryColors, CategoryIcons, SeedIds, SettingKeys;
export 'src/tables.dart'
    show
        AccountType,
        Accounts,
        Categories,
        CategoryKind,
        EntryDirection,
        RecurrenceFrequency,
        RecurringRules,
        SettingsEntries,
        Transactions;
