import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/period_views.dart';
import 'package:finance_app/data/stats_period.dart';
import 'package:finance_db/finance_db.dart' hide CategoryKind;
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// Tier 0.5: which days the ledger spends on, and which days it is silent.
///
/// Every figure here is a statement about the ledger rather than about behaviour
/// (C11), and the count of how many of each weekday the range covers is what
/// stops a partial first week from making a Monday look quiet for free.
void main() {
  /// ₹100 on Monday 7 September, ₹300 on Friday the 11th, ₹50 on Saturday the
  /// 12th, plus an investment and an income that must not count.
  Future<Fixture> rhythmFixture() async {
    final fixture = makeFixture();
    for (final (date, amount, categoryId, direction)
        in <(DateTime, int, String, TxDirection)>[
          (
            DateTime(2026, 9, 7),
            10000,
            SeedIds.categoryGroceries,
            TxDirection.expense,
          ),
          (
            DateTime(2026, 9, 10),
            300000,
            SeedIds.categoryMutualFunds,
            TxDirection.investment,
          ),
          (
            DateTime(2026, 9, 1),
            8000000,
            SeedIds.categoryIncome,
            TxDirection.income,
          ),
          (
            DateTime(2026, 9, 11),
            30000,
            SeedIds.categoryGroceries,
            TxDirection.expense,
          ),
          (
            DateTime(2026, 9, 12),
            5000,
            SeedIds.categoryDining,
            TxDirection.expense,
          ),
        ]) {
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: categoryId,
        amountMinor: amount,
        date: date,
        direction: direction,
        payee: 'Test',
      );
    }
    return fixture;
  }

  group('spendingRhythmIn', () {
    test('totals by weekday and finds the busiest day', () async {
      final fixture = await rhythmFixture();
      addTearDown(fixture.dispose);

      final rhythm = (await fixture.snapshot()).spendingRhythmIn(
        StatsRange.containing(StatsPeriod.month, testNow),
      );

      expect(rhythm.hasData, isTrue);
      expect(rhythm.totalMinor, 45000);
      expect(rhythm.byWeekday, hasLength(7));
      // Monday first, as DateTime.weekday orders them.
      expect(rhythm.byWeekday.first.weekday, DateTime.monday);
      expect(rhythm.byWeekday.first.totalMinor, 10000);
      expect(rhythm.byWeekday.first.days, 1);
      // Friday carries the largest average — ₹300 over the two Fridays the
      // range covers — so it is the busiest day.
      expect(rhythm.busiest?.weekday, DateTime.friday);
      expect(rhythm.busiest?.averageMinor, 15000);
    });

    test('counts the days that have happened, not the whole month', () async {
      final fixture = await rhythmFixture();
      addTearDown(fixture.dispose);

      final rhythm = (await fixture.snapshot()).spendingRhythmIn(
        StatsRange.containing(StatsPeriod.month, testNow),
      );

      // September is 30 days long and today is the 13th, so ten of its days have
      // no entry yet — including seventeen that have not happened.
      expect(rhythm.recordedDays, 13);
      expect(rhythm.activeDays, 3);
      expect(rhythm.quietDays, 10);
      expect(rhythm.averagePerActiveDayMinor, 15000);
    });

    test('leaves investing and income out', () async {
      final fixture = await rhythmFixture();
      addTearDown(fixture.dispose);

      final rhythm = (await fixture.snapshot()).spendingRhythmIn(
        StatsRange.containing(StatsPeriod.month, testNow),
      );

      // The SIP and the salary are ₹38,000 of movement, and neither is a day
      // this ledger spent on (C1).
      expect(rhythm.totalMinor, 45000);
      expect(rhythm.activeDays, 3);
    });

    test('a finished month counts every day in it', () async {
      final fixture = await rhythmFixture();
      addTearDown(fixture.dispose);

      final rhythm = (await fixture.snapshot()).spendingRhythmIn(
        StatsRange.containing(StatsPeriod.month, DateTime(2026, 8, 10)),
      );

      expect(rhythm.recordedDays, 31);
      expect(rhythm.activeDays, 0);
      expect(rhythm.quietDays, 31);
      expect(rhythm.hasData, isFalse);
      expect(rhythm.busiest, isNull);
      expect(rhythm.averagePerActiveDayMinor, 0);
    });

    test('a weekday the range does not cover is not the quietest', () async {
      final fixture = await rhythmFixture();
      addTearDown(fixture.dispose);

      // Friday the 11th through Sunday the 13th: Monday, Tuesday, Wednesday and
      // Thursday are outside the range entirely.
      final rhythm = (await fixture.snapshot()).spendingRhythmIn(
        StatsRange(
          period: StatsPeriod.week,
          from: DateTime(2026, 9, 11),
          to: DateTime(2026, 9, 14),
        ),
      );

      expect(rhythm.recordedDays, 3);
      expect(rhythm.byWeekday.first.days, 0);
      expect(rhythm.byWeekday.first.totalMinor, 0);
      expect(rhythm.busiest?.weekday, DateTime.friday);
    });

    test('an empty ledger has no rhythm rather than a quiet one', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      final rhythm = (await fixture.snapshot()).spendingRhythmIn(
        StatsRange.containing(StatsPeriod.year, testNow),
      );

      expect(rhythm.hasData, isFalse);
      expect(rhythm.totalMinor, 0);
      expect(rhythm.averagePerActiveDayMinor, 0);
    });
  });
}
