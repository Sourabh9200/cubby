import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Table, TableInfo, TableUpdateQuery;
import 'package:finance_db/finance_db.dart' as db_layer;

import 'backup/backup_crypto.dart';
import 'backup/backup_failure.dart';
import 'finance_repository.dart';
import 'finance_snapshot.dart';
import 'models.dart';
import 'row_mapper.dart';
import 'writers/category_writer.dart';
import 'writers/recurring_writer.dart';
import 'writers/sample_data_writer.dart';
import 'writers/transaction_writer.dart';

/// [FinanceRepository] backed by the encrypted drift database.
///
/// The snapshot is rebuilt from scratch on every change rather than assembled
/// by zipping five independent query streams. Zipping would risk the dashboard
/// rendering a total from one revision beside a donut from another; rebuilding
/// makes that impossible, at the cost of a few extra local reads that SQLite
/// answers in microseconds.
class DriftFinanceRepository implements FinanceRepository {
  DriftFinanceRepository({
    required db_layer.AppDatabase db,
    DateTime Function()? clock,
  }) : db = db,
       _clock = clock ?? DateTime.now,
       _transactions = TransactionWriter(db),
       _categories = CategoryWriter(db),
       _recurring = RecurringWriter(db),
       _sampleData = SampleDataWriter(db);

  final db_layer.AppDatabase db;

  /// Injected so month boundaries are deterministic under test.
  final DateTime Function() _clock;

  final TransactionWriter _transactions;
  final CategoryWriter _categories;
  final RecurringWriter _recurring;
  final SampleDataWriter _sampleData;

  @override
  Stream<FinanceSnapshot> watch() async* {
    yield await buildSnapshot();
    yield* db
        .tableUpdates(
          TableUpdateQuery.onAllTables(<TableInfo<Table, Object?>>[
            db.transactions,
            db.categories,
            db.accounts,
            db.recurringRules,
            db.settingsEntries,
          ]),
        )
        .asyncMap((_) => buildSnapshot());
  }

  /// Reads everything the UI needs in one consistent pass.
  ///
  /// Public so a test can assert on a snapshot without subscribing first.
  Future<FinanceSnapshot> buildSnapshot() async {
    final now = _clock();

    final ledger = await db.watchLedger().first;
    final categoryRows = await db.watchCategories().first;
    final accountRows = await db.watchAccounts().first;
    final monthTotals = await db.watchMonthTotals().first;
    final trend = await db.watchCategoryTrend().first;
    final daily = await db.watchDailyTotals().first;
    final ruleRows = await db.watchRecurringRules().first;

    final spendByMonth = RowMapper.toCategorySpendByMonth(trend);
    // Split from the same read, so the donut and the investing card can never
    // describe different revisions of the ledger.
    final investedByMonth = RowMapper.toCategoryInvestmentByMonth(trend);
    // Income comes from that same read too, so "income this month" and "income
    // by source this month" are arithmetically the same number by construction.
    final incomeByMonth = RowMapper.toCategoryIncomeByMonth(trend);

    return FinanceSnapshot(
      transactions: ledger.map(RowMapper.toTransaction).toList(growable: false),
      categories: categoryRows
          .map(RowMapper.toCategory)
          .toList(growable: false),
      accounts: accountRows
          .map(RowMapper.toAccountBalance)
          .toList(growable: false),
      monthlySummaries: RowMapper.toMonthSummaries(
        totals: monthTotals,
        spendByMonth: spendByMonth,
      ),
      categorySpendByMonth: spendByMonth,
      categoryInvestmentByMonth: investedByMonth,
      categoryIncomeByMonth: incomeByMonth,
      dailySpendByMonth: RowMapper.toDailySpendByMonth(daily),
      recurringRules: ruleRows
          .map(RowMapper.toRecurringRule)
          .toList(growable: false),
      now: now,
    );
  }

  @override
  Future<void> addTransaction({
    required String accountId,
    required String categoryId,
    required int amountMinor,
    required DateTime date,
    required TxDirection direction,
    String payee = '',
    String note = '',
  }) => _transactions.add(
    accountId: accountId,
    categoryId: categoryId,
    amountMinor: amountMinor,
    date: date,
    direction: direction,
    payee: payee,
    note: note,
  );

