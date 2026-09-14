import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/period_views.dart';
import 'package:finance_app/data/stats_period.dart';
import 'package:finance_db/finance_db.dart' hide CategoryKind;
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// Tier 0.1 and 0.2: a period's income split into spent, invested and left.
///
/// The invariant these lean on hardest is C1: investing is cash out but not
/// consumption, so a composition that folded the two together would understate
/// the savings rate by exactly the amount invested.
void main() {
  /// Income ₹1,00,000, spending ₹40,000, investing ₹20,000, all in September.
  Future<Fixture> compositionFixture() async {
    final fixture = makeFixture();
    for (final (categoryId, amount, day, direction)
        in <(String, int, int, TxDirection)>[
          (SeedIds.categoryIncome, 10000000, 1, TxDirection.income),
          (SeedIds.categoryGroceries, 4000000, 5, TxDirection.expense),
          (SeedIds.categoryMutualFunds, 2000000, 6, TxDirection.investment),
        ]) {
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: categoryId,
        amountMinor: amount,
        date: DateTime(2026, 9, day),
        direction: direction,
        payee: 'Test',
      );
    }
    return fixture;
  }

  group('compositionFor', () {
    test('splits a period into spent, invested and unallocated', () async {
      final fixture = await compositionFixture();
      addTearDown(fixture.dispose);

      final totals = (await fixture.snapshot()).compositionFor(
        StatsRange.containing(StatsPeriod.month, testNow),
      );

      expect(totals.incomeMinor, 10000000);
      expect(totals.expenseMinor, 4000000);
      expect(totals.investmentMinor, 2000000);
      // Income neither consumed nor invested: the change in cash.
      expect(totals.unallocatedMinor, 4000000);
      // Cash out is not the spending figure: ₹60,000 left, ₹40,000 was consumed.
      expect(totals.outflowMinor, 6000000);
      expect(totals.isOverdrawn, isFalse);
      expect(totals.isEmpty, isFalse);
      expect(totals.shareOfIncome(4000000), closeTo(40, 0.01));
      expect(totals.savingsRate, closeTo(60, 0.01));
    });

    test('is the period totals re-arranged, not summed again', () async {
      final fixture = await compositionFixture();
      addTearDown(fixture.dispose);
      final snapshot = await fixture.snapshot();
      final range = StatsRange.containing(StatsPeriod.month, testNow);

      final totals = snapshot.totalsFor(range);
      final composition = snapshot.compositionFor(range);

      expect(composition.incomeMinor, totals.incomeMinor);
      expect(composition.expenseMinor, totals.expenseMinor);
      expect(composition.investmentMinor, totals.investmentMinor);
      // The same definition of "left over" as everywhere else in the app.
      expect(composition.unallocatedMinor, totals.cashLeftMinor);
    });

    test(
      'reports an overdrawn period rather than flooring it at zero',
      () async {
        final fixture = makeFixture();
        addTearDown(fixture.dispose);
        await fixture.repository.addTransaction(
          accountId: SeedIds.accountHdfc,
          categoryId: SeedIds.categoryGroceries,
          amountMinor: 500000,
          date: DateTime(2026, 9, 10),
          direction: TxDirection.expense,
          payee: 'BigBasket',
        );

        final totals = (await fixture.snapshot()).compositionFor(
          StatsRange.containing(StatsPeriod.month, testNow),
        );

        expect(totals.unallocatedMinor, -500000);
        expect(totals.isOverdrawn, isTrue);
        // A share of no income is undefined, not zero: "0%" would read as "you
        // spent none of it", which is the opposite of what happened.
        expect(totals.shareOfIncome(500000), isNull);
        expect(totals.savingsRate, isNull);
      },
    );

    test('excludes both legs of a transfer', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      for (final account in <String>[
        SeedIds.accountHdfc,
        SeedIds.accountCreditCard,
      ]) {
        await fixture.repository.addTransaction(
          accountId: account,
          categoryId: SeedIds.categoryMisc,
          amountMinor: 500000,
          date: DateTime(2026, 9, 8),
          direction: TxDirection.transfer,
          payee: 'Card payment',
        );
      }

      final totals = (await fixture.snapshot()).compositionFor(
        StatsRange.containing(StatsPeriod.month, testNow),
      );

      // Two legs that move money the user already owns. Counting either would
      // inflate one side of the composition (C2).
      expect(totals.isEmpty, isTrue);
      expect(totals.unallocatedMinor, 0);
    });

    test(
      'treats a month with nothing in it as empty, not zero income',
      () async {
        final fixture = await compositionFixture();
        addTearDown(fixture.dispose);

        final totals = (await fixture.snapshot()).compositionFor(
          StatsRange.containing(StatsPeriod.month, DateTime(2026, 8, 1)),
        );

        expect(totals.isEmpty, isTrue);
        expect(totals.shareOfIncome(0), isNull);
      },
    );
  });

  group('compositionByMonthIn', () {
    test('gives one point per month, stopping at the month in progress', () async {
      final fixture = await compositionFixture();
      addTearDown(fixture.dispose);

      final points = (await fixture.snapshot()).compositionByMonthIn(
        StatsRange.containing(StatsPeriod.year, testNow),
      );

      // January through September: the months of 2026 that have happened.
      expect(points, hasLength(9));
      expect(points.first.month, DateTime(2026));
      expect(points.last.month, DateTime(2026, 9));
      expect(points.last.totals.incomeMinor, 10000000);
      // A month with nothing recorded still gets a column, so a gap appears as
      // a short column rather than as a missing month.
      expect(points[1].totals.isEmpty, isTrue);
      expect(points[1].isPartial, isFalse);
    });

    test('marks only the month in progress as partial', () async {
      final fixture = await compositionFixture();
      addTearDown(fixture.dispose);

      final points = (await fixture.snapshot()).compositionByMonthIn(
        StatsRange.containing(StatsPeriod.year, testNow),
      );

      expect(points.last.month, DateTime(2026, 9));
      expect(points.last.isPartial, isTrue);
      expect(points.where((point) => point.isPartial), hasLength(1));
    });

    test('a finished range has no partial month at all', () async {
      final fixture = await compositionFixture();
      addTearDown(fixture.dispose);

      // Q2 2026 is over before the fixture's clock, so nothing in it is the
      // month in progress.
      final points = (await fixture.snapshot()).compositionByMonthIn(
        StatsRange.containing(StatsPeriod.quarter, DateTime(2026, 5, 1)),
      );

      expect(points.map((point) => point.month), <DateTime>[
        DateTime(2026, 4),
        DateTime(2026, 5),
        DateTime(2026, 6),
      ]);
      expect(points.any((point) => point.isPartial), isFalse);
    });

    test('clips an edge month to the range it came from', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      for (final day in <int>[10, 20]) {
        await fixture.repository.addTransaction(
          accountId: SeedIds.accountHdfc,
          categoryId: SeedIds.categoryGroceries,
          amountMinor: 100000,
          date: DateTime(2026, 9, day),
          direction: TxDirection.expense,
          payee: 'BigBasket',
        );
      }

      // The week of the 7th through the 13th: one column, carrying only the
      // 10th's entry even though the 20th is in the same month.
      final points = (await fixture.snapshot()).compositionByMonthIn(
        StatsRange.containing(StatsPeriod.week, testNow),
      );

      expect(points, hasLength(1));
      expect(points.single.month, DateTime(2026, 9));
      expect(points.single.isPartial, isTrue);
      expect(points.single.totals.expenseMinor, 100000);
    });
  });
}
