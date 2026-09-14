import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';
import 'passphrase_store.dart';
import 'queries/category_queries.dart';
import 'recurring.dart';

/// Opens the app's encrypted database.
///
/// Kept separate from [AppDatabase] so the database package does not need to
/// know about Flutter's plugin registries or the app's file layout.
class DatabaseOpener {
  const DatabaseOpener._();

  /// File name of the encrypted database in the app's private documents
  /// directory.
  static const String databaseFileName = 'finance.sqlite';

  /// Opens the database, generating a passphrase on first run.
  ///
  /// Returns the database together with whether the file on disk is genuinely
  /// encrypted, so the caller can surface the truth rather than assume it.
  static Future<OpenResult> open({
    PassphraseStore? passphraseStore,
    bool requireCipherSupport = kDebugMode,
  }) async {
    final store = passphraseStore ?? SecureStoragePassphraseStore();
    final passphrase = await store.loadOrCreate();
    final file = await _databaseFile();

    final database = AppDatabase.openEncrypted(
      file: file,
      passphrase: passphrase,
      requireCipherSupport: requireCipherSupport,
    );

    // Post anything that fell due while the app was closed, before the first
    // read. Doing it here rather than from a screen means every screen sees the
    // same ledger, and a month cannot render without the rent that has already
    // been paid. Idempotent: posting an occurrence advances the rule's due date
    // in the same write.
    await materialiseDueRecurring(database, today: DateTime.now());

    // Force a real read so the file is created before we inspect its header.
    await database.watchCategories().first;
    final encrypted = await isFileEncrypted(file);

    return OpenResult(
      database: database,
      isEncrypted: encrypted,
      filePath: file.path,
    );
  }

  /// Where the database lives. The app documents directory is private to the
  /// app on Android, so another app cannot read it even without encryption.
  static Future<File> _databaseFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, databaseFileName));
  }

  /// Opens an in-memory, unencrypted database. For tests only.
  static AppDatabase openInMemory() => AppDatabase.forTesting();
}

/// The result of opening the database.
class OpenResult {
  const OpenResult({
    required this.database,
    required this.isEncrypted,
    required this.filePath,
  });

  final AppDatabase database;

  /// True when the file header is not the plaintext SQLite magic string.
  final bool isEncrypted;

  final String filePath;
}