  @override
  Future<void> updateTransaction({
    required String id,
    required String accountId,
    required String categoryId,
    required int amountMinor,
    required DateTime date,
    required TxDirection direction,
    String payee = '',
    String note = '',
  }) => _transactions.update(
    id: id,
    accountId: accountId,
    categoryId: categoryId,
    amountMinor: amountMinor,
    date: date,
    direction: direction,
    payee: payee,
    note: note,
  );

  @override
  Future<void> deleteTransaction(String id) => _transactions.softDelete(id);

  @override
  Future<void> setCategoryBudget({
    required String categoryId,
    required int budgetMinor,
  }) => _categories.setBudget(categoryId: categoryId, budgetMinor: budgetMinor);

  @override
  Future<void> addCategory({
    required String name,
    required CategoryKind kind,
    required int budgetMinor,
  }) async {
    await _categories.add(name: name, kind: kind, budgetMinor: budgetMinor);
  }

  @override
  Future<void> deleteCategory(String categoryId) =>
      _categories.softDelete(categoryId);

  @override
  Future<void> addRecurringRule({
    required String accountId,
    required String categoryId,
    required int amountMinor,
    required TxDirection direction,
    required DateTime startedOn,
    String payee = '',
    bool postMissedMonths = true,
  }) async {
    await _recurring.add(
      accountId: accountId,
      categoryId: categoryId,
      amountMinor: amountMinor,
      direction: direction,
      startedOn: startedOn,
      payee: payee,
      postMissedMonths: postMissedMonths,
    );
  }

  @override
  Future<void> stopRecurringRule(String ruleId) => _recurring.stop(ruleId);

  @override
  Future<int> loadSampleData() => _sampleData.load();

  @override
  Future<void> eraseTransactions() => _transactions.softDeleteAll();

  @override
  Future<void> eraseSampleData() => _transactions.softDeleteSampleData();

  @override
  Future<bool> verifyEncrypted() async {
    final file = db.file;
    if (file == null) {
      // An in-memory database has no file to inspect, so it is trivially not
      // encrypted. Reporting `true` here would be a lie.
      return false;
    }
    return db_layer.isFileEncrypted(file);
  }

  @override
  Future<Uint8List> exportBackup({required String passphrase}) async {
    final document = await db.exportBackup();
    final clearText = utf8.encode(jsonEncode(document.toJson()));
    try {
      return await BackupCrypto.seal(
        clearText: clearText,
        passphrase: passphrase,
      );
    } on Object catch (error) {
      throw BackupFailure('The backup could not be encrypted: $error');
    }
  }

  @override
  Future<BackupRestoreReport> restoreBackup({
    required Uint8List bytes,
    required String passphrase,
  }) async {
    // Decrypt and validate *before* touching the database. A wrong passphrase or
    // a foreign file must fail while the user's ledger is still intact, not
    // halfway through replacing it.
    final db_layer.BackupDocument document;
    try {
      final clearText = await BackupCrypto.open(
        envelope: bytes,
        passphrase: passphrase,
      );
      document = db_layer.BackupDocument.fromJson(
        jsonDecode(utf8.decode(clearText)) as Map<String, Object?>,
      );
    } on BackupCryptoException catch (error) {
      throw BackupFailure(error.message);
    } on db_layer.BackupFormatException catch (error) {
      throw BackupFailure(error.message);
    } on FormatException {
      throw const BackupFailure('That file is not a readable Cubby backup.');
    }

    try {
      await db.importBackup(document);
    } on db_layer.BackupFormatException catch (error) {
      // A row this build cannot interpret. The replace runs in one transaction,
      // so it rolls back and the existing ledger is left alone.
      throw BackupFailure(error.message);
    }

    return BackupRestoreReport(
      transactions: document.transactionCount,
      categories: document.categories.length,
      accounts: document.accounts.length,
      recurringRules: document.recurringRules.length,
    );
  }

  @override
  Future<bool> appLockEnabled() async =>
      await db.readSetting(db_layer.SettingKeys.appLockEnabled) == 'true';

  @override
  Future<void> setAppLockEnabled(bool enabled) => db.writeSetting(
    db_layer.SettingKeys.appLockEnabled,
    enabled ? 'true' : 'false',
  );
}
