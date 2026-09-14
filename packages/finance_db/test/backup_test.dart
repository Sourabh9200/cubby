import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:finance_db/finance_db.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// The backup round trip.
///
/// Asserted with plain `test` against an in-memory database, which is only
/// possible because the backup is a logical dump of rows rather than a copy of
/// the SQLite file: the cipher this app ships with does not exist in the stock
/// SQLite build `flutter test` links against, so a file-level copy could never
/// be tested here at all.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  /// Puts a representative slice of everything in the database: an edited
  /// budget, income, spending, a sample row, and a recurring rule.
  Future<void> seedEverything(AppDatabase target) async {
    await target
        .into(target.transactions)
        .insert(
          entry(
            id: 'txn-1',
            categoryId: SeedIds.categoryGroceries,
            amountMinor: 45000,
            occurredOn: '2026-09-05',
            payee: 'BigBasket',
          ),
        );
    await target
        .into(target.transactions)
        .insert(
          entry(
            id: 'txn-2',
            categoryId: SeedIds.categoryIncome,
            amountMinor: 8000000,
            occurredOn: '2026-09-01',
            direction: EntryDirection.income,
            payee: 'Salary credit',
          ),
        );
    await target
        .into(target.transactions)
        .insert(
          entry(
            id: 'txn-sample',
            categoryId: SeedIds.categoryRent,
            amountMinor: 1800000,
            occurredOn: '2026-09-02',
            payee: 'Sample rent',
          ),
        );
    // The shared `entry()` helper has no `is_sample` argument, so the flag is
    // applied here — the restore must preserve it (C9).
    await (target.update(target.transactions)
          ..where((t) => t.id.equals('txn-sample')))
        .write(const TransactionsCompanion(isSample: Value<bool>(true)));
    await (target.update(
      target.categories,
    )..where((c) => c.id.equals(SeedIds.categoryGroceries))).write(
      const CategoriesCompanion(monthlyBudgetMinor: Value<int>(1500000)),
    );
    await target
        .into(target.recurringRules)
        .insert(
          RecurringRulesCompanion.insert(
            id: 'rule-1',
            accountId: SeedIds.accountHdfc,
            categoryId: SeedIds.categoryRent,
            currency: 'INR',
            direction: EntryDirection.expense,
            frequency: RecurrenceFrequency.monthly,
            dayOfMonth: 2,
            nextDueOn: '2026-10-02',
            startedOn: '2026-09-02',
            createdAt: DateTime.utc(2026, 9, 2),
            updatedAt: DateTime.utc(2026, 9, 2),
          ),
        );
  }

  /// Writes a document to JSON and reads it back, so the test proves the format
  /// survives a real file rather than just an in-memory hand-off.
  BackupDocument throughJson(BackupDocument document) =>
      BackupDocument.fromJson(
        jsonDecode(jsonEncode(document.toJson())) as Map<String, Object?>,
      );

  test(
    'restores the ledger, budgets and rules into a fresh database',
    () async {
      await seedEverything(db);

      final restored = AppDatabase.forTesting();
      addTearDown(restored.close);
      await restored.importBackup(throughJson(await db.exportBackup()));

      final ledger = await restored.watchLedger().first;
      expect(ledger, hasLength(3));

      final groceries = ledger.firstWhere((row) => row.id == 'txn-1');
      expect(groceries.payee, 'BigBasket');
      expect(groceries.amountMinor, 45000);
      expect(groceries.categoryName, 'Groceries');
      expect(groceries.accountName, 'HDFC Savings');
      // The exact day, not a UTC-shifted neighbour (C13).
      expect(groceries.occurredOn, '2026-09-05');

      expect(
        ledger.firstWhere((row) => row.id == 'txn-2').direction,
        EntryDirection.income,
      );
      // A sample row stays a sample row, so "remove sample data" still works
      // after a restore (C9).
      expect(
        ledger.firstWhere((row) => row.id == 'txn-sample').isSample,
        isTrue,
      );

      final categoryRows = await restored.watchCategories().first;
      expect(
        categoryRows
            .firstWhere((row) => row.id == SeedIds.categoryGroceries)
            .budgetMinor,
        1500000,
      );

      final rules = await restored.watchRecurringRules().first;
      expect(rules, hasLength(1));
      expect(rules.single.id, 'rule-1');
      expect(rules.single.nextDueOn, '2026-10-02');
      expect(rules.single.dayOfMonth, 2);
    },
  );

  test('replaces everything that was already there', () async {
    await seedEverything(db);
    final document = throughJson(await db.exportBackup());

    // A database that has drifted: the same seeds, plus a row of its own. A
    // merge would leave this behind, so the count is the assertion.
    await db
        .into(db.transactions)
        .insert(
          entry(
            id: 'extra-1',
            categoryId: SeedIds.categoryDining,
            amountMinor: 25000,
            occurredOn: '2026-09-09',
          ),
        );
    expect(await db.watchLedger().first, hasLength(4));

    await db.importBackup(document);

    final ledger = await db.watchLedger().first;
    expect(ledger, hasLength(3));
    expect(ledger.map((row) => row.id), isNot(contains('extra-1')));
  });

  test('keeps a soft-deleted entry deleted', () async {
    await seedEverything(db);
    await (db.update(
      db.transactions,
    )..where((t) => t.id.equals('txn-1'))).write(
      TransactionsCompanion(deletedAt: Value(DateTime.utc(2026, 9, 6))),
    );

    final restored = AppDatabase.forTesting();
    addTearDown(restored.close);
    await restored.importBackup(throughJson(await db.exportBackup()));

    final ledger = await restored.watchLedger().first;
    expect(ledger.map((row) => row.id), isNot(contains('txn-1')));
  });

  test('refuses a file that is not one of ours', () {
    expect(
      () => BackupDocument.fromJson(<String, Object?>{'format': 'some.other'}),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('refuses a backup written by a newer version', () {
    expect(
      () => BackupDocument.fromJson(<String, Object?>{
        'format': BackupDocument.formatTag,
        'format_version': BackupDocument.formatVersion + 1,
        'schema_version': 3,
        'exported_at': '2026-09-14T00:00:00.000Z',
        'accounts': <Object?>[],
        'categories': <Object?>[],
        'transactions': <Object?>[],
        'recurring_rules': <Object?>[],
        'settings': <Object?>[],
      }),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('refuses a row carrying a value it cannot interpret', () async {
    await seedEverything(db);
    final json = jsonDecode(
      jsonEncode((await db.exportBackup()).toJson()),
    ) as Map<String, Object?>;
    // A value a future build might write, which this one has no meaning for.
    // Mapping it onto `expense` would corrupt the ledger quietly, so it is
    // refused instead.
    final rows = json['transactions']! as List<Object?>;
    (rows.first as Map<String, Object?>)['direction'] = 'teleport';

    final restored = AppDatabase.forTesting();
    addTearDown(restored.close);
    await expectLater(
      restored.importBackup(BackupDocument.fromJson(json)),
      throwsA(isA<BackupFormatException>()),
    );

    // And nothing was written: the deletes roll back with the failed batch, so
    // a refused restore cannot leave an empty ledger behind.
    expect(await restored.watchLedger().first, hasLength(0));
    expect(await restored.watchCategories().first, isNotEmpty);
  });
}
