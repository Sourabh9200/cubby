import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/period_views.dart';
import 'package:finance_app/data/stats_period.dart';
import 'package:finance_db/finance_db.dart' hide CategoryKind;
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// Tier 0.3: this August against last August.
///
/// A year-over-year comparison is the one that strips out season, and it is also
/// the easiest to make dishonest: a part-month against a whole one reads as a
/// saving every single time (C6), and a window the ledger did not exist for is
/// not a baseline at all (C7).
void main() {
  Future<void> add(
    Fixture fixture,
    DateTime date,
    int amountMinor,
    TxDirection direction,
  ) => fixture.repository.addTransaction(
    accountId: SeedIds.accountHdfc,
    categoryId: switch (direction) {
      TxDirection.income => SeedIds.categoryIncome,
      TxDirection.investment => SeedIds.categoryMutualFunds,
      _ => SeedIds.categoryGroceries,
    },
    amountMinor: amountMinor,
    date: date,
    direction: direction,
    payee: 'Test',
  );

  group('oneYearEarlier', () {
    test('steps a month to the same month, not 365 days back', () {
      final august = StatsRange.containing(
        StatsPeriod.month,
        DateTime(2026, 8, 5),
      );
      final earlier = august.oneYearEarlier();

      expect(earlier.period, StatsPeriod.month);
      expect(earlier.from, DateTime(2025, 8, 1));
      expect(earlier.to, DateTime(2025, 9, 1));
    });

    test('keeps February February across a leap year', () {
      final february = StatsRange.containing(
        StatsPeriod.month,
        DateTime(2028, 2, 10),
      );
      final earlier = february.oneYearEarlier();

      // Calendar arithmetic: February 2027 is February. Counting 365 days back
      // from 1 March 2028 would land on 2 March 2027.
      expect(earlier.from, DateTime(2027, 2, 1));
      expect(earlier.to, DateTime(2027, 3, 1));
    });

    test('steps a whole year one year', () {
      final year = StatsRange.containing(StatsPeriod.year, testNow);
      expect(year.oneYearEarlier().from, DateTime(2025));
      expect(year.oneYearEarlier().to, DateTime(2026));
    });
  });

  group('yearOverYearFor', () {
    test('compares a finished month with the same month a year earlier', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      // The 1st of August 2025 anchors the history, so last August is covered
      // from its first day.
      await add(fixture, DateTime(2025, 8, 1), 5000000, TxDirection.income);
      await add(fixture, DateTime(2025, 8, 5), 2000000, TxDirection.expense);
      await add(fixture, DateTime(2026, 8, 1), 6000000, TxDirection.income);
      await add(fixture, DateTime(2026, 8, 5), 3000000, TxDirection.expense);
      await add(fixture, DateTime(2026, 8, 6), 1000000, TxDirection.investment);

      final comparison = (await fixture.snapshot()).yearOverYearFor(
        StatsRange.containing(StatsPeriod.month, DateTime(2026, 8, 5)),
      );

      expect(comparison, isNotNull);
      // A month that is over is compared whole against a whole one.
      expect(comparison!.previousScale, 1.0);
      expect(comparison.current.expenseMinor, 3000000);
      expect(comparison.comparableExpenseMinor, 2000000);
      expect(comparison.expenseChangePercent, closeTo(50, 0.01));
      expect(comparison.incomeChangePercent, closeTo(20, 0.01));
      // Nothing was invested last August, so there is no percentage to report:
      // "infinite growth" is not a figure.
      expect(comparison.investmentChangePercent, isNull);
      expect(comparison.comparableInvestmentMinor, 0);
    });

    test('scales last year while the period is still running', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      await add(fixture, DateTime(2025, 9, 1), 5000000, TxDirection.income);
      await add(fixture, DateTime(2025, 9, 15), 3000000, TxDirection.expense);
      await add(fixture, DateTime(2026, 9, 5), 1500000, TxDirection.expense);

      final comparison = (await fixture.snapshot()).yearOverYearFor(
        StatsRange.containing(StatsPeriod.month, testNow),
      );

      expect(comparison, isNotNull);
      // 13 of September's 30 days have happened.
      expect(comparison!.previousScale, closeTo(13 / 30, 0.0001));
      expect(comparison.comparableExpenseMinor, 1300000);
      // Against the whole of last September this would have read as -50%: a
      // saving that never happened (C6).
      expect(comparison.expenseChangePercent, closeTo(15.38, 0.01));
    });

    test('says nothing when the earlier window is not covered', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      // The ledger starts on the 2nd of September 2025.
      await add(fixture, DateTime(2025, 9, 2), 1000000, TxDirection.expense);
      await add(fixture, DateTime(2026, 9, 5), 1500000, TxDirection.expense);

      final snapshot = await fixture.snapshot();
      final september = StatsRange.containing(StatsPeriod.month, testNow);

      // Last September is only covered from its second day, so comparing this
      // September against it would compare a whole month with most of one.
      expect(snapshot.yearOverYearFor(september), isNull);
      expect(snapshot.expenseChangeYearOverYear(september), isNull);

      // The next month's window is covered in full, so the comparison appears
      // as soon as it honestly can.
      final october = StatsRange.containing(
        StatsPeriod.month,
        DateTime(2026, 10, 1),
      );
      expect(snapshot.yearOverYearFor(october), isNotNull);
    });

    test('says nothing on an empty ledger', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      final snapshot = await fixture.snapshot();
      final range = StatsRange.containing(StatsPeriod.month, testNow);

      expect(snapshot.yearOverYearFor(range), isNull);
      expect(snapshot.expenseChangeYearOverYear(range), isNull);
    });
  });
}
