import 'package:drift/drift.dart';
import 'package:finance_db/finance_db.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  group('month totals', () {
    setUp(() => seedSeptember(db));

    test('groups by local month, oldest first', () async {
      final months = await db.watchMonthTotals().first;
      expect(months.map((m) => '${m.year}-${m.month}'), <String>[
        '2026-8',
        '2026-9',
      ]);
      expect(months.first.expenseMinor, 700000);
      expect(months.last.expenseMinor, 180000);
      expect(months.last.incomeMinor, 900000);
      expect(months.last.netMinor, 720000);
    });

    test('files a first-of-month entry in its own month', () async {
      // The bug the local `occurredOn` column exists to prevent: a UTC rollup
      // would move 2026-09-01 into August for anyone east of Greenwich, and the
      // total would quietly disagree with a bank statement.
      final september = (await db.watchMonthTotals().first).last;
      expect(september.month, 9);
      expect(september.incomeMinor, 900000);
    });

    test('reports a net that can go negative', () async {
      await db
          .into(db.transactions)
          .insert(
            entry(
              id: 'huge',
              categoryId: SeedIds.categoryRent,
              amountMinor: 5000000,
              occurredOn: '2026-09-30',
            ),
          );
      expect((await db.watchMonthTotals().first).last.netMinor, lessThan(0));
    });

    test('returns nothing for an empty ledger', () async {
      final fresh = AppDatabase.forTesting();
      expect(await fresh.watchMonthTotals().first, isEmpty);
      await fresh.close();
    });
  });

  group('daily totals', () {
    setUp(() => seedSeptember(db));

    test('groups by day, one series per month on record', () async {
      final days = await db.watchDailyTotals().first;
      final september = days.where((day) => day.monthKey == '2026-09').toList();
      expect(september.map((d) => d.day), <int>[2, 11, 20]);
      expect(september.first.totalMinor, 100000);
      // The fixture also has a 30 August entry, and it comes back in the same
      // read rather than requiring a query per month.
      expect(days.any((day) => day.monthKey == '2026-08'), isTrue);
    });

    test('excludes income', () async {
      final days = await db.watchDailyTotals().first;
      // The 1st carried only income, so it must not appear at all.
      expect(
        days.any((day) => day.monthKey == '2026-09' && day.day == 1),
        isFalse,
      );
    });

    test('a soft-deleted entry disappears from the day series', () async {
      await (db.update(db.transactions)..where((t) => t.id.equals('g1'))).write(
        TransactionsCompanion(deletedAt: Value<DateTime>(DateTime.now())),
      );
      final days = await db.watchDailyTotals().first;
      expect(
        days.any((day) => day.monthKey == '2026-09' && day.day == 2),
        isFalse,
      );
    });
  });

  group('account balances', () {
    test('nets income against expense', () async {
      await db.batch(
        (Batch batch) => batch
          ..insert(
            db.transactions,
            entry(
              id: 'out',
              categoryId: SeedIds.categoryMisc,
              amountMinor: 25000,
              occurredOn: '2026-09-05',
            ),
          )
          ..insert(
            db.transactions,
            entry(
              id: 'in',
              categoryId: SeedIds.categoryIncome,
              amountMinor: 100000,
              occurredOn: '2026-09-06',
              direction: EntryDirection.income,
            ),
          ),
      );

      final hdfc = (await db.watchAccounts().first).firstWhere(
        (a) => a.id == SeedIds.accountHdfc,
      );
      expect(hdfc.netMovementMinor, 75000);
      expect(hdfc.balanceMinor, 75000);
    });

    test('attributes spend to the correct account only', () async {
      await db
          .into(db.transactions)
          .insert(
            entry(
              id: 'card',
              categoryId: SeedIds.categoryShopping,
              accountId: SeedIds.accountCreditCard,
              amountMinor: 40000,
              occurredOn: '2026-09-05',
            ),
          );

      final accounts = await db.watchAccounts().first;
      final card = accounts.firstWhere(
        (a) => a.id == SeedIds.accountCreditCard,
      );
      // A credit card carries a negative balance, which is why the opening
      // balance column is signed.
      expect(card.balanceMinor, -40000);

      final hdfc = accounts.firstWhere((a) => a.id == SeedIds.accountHdfc);
      expect(hdfc.netMovementMinor, 0);
    });
  });

  group('reactivity', () {
    test('a write re-emits dependent queries', () async {
      // Drift invalidates streams whose `readsFrom` tables changed. If this
      // regressed, the UI would silently stop refreshing after a write.
      final emissions = <int>[];
      final subscription = db
          .watchCategorySpend(fromIso: septemberStart, toIso: octoberStart)
          .listen((rows) => emissions.add(rows.length));
      await pumpEventQueue();
      expect(emissions, <int>[0]);

      await db
          .into(db.transactions)
          .insert(
            entry(
              id: 'live',
              categoryId: SeedIds.categoryGroceries,
              amountMinor: 1000,
              occurredOn: '2026-09-09',
            ),
          );
      await pumpEventQueue();

      expect(emissions.last, 1);
      await subscription.cancel();
    });
  });
}
