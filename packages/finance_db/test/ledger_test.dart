import 'package:drift/drift.dart';
import 'package:finance_db/finance_db.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  group('ledger reads', () {
    test('joins category and account names', () async {
      await db
          .into(db.transactions)
          .insert(
            entry(
              id: 't1',
              categoryId: SeedIds.categoryGroceries,
              amountMinor: 45000,
              occurredOn: '2026-09-05',
              payee: 'BigBasket',
            ),
          );

      final ledger = await db.watchLedger().first;
      expect(ledger, hasLength(1));
      final row = ledger.single;
      expect(row.categoryName, 'Groceries');
      expect(row.accountName, 'HDFC Savings');
      expect(row.payee, 'BigBasket');
      expect(row.amountMinor, 45000);
      expect(row.isExpense, isTrue);
      expect(row.isIncome, isFalse);
    });

    test('preserves the exact local date that was entered', () async {
      // Guards against any UTC round-trip shifting the day.
      await db
          .into(db.transactions)
          .insert(
            entry(
              id: 't1',
              categoryId: SeedIds.categoryMisc,
              amountMinor: 1000,
              occurredOn: '2026-09-01',
            ),
          );

      final row = (await db.watchLedger().first).single;
      expect(row.occurredOn, '2026-09-01');
      expect(row.date, DateTime(2026, 9, 1));
      expect(row.date.day, 1);
    });

    test('orders newest first', () async {
      await db.batch(
        (Batch batch) => batch
          ..insert(
            db.transactions,
            entry(
              id: 'older',
              categoryId: SeedIds.categoryMisc,
              amountMinor: 100,
              occurredOn: '2026-09-01',
            ),
          )
          ..insert(
            db.transactions,
            entry(
              id: 'newer',
              categoryId: SeedIds.categoryMisc,
              amountMinor: 200,
              occurredOn: '2026-09-20',
            ),
          ),
      );

      final ledger = await db.watchLedger().first;
      expect(ledger.map((r) => r.id), <String>['newer', 'older']);
    });

    test('honours a limit', () async {
      await db.batch(
        (Batch batch) => batch
          ..insert(
            db.transactions,
            entry(
              id: 'a',
              categoryId: SeedIds.categoryMisc,
              amountMinor: 100,
              occurredOn: '2026-09-01',
            ),
          )
          ..insert(
            db.transactions,
            entry(
              id: 'b',
              categoryId: SeedIds.categoryMisc,
              amountMinor: 200,
              occurredOn: '2026-09-02',
            ),
          ),
      );

      expect(await db.watchLedger(limit: 1).first, hasLength(1));
    });

    test('excludes soft-deleted rows', () async {
      await db
          .into(db.transactions)
          .insert(
            entry(
              id: 'gone',
              categoryId: SeedIds.categoryMisc,
              amountMinor: 500,
              occurredOn: '2026-09-10',
            ),
          );

      await (db.update(
        db.transactions,
      )..where((t) => t.id.equals('gone'))).write(
        TransactionsCompanion(deletedAt: Value<DateTime>(DateTime.now())),
      );

      expect(await db.watchLedger().first, isEmpty);
    });

    test('records income with an unsigned amount and a direction', () async {
      await db
          .into(db.transactions)
          .insert(
            entry(
              id: 'salary',
              categoryId: SeedIds.categoryIncome,
              amountMinor: 8500000,
              occurredOn: '2026-09-01',
              direction: EntryDirection.income,
              payee: 'Salary credit',
            ),
          );

      final row = (await db.watchLedger().first).single;
      // The stored amount is positive; direction carries the sign. Keeping it
      // this way means no code path can flip a spend into income by dropping a
      // minus sign.
      expect(row.amountMinor, 8500000);
      expect(row.isIncome, isTrue);
      expect(row.isExpense, isFalse);
    });
  });

  group('referential integrity', () {
    test('rejects an entry pointing at a missing category', () async {
      expect(
        () => db
            .into(db.transactions)
            .insert(
              entry(
                id: 'orphan',
                categoryId: 'no-such-category',
                amountMinor: 100,
                occurredOn: '2026-09-01',
              ),
            ),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects an entry pointing at a missing account', () async {
      expect(
        () => db
            .into(db.transactions)
            .insert(
              entry(
                id: 'orphan',
                categoryId: SeedIds.categoryMisc,
                accountId: 'no-such-account',
                amountMinor: 100,
                occurredOn: '2026-09-01',
              ),
            ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
