import 'package:finance_app/app.dart';
import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/period_views.dart';
import 'package:finance_app/data/stats_period.dart';
import 'package:finance_db/finance_db.dart' hide CategoryKind;
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// The overview's period selector: week, month, quarter, year.
///
/// The invariant these lean on hardest is that the four lengths are one
/// arithmetic over different bounds. A quarter that did not equal the sum of its
/// months would mean two screens disagreeing about the user's money, which is the
/// one thing a finance app cannot do.
void main() {
  /// One grocery entry in each month of Q3 2026: ₹1,000 in July, ₹2,000 in
  /// August, ₹3,000 in September.
  Future<Fixture> quarterFixture() async {
    final fixture = makeFixture();
    for (final (date, amount) in <(DateTime, int)>[
      (DateTime(2026, 7, 15), 100000),
      (DateTime(2026, 8, 5), 200000),
      // Inside the week of 7–13 September, which the tests below also use.
      (DateTime(2026, 9, 10), 300000),
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
    return fixture;
  }

  group('period boundaries', () {
    test('a week runs Monday to Sunday', () {
      // 13 September 2026 is a Sunday, so the week containing it starts on the
      // 7th. A week anchored on any other day would file a Sunday entry into the
      // wrong week.
      final week = StatsRange.containing(
        StatsPeriod.week,
        DateTime(2026, 9, 13),
      );
      expect(week.from, DateTime(2026, 9, 7));
      expect(week.to, DateTime(2026, 9, 14));
      expect(week.days, 7);
    });

    test('a week spans a year boundary without breaking', () {
      // 1 January 2027 is a Friday, so its week starts in the previous year.
      final week = StatsRange.containing(
        StatsPeriod.week,
        DateTime(2027, 1, 1),
      );
      expect(week.from, DateTime(2026, 12, 28));
      expect(week.to, DateTime(2027, 1, 4));
    });

    test('quarters start in January, April, July and October', () {
      expect(
        StatsRange.containing(StatsPeriod.quarter, DateTime(2026, 2, 9)).from,
        DateTime(2026, 1, 1),
      );
      expect(
        StatsRange.containing(StatsPeriod.quarter, DateTime(2026, 5, 31)).from,
        DateTime(2026, 4, 1),
      );
      final q3 = StatsRange.containing(
        StatsPeriod.quarter,
        DateTime(2026, 9, 13),
      );
      expect(q3.from, DateTime(2026, 7, 1));
      expect(q3.to, DateTime(2026, 10, 1));
      expect(q3.days, 92);
    });

    test('a year runs January to January', () {
      final year = StatsRange.containing(
        StatsPeriod.year,
        DateTime(2026, 9, 13),
      );
      expect(year.from, DateTime(2026));
      expect(year.to, DateTime(2027));
    });

    test('stepping moves one whole period, not a number of days', () {
      final september = StatsRange.containing(
        StatsPeriod.month,
        DateTime(2026, 9, 13),
      );
      expect(september.step(-1).from, DateTime(2026, 8, 1));
      // Back over a year boundary keeps the length right.
      expect(
        StatsRange.containing(
          StatsPeriod.month,
          DateTime(2026, 1, 9),
        ).step(-1).from,
        DateTime(2025, 12, 1),
      );
      expect(
        StatsRange.containing(
          StatsPeriod.quarter,
          DateTime(2026, 1, 9),
        ).step(-1).from,
        DateTime(2025, 10, 1),
      );
      expect(
        StatsRange.containing(
          StatsPeriod.week,
          DateTime(2026, 9, 13),
        ).step(-1).from,
        DateTime(2026, 8, 31),
      );
    });
  });

  group('totals for a period', () {
    test('a quarter equals the sum of its months', () async {
      final fixture = await quarterFixture();
      addTearDown(fixture.dispose);
      final snapshot = await fixture.snapshot();

      final july = snapshot.totalsFor(
        StatsRange.containing(StatsPeriod.month, DateTime(2026, 7, 1)),
      );
      final august = snapshot.totalsFor(
        StatsRange.containing(StatsPeriod.month, DateTime(2026, 8, 1)),
      );
      final september = snapshot.totalsFor(
        StatsRange.containing(StatsPeriod.month, DateTime(2026, 9, 1)),
      );
      final quarter = snapshot.totalsFor(
        StatsRange.containing(StatsPeriod.quarter, DateTime(2026, 9, 13)),
      );

      expect(july.expenseMinor, 100000);
      expect(august.expenseMinor, 200000);
      expect(september.expenseMinor, 300000);
      expect(
        quarter.expenseMinor,
        july.expenseMinor + august.expenseMinor + september.expenseMinor,
      );
    });

    test('a year equals the sum of its quarters', () async {
      final fixture = await quarterFixture();
      addTearDown(fixture.dispose);
      final snapshot = await fixture.snapshot();

      final year = snapshot.totalsFor(
        StatsRange.containing(StatsPeriod.year, DateTime(2026, 9, 13)),
      );
      final quarters = <int>[1, 4, 7, 10]
          .map(
            (month) => snapshot
                .totalsFor(
                  StatsRange.containing(
                    StatsPeriod.quarter,
                    DateTime(2026, month),
                  ),
                )
                .expenseMinor,
          )
          .fold(0, (sum, value) => sum + value);

      expect(year.expenseMinor, quarters);
      expect(year.expenseMinor, 600000);
    });

    test('a week counts its own days and nobody else\'s', () async {
      final fixture = await quarterFixture();
      addTearDown(fixture.dispose);
      final snapshot = await fixture.snapshot();

      final week = StatsRange.containing(
        StatsPeriod.week,
        DateTime(2026, 9, 13),
      );
      expect(week.contains(DateTime(2026, 9, 7)), isTrue);
      expect(week.contains(DateTime(2026, 9, 10)), isTrue);
      // The Sunday before belongs to the previous week.
      expect(week.contains(DateTime(2026, 9, 6)), isFalse);
      expect(snapshot.totalsFor(week).expenseMinor, 300000);
      expect(
        snapshot.totalsFor(week.step(-1)).expenseMinor,
        0,
        reason: 'the previous week has nothing in it',
      );
    });

    test('the breakdown and the outliers cover only the period shown', () async {
      final fixture = await quarterFixture();
      addTearDown(fixture.dispose);
      final snapshot = await fixture.snapshot();

      final week = StatsRange.containing(
        StatsPeriod.week,
        DateTime(2026, 9, 13),
      );
      final quarter = StatsRange.containing(
        StatsPeriod.quarter,
        DateTime(2026, 9, 13),
      );

      expect(snapshot.spendIn(week).single.totalMinor, 300000);
      expect(snapshot.spendIn(quarter).single.totalMinor, 600000);
      expect(
        snapshot.topExpensesIn(quarter).map((txn) => txn.amountMinor),
        <int>[300000, 200000, 100000],
      );
      // September alone sees only its own entry, however small the others are.
      expect(
        snapshot
            .topExpensesIn(
              StatsRange.containing(StatsPeriod.month, DateTime(2026, 9, 1)),
            )
            .map((txn) => txn.amountMinor),
        <int>[300000],
      );
      // A period with nothing in it reports nothing, not a zero row.
      expect(snapshot.spendIn(week.step(-1)), isEmpty);
      expect(snapshot.topExpensesIn(week.step(-1)), isEmpty);
      expect(snapshot.incomeIn(week), isEmpty);
    });
  });

  group('budgets and comparisons per period', () {
    test('a monthly limit scales by the whole months in the period', () async {
      final fixture = await quarterFixture();
      addTearDown(fixture.dispose);
      final snapshot = await fixture.snapshot();

      // Groceries carries the seeded ₹9,000 limit and has ₹6,000 against it in
      // Q3: three months of limit, one quarter of spending.
      final quarter = snapshot.budgetStatusesIn(
        StatsRange.containing(StatsPeriod.quarter, DateTime(2026, 9, 13)),
      );
      final groceries = quarter.firstWhere(
        (status) => status.category == 'Groceries',
      );
      expect(groceries.budgetMinor, 900000 * 3);
      expect(groceries.spentMinor, 600000);

      // A month is unscaled, exactly as it was before periods existed.
      final september = snapshot.budgetStatusesIn(
        StatsRange.containing(StatsPeriod.month, DateTime(2026, 9, 1)),
      );
      final septemberGroceries = september.firstWhere(
        (status) => status.category == 'Groceries',
      );
      expect(septemberGroceries.budgetMinor, 900000);
      expect(septemberGroceries.spentMinor, 300000);
    });

    test('a week reports no budget rows at all', () async {
      final fixture = await quarterFixture();
      addTearDown(fixture.dispose);

      final week = StatsRange.containing(
        StatsPeriod.week,
        DateTime(2026, 9, 13),
      );
      // Zero rather than a stretched figure: a week holds no whole month, so any
      // limit shown against it would be invented. The screen says so instead.
      expect(week.period.monthsCovered, 0);
      expect((await fixture.snapshot()).budgetStatusesIn(week), isEmpty);
      expect((await fixture.snapshot()).investmentTargetsIn(week), isEmpty);
    });

    test(
      'a finished period is compared whole, one in progress scaled',
      () async {
        final fixture = makeFixture();
        addTearDown(fixture.dispose);
        for (final (date, amount) in <(DateTime, int)>[
          (DateTime(2026, 2, 10), 200000), // Q1
          (DateTime(2026, 5, 10), 100000), // Q2, complete
          (DateTime(2026, 7, 15), 100000), // Q3, in progress
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

        // Q2 is over, so it is compared against a whole Q1: half of it.
        expect(
          snapshot.expenseChangeForRange(
            StatsRange.containing(StatsPeriod.quarter, DateTime(2026, 5, 10)),
          ),
          closeTo(-50, 0.01),
        );

        // Q3 is 75 of its 92 days old, so Q2 is scaled down before comparing.
        // Against a whole Q2 this would read as no change at all.
        final change = snapshot.expenseChangeForRange(
          StatsRange.containing(StatsPeriod.quarter, DateTime(2026, 9, 13)),
        );
        expect(change, isNotNull);
        expect(change!, greaterThan(0));
      },
    );

    test('the pace curve spans the period and stops at today', () async {
      final fixture = await quarterFixture();
      addTearDown(fixture.dispose);
      final snapshot = await fixture.snapshot();

      // July is over, so its curve runs to its last day: 31 days plus the origin.
      final july = snapshot.cumulativeSpendIn(
        StatsRange.containing(StatsPeriod.month, DateTime(2026, 7, 1)),
      );
      expect(july, hasLength(32));
      expect(july.last, closeTo(1000, 0.01));

      // A week is seven days plus the origin.
      final week = snapshot.cumulativeSpendIn(
        StatsRange.containing(StatsPeriod.week, DateTime(2026, 9, 13)),
      );
      expect(week, hasLength(8));
      expect(week.last, closeTo(3000, 0.01));

      // The month in progress stops at today — the 13th — rather than drawing a
      // flat line to the 30th.
      final september = snapshot.cumulativeSpendIn(
        StatsRange.containing(StatsPeriod.month, DateTime(2026, 9, 13)),
      );
      expect(september, hasLength(14));
    });
  });

  testWidgets('the overview opens on Month and follows a change of period', (
    tester,
  ) async {
    final fixture = await quarterFixture();
    addTearDown(fixture.dispose);

    await tester.pumpWidget(
      FinanceApp(
        repository: fixture.repository,
        initialSnapshot: await fixture.snapshot(),
      ),
    );
    await tester.pumpAndSettle();

    // Monthly by default: September holds only its own ₹3,000.
    expect(find.text('Spent this month'), findsOneWidget);
    expect(find.text('₹3,000'), findsWidgets);

    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();

    // The same screen, now the year — every month's entries, and the label says
    // which long period is on screen.
    expect(find.text('Spent this year'), findsOneWidget);
    expect(find.text('₹6,000'), findsWidgets);
    expect(find.text('2026'), findsOneWidget);

    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(find.text('Spent this week'), findsOneWidget);
    // The week of the 7th holds September's single entry, not the quarter's.
    expect(find.text('₹3,000'), findsWidgets);
  });
}
