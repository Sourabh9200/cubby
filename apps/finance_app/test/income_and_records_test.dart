import 'package:finance_app/app.dart';
import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/monthly_extremes.dart';
import 'package:finance_app/data/snapshot_analytics.dart';
import 'package:finance_app/data/snapshot_views.dart';
import 'package:finance_app/features/trends/trends_screen.dart';
import 'package:finance_app/features/trends/widgets/income_sources_card.dart';
import 'package:finance_app/features/trends/widgets/monthly_records_card.dart';
import 'package:finance_db/finance_db.dart' hide CategoryKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// Income by source, and the highest and lowest month on record.
///
/// Repository and analytics behaviour is asserted with plain `test`s and the
/// rendering with `testWidgets`, as the other suites do: a widget test that
/// starts a database write and then tears down fights the harness.
void main() {
  group('income by source', () {
    test('splits the month by income category, largest first', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      await fixture.repository.addCategory(
        name: 'Freelance',
        kind: CategoryKind.income,
        budgetMinor: 0,
      );
      final freelance = (await fixture.snapshot()).categoryNamed('Freelance')!;

      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryIncome,
        amountMinor: 8000000,
        date: DateTime(2026, 9, 1),
        direction: TxDirection.income,
        payee: 'Salary credit',
      );
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: freelance.id,
        amountMinor: 2500000,
        date: DateTime(2026, 9, 20),
        direction: TxDirection.income,
        payee: 'Invoice paid',
      );

      final sources = (await fixture.snapshot()).incomeBySource(testNow);

      expect(sources.map((source) => source.category), <String>[
        'Income',
        'Freelance',
      ]);
      expect(sources.first.totalMinor, 8000000);
      expect(sources.last.totalMinor, 2500000);
    });

    test('adds up to the headline income figure for the same month', () async {
      // The invariant a breakdown has to hold. Income is read once and split
      // twice; if the rows ever disagreed with the summary, the card would be
      // showing the user a set of numbers that does not sum to their own total.
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      await fixture.repository.addCategory(
        name: 'Interest',
        kind: CategoryKind.income,
        budgetMinor: 0,
      );
      final interest = (await fixture.snapshot()).categoryNamed('Interest')!;

      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryIncome,
        amountMinor: 8000000,
        date: DateTime(2026, 9, 1),
        direction: TxDirection.income,
        payee: 'Salary credit',
      );
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: interest.id,
        amountMinor: 90000,
        date: DateTime(2026, 9, 28),
        direction: TxDirection.income,
        payee: 'FD interest',
      );

      final snapshot = await fixture.snapshot();
      final sources = snapshot.incomeBySource(testNow);
      final summed = sources.fold<int>(
        0,
        (sum, source) => sum + source.totalMinor,
      );

      expect(summed, snapshot.incomeTotal(testNow));
      expect(snapshot.incomeTotal(testNow), 8090000);
      // Income is money arriving. It must never leak into the spending split,
      // which is the bug that would make a salary month look like a spend.
      expect(snapshot.spendByCategory(testNow), isEmpty);
    });

    test(
      'reports no sources rather than a zero row on a quiet month',
      () async {
        final fixture = makeFixture();
        addTearDown(fixture.dispose);

        final snapshot = await fixture.snapshot();
        expect(snapshot.incomeBySource(testNow), isEmpty);
        expect(snapshot.incomeTotal(testNow), 0);
      },
    );
  });

  group('monthly records', () {
    /// Three months of spend, optionally with a single month of investing.
    Future<void> addThreeMonths(
      Fixture fixture, {
      required int investmentInSeptember,
    }) async {
      for (final (payee, month, amount) in <(String, DateTime, int)>[
        ('aug', DateTime(2026, 8, 5), 100000),
        ('sep', DateTime(2026, 9, 5), 300000),
        ('jul', DateTime(2026, 7, 5), 200000),
      ]) {
        await fixture.repository.addTransaction(
          accountId: SeedIds.accountHdfc,
          categoryId: SeedIds.categoryGroceries,
          amountMinor: amount,
          date: month,
          direction: TxDirection.expense,
          payee: payee,
        );
      }
      if (investmentInSeptember > 0) {
        await fixture.repository.addTransaction(
          accountId: SeedIds.accountHdfc,
          categoryId: SeedIds.categoryMutualFunds,
          amountMinor: investmentInSeptember,
          date: DateTime(2026, 9, 6),
          direction: TxDirection.investment,
          payee: 'SIP',
        );
      }
    }

    test('reports the highest and lowest month for spending', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      await addThreeMonths(fixture, investmentInSeptember: 0);

      final expense = (await fixture.snapshot()).monthlyExtremes.firstWhere(
        (record) => record.measure == MetricMeasure.expense,
      );

      expect(expense.highest!.month, DateTime(2026, 9));
      expect(expense.highest!.totalMinor, 300000);
      expect(expense.lowest!.month, DateTime(2026, 8));
      expect(expense.lowest!.totalMinor, 100000);
      expect(expense.averageMinor, 200000);
      expect(expense.isFlat, isFalse);
    });

    test('skips months that recorded nothing rather than counting zeroes', () async {
      // A single investing month. Counting the months with no investing as zero
      // would report the user's best investing month as their worst, which is
      // the most misleading thing a records panel could say.
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      await addThreeMonths(fixture, investmentInSeptember: 500000);

      final investing = (await fixture.snapshot()).monthlyExtremes.firstWhere(
        (record) => record.measure == MetricMeasure.investment,
      );

      expect(investing.hasData, isTrue);
      expect(investing.highest!.month, DateTime(2026, 9));
      expect(investing.lowest!.month, DateTime(2026, 9));
      expect(investing.averageMinor, 500000);
      // One month has no spread, so the card says "same every month" instead of
      // printing an average identical to both rows.
      expect(investing.isFlat, isTrue);
    });

    test('reports nothing at all on a fresh install', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      final extremes = (await fixture.snapshot()).monthlyExtremes;

      expect(extremes, hasLength(3));
      expect(extremes.every((record) => !record.hasData), isTrue);
      expect(extremes.every((record) => record.highest == null), isTrue);
      expect(extremes.every((record) => record.averageMinor == 0), isTrue);
    });
  });

  testWidgets('trends shows the records and the income split', (tester) async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);

    await fixture.repository.addCategory(
      name: 'Freelance',
      kind: CategoryKind.income,
      budgetMinor: 0,
    );
    final freelance = (await fixture.snapshot()).categoryNamed('Freelance')!;
    await fixture.repository.addTransaction(
      accountId: SeedIds.accountHdfc,
      categoryId: SeedIds.categoryIncome,
      amountMinor: 8000000,
      date: DateTime(2026, 9, 1),
      direction: TxDirection.income,
      payee: 'Salary credit',
    );
    await fixture.repository.addTransaction(
      accountId: SeedIds.accountHdfc,
      categoryId: freelance.id,
      amountMinor: 2500000,
      date: DateTime(2026, 9, 20),
      direction: TxDirection.income,
      payee: 'Invoice paid',
    );
    await fixture.repository.addTransaction(
      accountId: SeedIds.accountHdfc,
      categoryId: SeedIds.categoryGroceries,
      amountMinor: 45000,
      date: DateTime(2026, 8, 5),
      direction: TxDirection.expense,
      payee: 'BigBasket',
    );
    // An investing month too, so all three records rows have something to show:
    // a measure with no months at all is deliberately omitted from the card.
    await fixture.repository.addTransaction(
      accountId: SeedIds.accountHdfc,
      categoryId: SeedIds.categoryMutualFunds,
      amountMinor: 2000000,
      date: DateTime(2026, 9, 6),
      direction: TxDirection.investment,
      payee: 'SIP',
    );

    await tester.pumpWidget(
      FinanceApp(
        repository: fixture.repository,
        initialSnapshot: await fixture.snapshot(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();

    // Both cards sit below the fold, and a sliver list does not build what is
    // off-screen — so they have to be scrolled into existence. The scrollable is
    // named rather than assumed: `HomeShell` keeps every tab alive in an
    // `IndexedStack`, so the first `Scrollable` in the tree belongs to the
    // overview, not to this screen.
    final trendsScrollable = find.descendant(
      of: find.byType(TrendsScreen),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byType(MonthlyRecordsCard),
      300,
      scrollable: trendsScrollable,
    );
    await tester.pumpAndSettle();

    // Scoped to each card: the bar chart's legend already reads "Spent" and
    // "Received", so an unscoped finder would match it instead.
    Finder inRecords(String label) => find.descendant(
      of: find.byType(MonthlyRecordsCard),
      matching: find.text(label),
    );
    expect(inRecords('Spent'), findsOneWidget);
    expect(inRecords('Received'), findsOneWidget);
    expect(inRecords('Invested'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byType(IncomeSourcesCard),
      300,
      scrollable: trendsScrollable,
    );
    await tester.pumpAndSettle();

    Finder inSources(String label) => find.descendant(
      of: find.byType(IncomeSourcesCard),
      matching: find.text(label),
    );
    expect(inSources('Freelance'), findsOneWidget);
    expect(inSources('Income'), findsOneWidget);
    // Two sources, so the pill counts them rather than claiming one.
    expect(inSources('2 sources'), findsOneWidget);
  });
}
