import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';
import 'backup_document.dart';

/// Whole-database export and import, in the app's own format.
///
/// This is a *logical* dump, not a copy of the SQLite file, and that is
/// deliberate. The file is encrypted with a key held in the platform keystore,
/// so a copied file is worthless the moment the app is reinstalled — the key
/// dies with it. Rows, by contrast, can be re-written into a fresh database on
/// any device.
///
/// It also means the round trip is testable with plain `test` against
/// `AppDatabase.forTesting()`, which a file-level copy never could be: the
/// cipher pragma does not exist in the stock SQLite build the test suite runs
/// against.
extension BackupQueries on AppDatabase {
  /// Reads every table into a document.
  Future<BackupDocument> exportBackup() async {
    final accountRows = await select(accounts).get();
    final categoryRows = await select(categories).get();
    final transactionRows = await select(transactions).get();
    final ruleRows = await select(recurringRules).get();
    final settingRows = await select(settingsEntries).get();

    return BackupDocument(
      exportedAt: DateTime.now().toUtc(),
      schemaVersion: schemaVersion,
      accounts: accountRows.map(_accountToMap).toList(growable: false),
      categories: categoryRows.map(_categoryToMap).toList(growable: false),
      transactions: transactionRows
          .map(_transactionToMap)
          .toList(growable: false),
      recurringRules: ruleRows.map(_ruleToMap).toList(growable: false),
      settings: settingRows.map(_settingToMap).toList(growable: false),
    );
  }

  /// Replaces the entire contents of the database with [document].
  ///
  /// Replace rather than merge, and in one transaction: a restore that merged
  /// would leave the user with a blend of two ledgers that no total could
  /// explain, and one that failed halfway would leave a database that is
  /// neither. Either the whole snapshot lands or nothing changes.
  ///
  /// The delete order is not cosmetic. A transaction references both an account
  /// and a category with `RESTRICT`, so removing a parent before its children
  /// throws rather than cascading.
  Future<void> importBackup(BackupDocument document) async {
    await transaction(() async {
      await delete(transactions).go();
      await delete(recurringRules).go();
      await delete(categories).go();
      await delete(accounts).go();
      await delete(settingsEntries).go();

      await batch((Batch batch) {
        // Parents before children on the way back in, for the same reason.
        batch
          ..insertAll(
            accounts,
            document.accounts.map(_accountCompanion).toList(growable: false),
          )
          ..insertAll(
            categories,
            document.categories.map(_categoryCompanion).toList(growable: false),
          )
          ..insertAll(
            settingsEntries,
            document.settings.map(_settingCompanion).toList(growable: false),
          )
          ..insertAll(
            recurringRules,
            document.recurringRules.map(_ruleCompanion).toList(growable: false),
          )
          ..insertAll(
            transactions,
            document.transactions
                .map(_transactionCompanion)
                .toList(growable: false),
          );
      });
    });
  }
}

// ---------------------------------------------------------------------------
// Export: rows to JSON maps.
//
// Keys mirror the column names rather than the Dart field names, so a backup
// can be read beside the schema without a translation step. Timestamps are
// written as UTC ISO-8601 and the date-only columns are already `YYYY-MM-DD`,
// which means a backup does not depend on how drift happens to encode a
// `DateTime` on disk.
// ---------------------------------------------------------------------------

Map<String, Object?> _accountToMap(Account row) => <String, Object?>{
  'id': row.id,
  'name': row.name,
  'type': row.type.name,
  'currency': row.currency,
  'opening_balance_minor': row.openingBalanceMinor,
  'is_archived': row.isArchived,
  'sort_order': row.sortOrder,
  'created_at': row.createdAt.toUtc().toIso8601String(),
  'updated_at': row.updatedAt.toUtc().toIso8601String(),
  'deleted_at': row.deletedAt?.toUtc().toIso8601String(),
};

Map<String, Object?> _categoryToMap(Category row) => <String, Object?>{
  'id': row.id,
  'name': row.name,
  'kind': row.kind.name,
  'icon_key': row.iconKey,
  'color_key': row.colorKey,
  'monthly_budget_minor': row.monthlyBudgetMinor,
  'is_system': row.isSystem,
  'sort_order': row.sortOrder,
  'created_at': row.createdAt.toUtc().toIso8601String(),
  'updated_at': row.updatedAt.toUtc().toIso8601String(),
  'deleted_at': row.deletedAt?.toUtc().toIso8601String(),
};

