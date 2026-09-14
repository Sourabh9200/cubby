import 'package:drift/drift.dart';
import 'package:finance_db/finance_db.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Investment behaviour.
///
/// These tests exist because "investment" is the one concept in the schema that
/// is easy to implement as a special case of something else and be subtly wrong.
/// Treating a mutual fund contribution as an expense keeps every screen
/// rendering, every chart drawing, and every test passing — while making the
/// spending total and the savings rate wrong by exactly the amount the user
/// saved. The invariants below are what stop that.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  group('investments', () {
    test('do not count as spending, but do leave the account', () async {
      await seedSeptember(db);

      final before = (await db.watchMonthTotals().first).last;
      expect(before.expenseMinor, 180000);
      expect(before.investmentMinor, 0);

      await db
          .into(db.transactions)
          .insert(
            entry(
              id: 'sip',
              categoryId: SeedIds.categoryMutualFunds,
              amountMinor: 2000000,
              occurredOn: '2026-09-05',
              direction: EntryDirection.investment,
            ),
          );

      final after = (await db.watchMonthTotals().first).last;

      // The invariant the whole feature rests on. A ₹20,000 SIP must not read as
      // ₹20,000 of spending, or the savings rate falls by exactly the amount the
      // user saved.
      expect(after.expenseMinor, 180000);
      expect(after.investmentMinor, 2000000);

      // Income less consumption is unchanged: that money was kept, just not in
      // the current account.
      expect(after.netMinor, 720000);
      // Cash, on the other hand, did go down.
      expect(after.cashLeftMinor, 720000 - 2000000);

      // And it is a real entry, not a phantom.
      expect(after.txnCount, before.txnCount + 1);
      // Five seeded rows plus the SIP, including the August one that sits
      // outside the September window.
      expect(await db.watchLedger().first, hasLength(6));
    });

    test('reduce the account balance like any other outflow', () async {
      await db
          .into(db.transactions)
          .insert(
            entry(
              id: 'sip',
              categoryId: SeedIds.categoryMutualFunds,
              amountMinor: 2000000,
              occurredOn: '2026-09-05',
              direction: EntryDirection.investment,
            ),
          );

      final account = (await db.watchAccounts().first).firstWhere(
        (candidate) => candidate.id == SeedIds.accountHdfc,
      );
      // This is the one place an investment behaves exactly like an expense. A
      // balance that ignored it would overstate the money available to spend.
      expect(account.netMovementMinor, -2000000);
      expect(account.balanceMinor, -2000000);
    });

    test('are reported per month in their own column', () async {
      await db.batch(
        (Batch batch) => batch
          ..insert(
            db.transactions,
            entry(
              id: 's1',
              categoryId: SeedIds.categoryMutualFunds,
              amountMinor: 2000000,
              occurredOn: '2026-08-05',
              direction: EntryDirection.investment,
            ),
          )
          ..insert(
            db.transactions,
            entry(
              id: 's2',
              categoryId: SeedIds.categoryMutualFunds,
              amountMinor: 2500000,
              occurredOn: '2026-09-05',
              direction: EntryDirection.investment,
            ),
          ),
      );

      final months = await db.watchMonthTotals().first;
      expect(months.map((m) => m.investmentMinor), <int>[2000000, 2500000]);
      // A month containing only investments has no spending at all. Reporting it
      // as zero spend is correct: the user consumed nothing.
      expect(months.map((m) => m.expenseMinor), <int>[0, 0]);
    });

    test('are separated from spending in the trend query', () async {
      await db.batch(
        (Batch batch) => batch
          ..insert(
            db.transactions,
            entry(
              id: 'g',
              categoryId: SeedIds.categoryGroceries,
              amountMinor: 100000,
              occurredOn: '2026-09-02',
            ),
          )
          ..insert(
            db.transactions,
            entry(
              id: 'sip',
              categoryId: SeedIds.categoryMutualFunds,
              amountMinor: 2000000,
              occurredOn: '2026-09-05',
              direction: EntryDirection.investment,
            ),
          ),
      );

      final trend = await db.watchCategoryTrend().first;
      final byKey = <String, CategoryTrendPoint>{
        for (final point in trend)
          '${point.categoryName}:${point.direction.name}': point,
      };

      expect(byKey['Groceries:expense']!.totalMinor, 100000);
      expect(byKey['Mutual Funds:investment']!.totalMinor, 2000000);

      // The spending series must not contain the fund contribution, or the donut
      // would list "Mutual Funds" as a top spending category.
      expect(
        trend
            .where((point) => point.direction == EntryDirection.expense)
            .map((point) => point.categoryName),
        isNot(contains('Mutual Funds')),
      );
    });

    test('are excluded from the daily pace curve', () async {
      await db.batch(
        (Batch batch) => batch
          ..insert(
            db.transactions,
            entry(
              id: 'sip',
              categoryId: SeedIds.categoryMutualFunds,
              amountMinor: 2000000,
              occurredOn: '2026-09-05',
              direction: EntryDirection.investment,
            ),
          )
          ..insert(
            db.transactions,
            entry(
              id: 'g',
              categoryId: SeedIds.categoryGroceries,
              amountMinor: 45000,
              occurredOn: '2026-09-05',
            ),
          ),
      );

      final daily = await db.watchDailyTotals('2026-09').first;
      // Only the groceries. Counting the SIP here would make a diligent saver
      // look like a big spender on the day their SIP lands.
      expect(daily.single.day, 5);
      expect(daily.single.totalMinor, 45000);
    });

    test('per-category totals can be asked for by kind', () async {
      await db.batch(
        (Batch batch) => batch
          ..insert(
            db.transactions,
            entry(
              id: 'g',
              categoryId: SeedIds.categoryGroceries,
              amountMinor: 100000,
              occurredOn: '2026-09-02',
            ),
          )
          ..insert(
            db.transactions,
            entry(
              id: 'sip',
              categoryId: SeedIds.categoryMutualFunds,
              amountMinor: 2000000,
              occurredOn: '2026-09-05',
              direction: EntryDirection.investment,
            ),
          ),
      );

      final spending = await db
          .watchCategorySpend(fromIso: septemberStart, toIso: octoberStart)
          .first;
      expect(spending.map((row) => row.categoryName), <String>['Groceries']);
      expect(spending.single.kind, CategoryKind.expense);

      final investing = await db
          .watchCategorySpend(
            fromIso: septemberStart,
            toIso: octoberStart,
            kind: CategoryKind.investment,
          )
          .first;
      expect(investing.map((row) => row.categoryName), <String>[
        'Mutual Funds',
      ]);
      expect(investing.single.kind, CategoryKind.investment);
      expect(investing.single.totalMinor, 2000000);
    });

    test('read as investments in the ledger, not as expenses', () async {
      await db
          .into(db.transactions)
          .insert(
            entry(
              id: 'sip',
              categoryId: SeedIds.categoryMutualFunds,
              amountMinor: 2000000,
              occurredOn: '2026-09-05',
              direction: EntryDirection.investment,
            ),
          );

      final row = (await db.watchLedger().first).single;
      expect(row.isInvestment, isTrue);
      expect(row.isExpense, isFalse);
      expect(row.isIncome, isFalse);
      expect(row.categoryName, 'Mutual Funds');
    });

    test('an unknown direction from a newer version falls back safely', () async {
      // A row written by a future release must not crash this one. Reading it as
      // an expense is a deliberate degradation: the app stays usable and the
      // user can still see their history, rather than meeting an exception.
      await db.customStatement(
        'INSERT INTO transactions (id, account_id, category_id, amount_minor, '
        'currency, direction, occurred_on, occurred_at, payee, note, '
        'is_sample, created_at, updated_at) VALUES '
        "('future', ?, ?, 1000, 'INR', 'rebalancing', '2026-09-05', "
        '1780000000, \'\', \'\', 0, 1780000000, 1780000000)',
        <Object?>[SeedIds.accountHdfc, SeedIds.categoryMutualFunds],
      );

      final row = (await db.watchLedger().first).single;
      expect(row.direction, EntryDirection.expense);
    });
  });
}
