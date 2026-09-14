import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/period_views.dart';
import 'package:finance_app/data/snapshot_analytics.dart';
import 'package:finance_app/data/stats_period.dart';
import 'package:finance_db/finance_db.dart' hide CategoryKind;
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// The arithmetic behind the two Tier 3 screens.
///
/// A day and a custom range are new lengths for the period engine, and a year in
/// review is a new reading of figures that already existed. Most of this is
/// tested here rather than through the screens, because the interesting cases are
/// the ones a tap is awkward to reach: a window that is only half covered, a year
/// with nothing in it, a payee that is frequent but not large.
void main() {
  group('a day, and a range the user picked', () {
    test('a day covers exactly one day, and stepping crosses a month', () {
      final range = StatsRange.containing(
        StatsPeriod.day,
        DateTime(2026, 9, 13, 12),
      );
      expect(range.from, DateTime(2026, 9, 13));
      expect(range.to, DateTime(2026, 9, 14));
      expect(range.days, 1);
      expect(range.contains(DateTime(2026, 9, 13, 23, 59)), isTrue);
      // The end is exclusive, so the next day is not in this day.
      expect(range.contains(DateTime(2026, 9, 14)), isFalse);

      expect(range.step(1).from, DateTime(2026, 9, 14));
      expect(range.step(-1).from, DateTime(2026, 9, 12));
      // Across a month boundary — the case a fixed 24-hour duration would get
      // wrong, and the reason every period is calendar arithmetic.
      final firstOfOctober = StatsRange.containing(
        StatsPeriod.day,
        DateTime(2026, 10, 1),
      );
      expect(firstOfOctober.step(-1).from, DateTime(2026, 9, 30));
      expect(range.oneYearEarlier().from, DateTime(2025, 9, 13));
    });

    test('a custom range steps by its own length, and normalises its bounds', () {
      final range = StatsRange.custom(
        from: DateTime(2026, 8, 10),
        to: DateTime(2026, 9, 1),
      );
      expect(range.days, 22);

      // The same 22 days immediately before, which is the only comparison that
      // holds the span length constant.
      final previous = range.step(-1);
      expect(previous.from, DateTime(2026, 7, 19));
      expect(previous.to, DateTime(2026, 8, 10));
      expect(previous.days, 22);
      expect(previous.step(1).sameDatesAs(range), isTrue);

      // A time of day cannot leak into a label or a sum.
      final noisy = StatsRange.custom(
        from: DateTime(2026, 8, 10, 23, 30),
        to: DateTime(2026, 9, 1, 5),
      );
      expect(noisy.from, DateTime(2026, 8, 10));
      expect(noisy.to, DateTime(2026, 9, 1));
    });

    test('neither a day nor a custom range scales a monthly limit', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      await seedMinimal(fixture);
      await fixture.repository.setCategoryBudget(
        categoryId: SeedIds.categoryGroceries,
        budgetMinor: 100000,
      );
      final snapshot = await fixture.snapshot();

      expect(StatsPeriod.day.monthsCovered, 0);
      expect(StatsPeriod.custom.monthsCovered, 0);
      expect(
        snapshot.budgetStatusesIn(
          StatsRange.containing(StatsPeriod.day, testNow),
        ),
        isEmpty,
      );
      expect(
        snapshot.budgetStatusesIn(
          StatsRange.custom(
            from: DateTime(2026, 8, 10),
            to: DateTime(2026, 9, 1),
          ),
        ),
        isEmpty,
      );
      // A month still scales, so the two empty lists above are about the length
      // of the window and not about the limit being missing (C4).
      expect(
        snapshot.budgetStatusesIn(
          StatsRange.containing(StatsPeriod.month, testNow),
        ),
        isNotEmpty,
      );
    });
  });

  group('the previous period', () {
    test('is compared whole once over, and scaled while it runs', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      for (final (date, amount) in <(DateTime, int)>[
        // July from its first day, so July is a month this ledger covers
        // completely and the August comparison has something whole to compare
        // against (C7).
        (DateTime(2026, 7, 1), 100000),
        (DateTime(2026, 8, 5), 200000),
        (DateTime(2026, 9, 5), 10000),
      ]) {
        await fixture.repository.addTransaction(
          accountId: SeedIds.accountHdfc,
          categoryId: SeedIds.categoryGroceries,
          amountMinor: amount,
          date: date,
          direction: TxDirection.expense,
          payee: 'BigBasket',
        );
      }
      final snapshot = await fixture.snapshot();

      // August is over, so it is compared against a whole July: +100%.
      final august = snapshot.previousPeriodComparison(
        StatsRange.containing(StatsPeriod.month, DateTime(2026, 8)),
      );
      expect(august, isNotNull);
      expect(august!.expenseChangePercent, closeTo(100, 0.01));

      // September is 13 of its 30 days old, so August is scaled to the same
      // point in it before comparing. Against a whole August, a part-month would
      // read as a large saving every single time (C6).
      final scaled = 200000 * (13 / 30);
      final september = snapshot.previousPeriodComparison(
        StatsRange.containing(StatsPeriod.month, testNow),
      );
      expect(september, isNotNull);
      expect(september!.comparableExpenseMinor, closeTo(scaled, 1));
      expect(
        september.expenseChangePercent,
        closeTo((10000 - scaled) / scaled * 100, 0.01),
      );
    });

    test('is withheld when the earlier window is only half covered', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      // The ledger begins on the 20th of August: August is not a month anyone
      // recorded, so it is not something to compare September against (C7).
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryGroceries,
        amountMinor: 50000,
        date: DateTime(2026, 8, 20),
        direction: TxDirection.expense,
        payee: 'BigBasket',
      );
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryGroceries,
        amountMinor: 10000,
        date: DateTime(2026, 9, 5),
        direction: TxDirection.expense,
        payee: 'BigBasket',
      );
      final snapshot = await fixture.snapshot();

      expect(
        snapshot.previousPeriodComparison(
          StatsRange.containing(StatsPeriod.month, testNow),
        ),
        isNull,
      );
      // The month before the ledger began has nothing to compare with either,
      // whatever length the window is.
      expect(
        snapshot.previousPeriodComparison(
          StatsRange.containing(StatsPeriod.month, DateTime(2026, 8)),
        ),
        isNull,
      );
      // The overview's looser delta still answers, by design: it is read as a
      // nudge beside a headline, and its behaviour is pinned elsewhere.
      expect(
        snapshot.expenseChangeForRange(
          StatsRange.containing(StatsPeriod.month, testNow),
        ),
        isNotNull,
      );
    });
  });

  group('the most frequent payee', () {
    test('is not the largest one', () {
      final snapshot = snapshotWith(
        transactions: <Transaction>[
          expenseOn(DateTime(2026, 9, 1), 1800000, payee: 'Rent'),
          for (var day = 3; day <= 9; day += 2)
            expenseOn(DateTime(2026, 9, day), 15000, payee: 'Cafe Coffee Day'),
        ],
      );
      final range = StatsRange.containing(StatsPeriod.month, testNow);

      expect(snapshot.topPayeesIn(range).first.payee, 'Rent');
      expect(snapshot.payeeTotalsIn(range).length, 2);
      final frequent = snapshot.mostFrequentPayeeIn(range);
      expect(frequent!.payee, 'Cafe Coffee Day');
      expect(frequent.count, 4);
      expect(frequent.totalMinor, 60000);
    });

    test('is null when nothing was paid, and stable when counts tie', () {
      expect(
        snapshotWith().mostFrequentPayeeIn(
          StatsRange.containing(StatsPeriod.month, testNow),
        ),
        isNull,
      );

      final snapshot = snapshotWith(
        transactions: <Transaction>[
          expenseOn(DateTime(2026, 9, 2), 30000, payee: 'Zomato'),
          expenseOn(DateTime(2026, 9, 3), 50000, payee: 'Swiggy'),
        ],
      );
      // One entry each, so the larger total wins and the answer does not change
      // between rebuilds.
      final range = StatsRange.containing(StatsPeriod.month, testNow);
      expect(snapshot.mostFrequentPayeeIn(range)!.payee, 'Swiggy');
      expect(snapshot.mostFrequentPayeeIn(range)!.payee, 'Swiggy');
    });
  });

  group('a year in review', () {
    /// Twenty-one months of history, so a year is complete, the year before it
    /// is complete, and a comparison is possible — which is the case the review
    /// is written for. Amounts step by month so the biggest month is a known one.
    Future<Fixture> withYears() async {
      final fixture = makeFixture();
      for (
        var month = DateTime(2025);
        month.isBefore(DateTime(2026, 10));
        month = DateTime(month.year, month.month + 1)
      ) {
        await fixture.repository.addTransaction(
          accountId: SeedIds.accountHdfc,
          categoryId: SeedIds.categoryGroceries,
          amountMinor: 100000 + month.month * 1000,
          date: month,
          direction: TxDirection.expense,
          payee: 'BigBasket',
        );
      }
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryIncome,
        amountMinor: 5000000,
        date: DateTime(2026, 1, 1),
        direction: TxDirection.income,
        payee: 'Salary credit',
      );
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryMutualFunds,
        amountMinor: 2000000,
        date: DateTime(2026, 3, 1),
        direction: TxDirection.investment,
        payee: 'Fund',
      );
      await fixture.repository.setCategoryBudget(
        categoryId: SeedIds.categoryGroceries,
        budgetMinor: 105000,
      );
      await fixture.repository.addRecurringRule(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryRent,
        amountMinor: 1800000,
        direction: TxDirection.expense,
        startedOn: testNow,
        payee: 'Monthly rent transfer',
      );
      return fixture;
    }

    test('reads its figures off the sums the other screens use', () async {
      final fixture = await withYears();
      addTearDown(fixture.dispose);
      final snapshot = await fixture.snapshot();
      final review = snapshot.yearInReview(2026);

      expect(review.year, 2026);
      expect(review.range.from, DateTime(2026));
      expect(review.isComplete, isFalse);
      expect(review.isEmpty, isFalse);
      expect(review.entries, 11);

      // Nine months of groceries at 100000 + month × 1000, plus the salary and
      // the fund contribution.
      expect(review.totals.expenseMinor, 945000);
      expect(review.totals.incomeMinor, 5000000);
      expect(review.totals.investmentMinor, 2000000);
      expect(
        review.totals.savingsRate,
        closeTo((5000000 - 945000) / 5000000 * 100, 0.01),
      );
      expect(review.totals.investmentRate, closeTo(40, 0.01));
      expect(review.monthsRecorded, 9);

      expect(review.biggestMonth!.month, DateTime(2026, 9));
      expect(review.biggestMonth!.totalMinor, 109000);
      expect(review.topCategory!.category, 'Groceries');
      expect(review.largestPayee!.payee, 'BigBasket');
      expect(review.largestPayee!.count, 9);
      expect(review.frequentPayee!.payee, 'BigBasket');

      // Every month of the year so far has groceries and a limit; five of them
      // are inside the ₹1,050 limit and four are over it.
      expect(review.hasLimitRecord, isTrue);
      expect(review.monthsComparedToLimits, 9);
      expect(review.monthsInsideLimits, 5);
      expect(review.stayedInsideEveryMonth, isFalse);

      // A standing rule is a figure about now, carried into a review of a year
      // that did not record it.
      expect(review.committedMonthlyMinor, 1800000);

      // 2025 is inside the ledger in full, so the comparison appears — with the
      // previous year scaled to the same point of the year, because this one is
      // still running (C6).
      final elapsed = review.range.elapsedFraction(testNow);
      final lastYear = (1278000 * elapsed).round();
      expect(review.change, isNotNull);
      expect(review.change!.comparableExpenseMinor, lastYear);
      expect(
        review.change!.expenseChangePercent,
        closeTo((945000 - lastYear) / lastYear * 100, 0.01),
      );
    });

    test(
      'a complete year has no change figure without a year behind it',
      () async {
        final fixture = await withYears();
        addTearDown(fixture.dispose);
        final snapshot = await fixture.snapshot();
        final review = snapshot.yearInReview(2025);

        expect(review.isComplete, isTrue);
        expect(review.totals.expenseMinor, 1278000);
        expect(review.entries, 12);
        expect(review.biggestMonth!.month, DateTime(2025, 12));
        // The comparison needs 2024, which this ledger does not reach (C7).
        expect(review.change, isNull);
      },
    );

    test('a year with nothing in it says nothing at all', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      final review = (await fixture.snapshot()).yearInReview(2026);

      expect(review.isEmpty, isTrue);
      expect(review.entries, 0);
      expect(review.monthsRecorded, 0);
      expect(review.biggestMonth, isNull);
      expect(review.topCategory, isNull);
      expect(review.largestPayee, isNull);
      expect(review.frequentPayee, isNull);
      expect(review.change, isNull);
      // Nothing was measured against a limit, so a streak is not reported even
      // though "0 of 0 months over" would be arithmetically true.
      expect(review.hasLimitRecord, isFalse);
      expect(review.stayedInsideEveryMonth, isFalse);
      expect(review.totals.savingsRate, isNull);
    });
  });
}
