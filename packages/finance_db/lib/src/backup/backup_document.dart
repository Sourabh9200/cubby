/// A portable snapshot of everything the user has recorded.
///
/// Deliberately transport-agnostic: it holds plain maps whose keys are the same
/// names the database columns use, and it knows nothing about drift, encryption,
/// or files. Extraction, sealing and file handling live elsewhere, which is what
/// lets the whole round trip be tested without a device or a plugin.
///
/// Two version numbers, because they answer different questions:
///
/// * [BackupDocument.formatVersion] is the *shape of this document* — the keys
///   and their value encodings. It changes only when a reader written today
///   could not understand a file written tomorrow.
/// * [BackupDocument.schemaVersion] records which database schema produced it,
///   so a restore can refuse rather than silently drop columns it does not know.
///
/// Nothing here is typed as a drift class on purpose. A backup outlives the
/// schema that produced it, and coupling the format to a generated class would
/// make a routine schema change silently rewrite every old file's meaning.
library;

/// Raised when a backup is not one this build can read.
///
/// A distinct type rather than a bare `FormatException` so the UI can tell the
/// user *what* is wrong — a wrong file is a different problem from a wrong
/// password, and only one of them is worth retrying.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => 'BackupFormatException: $message';
}

/// Everything the app stores, in a form that survives being written to a file.
class BackupDocument {
  const BackupDocument({
    required this.exportedAt,
    required this.schemaVersion,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.recurringRules,
    required this.settings,
  });

  /// Reads a decoded JSON map, rejecting anything this build cannot restore.
  ///
  /// Every failure is a [BackupFormatException] carrying a sentence a user can
  /// act on, because the alternative — a partially applied restore — is worse
  /// than every one of them put together.
  factory BackupDocument.fromJson(Map<String, Object?> json) {
    final format = json['format'];
    if (format != formatTag) {
      throw const BackupFormatException(
        'That file is not a Cubby backup. Choose the .cubby file this app '
        'created.',
      );
    }

    final version = _int(json, 'format_version');
    if (version > formatVersion) {
      throw BackupFormatException(
        'This backup was written by a newer version of Cubby (format $version, '
        'this build reads up to $formatVersion). Update the app and try again.',
      );
    }

    return BackupDocument(
      exportedAt: _dateTime(json, 'exported_at'),
      schemaVersion: _int(json, 'schema_version'),
      accounts: _rows(json, 'accounts'),
      categories: _rows(json, 'categories'),
      transactions: _rows(json, 'transactions'),
      recurringRules: _rows(json, 'recurring_rules'),
      settings: _rows(json, 'settings'),
    );
  }

  /// Marks a file as ours. A restore refuses anything without it, so an
  /// unrelated file chosen by mistake fails with a sentence rather than partway
  /// through deleting the user's ledger.
  static const String formatTag = 'cubby.backup';

  /// The document shape this build writes and understands.
  static const int formatVersion = 1;

  /// When the snapshot was taken, in UTC.
  final DateTime exportedAt;

  /// The database schema that produced this document.
  final int schemaVersion;

  final List<Map<String, Object?>> accounts;
  final List<Map<String, Object?>> categories;
  final List<Map<String, Object?>> transactions;
  final List<Map<String, Object?>> recurringRules;
  final List<Map<String, Object?>> settings;

  /// How many ledger entries the document carries, for the restore summary.
  int get transactionCount => transactions.length;

  Map<String, Object?> toJson() => <String, Object?>{
    'format': formatTag,
    'format_version': formatVersion,
    'schema_version': schemaVersion,
    'exported_at': exportedAt.toUtc().toIso8601String(),
    'accounts': accounts,
    'categories': categories,
    'transactions': transactions,
    'recurring_rules': recurringRules,
    'settings': settings,
  };

  static List<Map<String, Object?>> _rows(
    Map<String, Object?> json,
    String key,
  ) {
    final raw = json[key];
    if (raw is! List) {
      throw BackupFormatException('The backup is missing its "$key" section.');
    }
    return raw
        .map((Object? entry) {
          if (entry is! Map) {
            throw BackupFormatException(
              'The backup\'s "$key" section contains something that is not a row.',
            );
          }
          return <String, Object?>{
            for (final MapEntry<Object?, Object?> field in entry.entries)
              '${field.key}': field.value,
          };
        })
        .toList(growable: false);
  }

  static int _int(Map<String, Object?> json, String key) {
    final raw = json[key];
    if (raw is int) {
      return raw;
    }
    throw BackupFormatException(
      'The backup\'s "$key" is missing or not a number.',
    );
  }

  static DateTime _dateTime(Map<String, Object?> json, String key) {
    final raw = json[key];
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return parsed.toUtc();
      }
    }
    throw BackupFormatException(
      'The backup\'s "$key" is missing or not a timestamp.',
    );
  }
}