Map<String, Object?> _transactionToMap(Transaction row) => <String, Object?>{
  'id': row.id,
  'account_id': row.accountId,
  'category_id': row.categoryId,
  'amount_minor': row.amountMinor,
  'currency': row.currency,
  'direction': row.direction.name,
  'occurred_on': row.occurredOn,
  'occurred_at': row.occurredAt.toUtc().toIso8601String(),
  'payee': row.payee,
  'note': row.note,
  'transfer_group_id': row.transferGroupId,
  'is_sample': row.isSample,
  'created_at': row.createdAt.toUtc().toIso8601String(),
  'updated_at': row.updatedAt.toUtc().toIso8601String(),
  'deleted_at': row.deletedAt?.toUtc().toIso8601String(),
};

Map<String, Object?> _ruleToMap(RecurringRule row) => <String, Object?>{
  'id': row.id,
  'account_id': row.accountId,
  'category_id': row.categoryId,
  'amount_minor': row.amountMinor,
  'currency': row.currency,
  'direction': row.direction.name,
  'payee': row.payee,
  'note': row.note,
  'frequency': row.frequency.name,
  'day_of_month': row.dayOfMonth,
  'next_due_on': row.nextDueOn,
  'started_on': row.startedOn,
  'created_at': row.createdAt.toUtc().toIso8601String(),
  'updated_at': row.updatedAt.toUtc().toIso8601String(),
  'deleted_at': row.deletedAt?.toUtc().toIso8601String(),
};

Map<String, Object?> _settingToMap(SettingsEntry row) => <String, Object?>{
  'key': row.key,
  'value': row.value,
  'updated_at': row.updatedAt.toUtc().toIso8601String(),
};

// ---------------------------------------------------------------------------
// Import: JSON maps to companions.
//
// Every accessor is strict. The lenient `parseDirection`-style helpers in
// `queries/row_parsing.dart` fall back to a default so a row written by a newer
// app cannot crash an older one reading its *own* database. A backup is a
// different situation: an unknown value there means we are about to write
// something we did not understand, and inventing `expense` for it would corrupt
// the ledger quietly. So this refuses instead.
// ---------------------------------------------------------------------------

String _string(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is String) {
    return value;
  }
  throw BackupFormatException('A backup row is missing its "$key" text.');
}

String? _stringOrNull(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value == null || value is String) {
    return value as String?;
  }
  throw BackupFormatException('A backup row\'s "$key" is not text.');
}

int _int(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is int) {
    return value;
  }
  throw BackupFormatException('A backup row is missing its "$key" number.');
}

bool _bool(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is bool) {
    return value;
  }
  throw BackupFormatException('A backup row is missing its "$key" flag.');
}

DateTime _dateTime(Map<String, Object?> row, String key) {
  final parsed = DateTime.tryParse(_string(row, key));
  if (parsed == null) {
    throw BackupFormatException('A backup row\'s "$key" is not a timestamp.');
  }
  return parsed.toUtc();
}

DateTime? _dateTimeOrNull(Map<String, Object?> row, String key) {
  final raw = _stringOrNull(row, key);
  if (raw == null) {
    return null;
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw BackupFormatException('A backup row\'s "$key" is not a timestamp.');
  }
  return parsed.toUtc();
}

T _enumValue<T extends Enum>(
  List<T> values,
  Map<String, Object?> row,
  String key,
) {
  final raw = row[key];
  for (final value in values) {
    if (value.name == raw) {
      return value;
    }
  }
  throw BackupFormatException(
    'A backup row has an "$key" this version of Cubby does not recognise '
    '("$raw").',
  );
}

