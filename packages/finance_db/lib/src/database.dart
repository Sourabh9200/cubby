import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'seed_data.dart';
import 'seed_keys.dart';
import 'tables.dart';

part 'database.g.dart';

/// The app's encrypted SQLite database.
///
/// Drift is used over raw `sqflite` because every read here is an aggregate
/// over a growing ledger, and drift checks those queries at compile time and
/// generates a verified migration path between schema versions.
@DriftDatabase(
  tables: <Type>[
    Accounts,
    Categories,
    Transactions,
    RecurringRules,
    SettingsEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Wraps an existing executor. Tests pass
  /// [NativeDatabase.memory] here; production passes an encrypted file-backed
  /// one from [openEncrypted].
  AppDatabase(super.executor, {File? file}) : _file = file;

  final File? _file;

  /// The database file, when it is file-backed.
  ///
  /// Exposed so the app can verify the file header really is encrypted. Without
  /// it, the UI could only *claim* encryption.
  File? get file => _file;

  /// Opens the encrypted database at [file].
  ///
  /// [passphrase] must be the value from
  /// `DatabasePassphraseStore.loadOrCreate`, which is a 32-byte random string
  /// held in the platform keystore.
  ///
  /// [requireCipherSupport] is asserted in debug builds. It is switchable
  /// because `flutter test` runs against a plain SQLite build, where the
  /// cipher pragma legitimately does not exist.
  static AppDatabase openEncrypted({
    required File file,
    required String passphrase,
    bool requireCipherSupport = true,
  }) {
    return AppDatabase(
      NativeDatabase.createInBackground(
        file,
        setup: (sqlite.Database raw) {
          if (requireCipherSupport) {
            assert(
              hasCipherSupport(raw),
              'SQLite3MultipleCiphers is not linked, so `PRAGMA key` would be '
              'silently ignored and the database would be written as '
              'plaintext. Check the sqlite3 hook configuration in the '
              'workspace pubspec (source: sqlite3mc).',
            );
          }
          // Must run before any other statement touches the database.
          raw.execute("PRAGMA key = '${escapeSqlLiteral(passphrase)}';");
        },
      ),
      file: file,
    );
  }

  /// Opens an unencrypted in-memory database, for tests only.
  ///
  /// Named to be conspicuous in review: nothing in the app should call this.
  static AppDatabase forTesting() =>
      AppDatabase(NativeDatabase.memory(setup: _fastTestPragmas));

  /// Opens an unencrypted file-backed database, for tests that need to inspect
  /// the bytes on disk (for example the encryption header check).
  ///
  /// Also test-only. The app always uses [openEncrypted].
  static AppDatabase forFile(File file) =>
      AppDatabase(NativeDatabase(file, setup: _fastTestPragmas));

  static void _fastTestPragmas(sqlite.Database raw) {
    // WAL is not meaningful for an in-memory database, but disabling it keeps
    // test runs from creating stray -wal files.
    raw.execute('PRAGMA journal_mode = MEMORY;');
  }

  /// Schema 1 -> 2 added `transactions.is_sample`.
  ///
  /// Existing rows default to false, which is correct: everything written before
  /// this column existed was either the user's or indistinguishable from it, and
  /// mislabelling it as sample would make "erase sample data" a data-loss button.
  ///
  /// Schema 2 -> 3 added the `recurring_rules` table. Purely additive, and
  /// deliberately so: the upgrade must not touch a single ledger row, because the
  /// rows a user already has are the only thing in this database that cannot be
  /// reconstructed. Nothing is materialised by the migration either — an
  /// existing install has no rules, so there is nothing due.
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await seedDefaults(this);
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.addColumn(transactions, transactions.isSample);

        // Backfill. Before this column existed, the sample loader was the only
        // writer of this exact note, so any row carrying it is demo data.
        // Without this, rows loaded by an earlier version would be classified as
        // the user's, and "remove sample data" would silently do nothing for
        // anyone who had already tried the app — the fix would appear broken
        // precisely for the person who reported it.
        await customStatement(
          "UPDATE transactions SET is_sample = 1 WHERE note = 'Sample data';",
        );
      }
      if (from < 3) {
        await m.createTable(recurringRules);
      }
    },
    beforeOpen: (OpeningDetails details) async {
      // Enforce the foreign keys we declared. SQLite leaves them off by
      // default, which would make every `references` clause decorative.
      await customStatement('PRAGMA foreign_keys = ON;');

      // Top up any seed rows this database predates. Version 2 added the
      // investment categories, and without this an existing install would have
      // no way to record an investment at all — no schema migration can add
      // rows, so the seed version is the only mechanism that can.
      final storedSeedVersion = int.tryParse(
        await readSetting(SettingKeys.seedVersion) ?? '',
      );
      if (storedSeedVersion == null || storedSeedVersion < currentSeedVersion) {
        final seeded = await seedMissingDefaults(this);
        if (seeded) {
          await writeSetting(SettingKeys.seedVersion, '$currentSeedVersion');
        }
      }
    },
  );

  /// True when the linked SQLite build supports `PRAGMA key`.
  ///
  /// `PRAGMA cipher` is provided by SQLite3MultipleCiphers and by nothing in
  /// upstream SQLite, so its presence is a reliable signal.
  static bool hasCipherSupport(sqlite.Database raw) {
    try {
      return raw.select('PRAGMA cipher;').isNotEmpty;
    } on sqlite.SqliteException {
      return false;
    }
  }

  /// Escapes a value for single-quoted SQL literal use.
  static String escapeSqlLiteral(String value) => value.replaceAll("'", "''");

  /// Reads [key] from the settings table.
  Future<String?> readSetting(String key) async {
    final row = await (select(
      settingsEntries,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// Writes [key], replacing any previous value.
  Future<void> writeSetting(String key, String value) async {
    await into(settingsEntries).insertOnConflictUpdate(
      SettingsEntriesCompanion.insert(
        key: key,
        value: value,
        updatedAt: DateTime.now(),
      ),
    );
  }
}