AccountsCompanion _accountCompanion(Map<String, Object?> row) =>
    AccountsCompanion(
      id: Value<String>(_string(row, 'id')),
      name: Value<String>(_string(row, 'name')),
      type: Value<AccountType>(_enumValue(AccountType.values, row, 'type')),
      currency: Value<String>(_string(row, 'currency')),
      openingBalanceMinor: Value<int>(_int(row, 'opening_balance_minor')),
      isArchived: Value<bool>(_bool(row, 'is_archived')),
      sortOrder: Value<int>(_int(row, 'sort_order')),
      createdAt: Value<DateTime>(_dateTime(row, 'created_at')),
      updatedAt: Value<DateTime>(_dateTime(row, 'updated_at')),
      deletedAt: Value<DateTime?>(_dateTimeOrNull(row, 'deleted_at')),
    );

CategoriesCompanion _categoryCompanion(Map<String, Object?> row) =>
    CategoriesCompanion(
      id: Value<String>(_string(row, 'id')),
      name: Value<String>(_string(row, 'name')),
      kind: Value<CategoryKind>(_enumValue(CategoryKind.values, row, 'kind')),
      iconKey: Value<String>(_string(row, 'icon_key')),
      colorKey: Value<String>(_string(row, 'color_key')),
      monthlyBudgetMinor: Value<int>(_int(row, 'monthly_budget_minor')),
      isSystem: Value<bool>(_bool(row, 'is_system')),
      sortOrder: Value<int>(_int(row, 'sort_order')),
      createdAt: Value<DateTime>(_dateTime(row, 'created_at')),
      updatedAt: Value<DateTime>(_dateTime(row, 'updated_at')),
      deletedAt: Value<DateTime?>(_dateTimeOrNull(row, 'deleted_at')),
    );

SettingsEntriesCompanion _settingCompanion(Map<String, Object?> row) =>
    SettingsEntriesCompanion(
      key: Value<String>(_string(row, 'key')),
      value: Value<String>(_string(row, 'value')),
      updatedAt: Value<DateTime>(_dateTime(row, 'updated_at')),
    );

RecurringRulesCompanion _ruleCompanion(Map<String, Object?> row) =>
    RecurringRulesCompanion(
      id: Value<String>(_string(row, 'id')),
      accountId: Value<String>(_string(row, 'account_id')),
      categoryId: Value<String>(_string(row, 'category_id')),
      amountMinor: Value<int>(_int(row, 'amount_minor')),
      currency: Value<String>(_string(row, 'currency')),
      direction: Value<EntryDirection>(
        _enumValue(EntryDirection.values, row, 'direction'),
      ),
      payee: Value<String>(_string(row, 'payee')),
      note: Value<String>(_string(row, 'note')),
      frequency: Value<RecurrenceFrequency>(
        _enumValue(RecurrenceFrequency.values, row, 'frequency'),
      ),
      dayOfMonth: Value<int>(_int(row, 'day_of_month')),
      nextDueOn: Value<String>(_string(row, 'next_due_on')),
      startedOn: Value<String>(_string(row, 'started_on')),
      createdAt: Value<DateTime>(_dateTime(row, 'created_at')),
      updatedAt: Value<DateTime>(_dateTime(row, 'updated_at')),
      deletedAt: Value<DateTime?>(_dateTimeOrNull(row, 'deleted_at')),
    );

TransactionsCompanion _transactionCompanion(Map<String, Object?> row) =>
    TransactionsCompanion(
      id: Value<String>(_string(row, 'id')),
      accountId: Value<String>(_string(row, 'account_id')),
      categoryId: Value<String>(_string(row, 'category_id')),
      amountMinor: Value<int>(_int(row, 'amount_minor')),
      currency: Value<String>(_string(row, 'currency')),
      direction: Value<EntryDirection>(
        _enumValue(EntryDirection.values, row, 'direction'),
      ),
      occurredOn: Value<String>(_string(row, 'occurred_on')),
      occurredAt: Value<DateTime>(_dateTime(row, 'occurred_at')),
      payee: Value<String>(_string(row, 'payee')),
      note: Value<String>(_string(row, 'note')),
      transferGroupId: Value<String?>(_stringOrNull(row, 'transfer_group_id')),
      isSample: Value<bool>(_bool(row, 'is_sample')),
      createdAt: Value<DateTime>(_dateTime(row, 'created_at')),
      updatedAt: Value<DateTime>(_dateTime(row, 'updated_at')),
      deletedAt: Value<DateTime?>(_dateTimeOrNull(row, 'deleted_at')),
    );
