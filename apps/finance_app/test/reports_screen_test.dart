import 'package:finance_app/app.dart';
import 'package:finance_app/data/models.dart';
import 'package:finance_app/features/dashboard/widgets/budget_row.dart';
import 'package:finance_app/features/reports/reports_screen.dart';
import 'package:finance_app/features/reports/year_in_review_screen.dart';
import 'package:finance_app/features/trends/trends_screen.dart';
import 'package:finance_db/finance_db.dart' hide CategoryKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// The two Tier 3 screens as the user meets them: a report of any period from a
/// day to a year, and the year in review that hangs off a year report.
///
/// The figures asserted here are the ones a *person* reads — the sentence in the
/// review, the month's totals, what a single day says when it holds nothing —
/// rather than the shapes of the widgets. The arithmetic behind them is tested in
/// `reports_test.dart`.
void main() {
  /// Seven months of groceries from March, a September so far, a salary and one
  /// fund contribution, and limits to measure the months against.
  Future<Fixture> withMonths() async {
    final fixture = makeFixture();
    for (final (date, amount, categoryId, payee)
        in <(DateTime, int, String, String)>[
          (
            DateTime(2026, 3, 1),
            100000,
            SeedIds.categoryGroceries,
            'BigBasket',
          ),
          (
            DateTime(2026, 4, 5),
            120000,
            SeedIds.categoryGroceries,
            'BigBasket',
          ),
          (
            DateTime(2026, 5, 5),
            110000,
            SeedIds.categoryGroceries,
            'BigBasket',
          ),
          (
            DateTime(2026, 6, 5),
            130000,
            SeedIds.categoryGroceries,
            'BigBasket',
          ),
          (
            DateTime(2026, 7, 5),
            105000,
            SeedIds.categoryGroceries,
            'BigBasket',
          ),
          (
            DateTime(2026, 8, 5),
            115000,
            SeedIds.categoryGroceries,
            'BigBasket',
          ),
          (DateTime(2026, 9, 5), 90000, SeedIds.categoryGroceries, 'BigBasket'),
          (DateTime(2026, 9, 6), 10000, SeedIds.categoryDining, 'Swiggy'),
        ]) {
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: categoryId,
        amountMinor: amount,
        date: date,
        direction: TxDirection.expense,
        payee: payee,
      );
    }
    await fixture.repository.addTransaction(
      accountId: SeedIds.accountHdfc,
      categoryId: SeedIds.categoryIncome,
      amountMinor: 5000000,
      date: DateTime(2026, 9, 1),
      direction: TxDirection.income,
      payee: 'Salary credit',
    );
    await fixture.repository.addTransaction(
      accountId: SeedIds.accountHdfc,
      categoryId: SeedIds.categoryMutualFunds,
      amountMinor: 1000000,
      date: DateTime(2026, 9, 10),
      direction: TxDirection.investment,
      payee: 'Fund',
    );
    await fixture.repository.setCategoryBudget(
      categoryId: SeedIds.categoryGroceries,
      budgetMinor: 100000,
    );
    await fixture.repository.setCategoryBudget(
      categoryId: SeedIds.categoryDining,
      budgetMinor: 500000,
    );
    return fixture;
  }

  Future<void> pumpApp(WidgetTester tester, Fixture fixture) async {
    await tester.pumpWidget(
      FinanceApp(
        repository: fixture.repository,
        initialSnapshot: await fixture.snapshot(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the reports screen the way a user does: Trends, then the app-bar
  /// action. Nothing on the overview grew a card for this.
  Future<void> openReports(WidgetTester tester) async {
    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    expect(find.byType(TrendsScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Reports'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportsScreen), findsOneWidget);
  }

  /// The reports screen's own scroll view.
  Finder verticalScrollableIn(Type screen) => find.descendant(
    of: find.byType(screen),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );

  /// The period chips' scroll view, which is horizontal: on a narrow phone the
  /// later chips are off its right edge and have to be scrolled to, exactly as a
  /// finger would.
  Finder chipsScrollableIn(Type screen) => find.descendant(
    of: find.byType(screen),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.right,
    ),
  );

  Future<void> scrollTo(WidgetTester tester, Finder target, Type screen) async {
    await tester.scrollUntilVisible(
      target,
      250,
      scrollable: verticalScrollableIn(screen),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a report adds the month up and says what it compares with', (
    tester,
  ) async {
    final fixture = await withMonths();
    addTearDown(fixture.dispose);
    await pumpApp(tester, fixture);
    await openReports(tester);

    // Every finder is scoped to the report: the Trends screen stays mounted
    // under the pushed route, and a legend there also says "Spent".
    Finder inReport(Finder matching) =>
        find.descendant(of: find.byType(ReportsScreen), matching: matching);

    // September by default: the month containing today (C6).
    expect(inReport(find.text('September 2026')), findsOneWidget);
    expect(inReport(find.text('Totals')), findsOneWidget);
    expect(inReport(find.text('4 entries')), findsOneWidget);
    expect(inReport(find.text('Spent')), findsWidgets);
    expect(inReport(find.text('₹1,000')), findsWidgets);
    expect(inReport(find.text('Received')), findsOneWidget);
    expect(inReport(find.text('₹50,000')), findsWidgets);
    expect(inReport(find.text('Invested')), findsWidgets);
    expect(inReport(find.text('₹10,000')), findsWidgets);
    // Income less spending: what the month kept, which investing does not reduce.
    expect(inReport(find.text('₹49,000')), findsWidgets);

    // The comparison is the whole of August against September so far, scaled to
    // the same point in the month (C6).
    expect(
      inReport(find.textContaining('more than the previous month')),
      findsWidgets,
    );

    // Composition is the same card the overview shows, over these dates.
    expect(inReport(find.text('Composition')), findsOneWidget);

    await scrollTo(tester, find.text('Where it went'), ReportsScreen);
    expect(find.text('90% of spending · 1 entry'), findsOneWidget);
    expect(inReport(find.text('Dining Out')), findsWidgets);

    await scrollTo(tester, find.text('Who was paid'), ReportsScreen);
    expect(find.text('BigBasket'), findsOneWidget);
    expect(find.text('1 entry · avg ₹900'), findsOneWidget);

    // Budget outcomes, with the limits scaled to the month.
    await scrollTo(tester, find.byType(BudgetRow).first, ReportsScreen);
    expect(inReport(find.byType(BudgetRow)), findsWidgets);
    expect(find.text('90% used'), findsOneWidget);
  });

  testWidgets('a report of one day says what a day holds, and what it cannot', (
    tester,
  ) async {
    final fixture = await withMonths();
    addTearDown(fixture.dispose);
    await pumpApp(tester, fixture);
    await openReports(tester);

    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();

    Finder inReport(Finder matching) =>
        find.descendant(of: find.byType(ReportsScreen), matching: matching);

    // Today, named as a day rather than as a month.
    expect(inReport(find.text('13 Sep 2026')), findsOneWidget);
    // Nothing to compare with, said once for each of the three measures.
    expect(
      inReport(find.text('Nothing comparable in the previous day')),
      findsNWidgets(3),
    );

    // Nothing was spent, so the two lists say so rather than showing a zero row.
    await scrollTo(tester, find.text('Nothing spent'), ReportsScreen);
    expect(find.text('Nothing spent'), findsOneWidget);
    await scrollTo(tester, find.text('Nothing paid'), ReportsScreen);
    expect(find.text('Nothing paid'), findsOneWidget);

    // And a budget outcome is refused rather than scaled to a day (C4).
    await scrollTo(tester, find.text('Budgets are monthly'), ReportsScreen);
    expect(
      find.textContaining('A day or a week holds no whole month'),
      findsOneWidget,
    );
    expect(find.byType(BudgetRow), findsNothing);
  });

  testWidgets('a custom range is offered, and reads as a range once chosen', (
    tester,
  ) async {
    final fixture = await withMonths();
    addTearDown(fixture.dispose);
    await pumpApp(tester, fixture);
    await openReports(tester);

    expect(find.text('Custom range'), findsOneWidget);
    await tester.tap(find.text('Custom range'));
    await tester.pumpAndSettle();

    // Bounded by the ledger's first day and today, so a range outside the data
    // cannot be chosen.
    expect(find.byType(DateRangePickerDialog), findsOneWidget);

    // 5 to 10 September. The picker's end date is inclusive; the range's end is
    // exclusive, so the day tapped last is inside the report.
    await tester.tap(find.text('5').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('10').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(ReportsScreen), findsOneWidget);
    expect(find.text('Change range'), findsOneWidget);
    // The label names both ends, and repeats the year only when the span crosses
    // one: "5 Sep 2026 – 10 Sep".
    expect(find.text('5 Sep 2026 – 10 Sep'), findsOneWidget);

    // This window holds ₹1,000 of groceries and a ₹100 dinner, which is the same
    // figure the month shows — one implementation, two sets of bounds.
    Finder inReport(Finder matching) =>
        find.descendant(of: find.byType(ReportsScreen), matching: matching);
    expect(inReport(find.text('Totals')), findsOneWidget);
    expect(inReport(find.text('₹1,000')), findsWidgets);
    expect(inReport(find.text('3 entries')), findsOneWidget);

    // A range the user chose is not a whole number of months, so a monthly limit
    // is not scaled to it — the card says why (C4).
    await scrollTo(tester, find.text('Budgets are monthly'), ReportsScreen);
    expect(
      find.textContaining('A range you chose is not a whole number of months'),
      findsOneWidget,
    );
  });

  testWidgets('the year in review is one tap from a year report', (
    tester,
  ) async {
    final fixture = await withMonths();
    addTearDown(fixture.dispose);
    await pumpApp(tester, fixture);
    await openReports(tester);

    // No review link on a report of a month: the review is a year's reward, not
    // a button that is always there.
    expect(find.text('Year in review'), findsNothing);

    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Year in review'), ReportsScreen);
    await tester.tap(find.text('Year in review'));
    await tester.pumpAndSettle();

    expect(find.byType(YearInReviewScreen), findsOneWidget);
    expect(find.text('2026 in review'), findsOneWidget);
    expect(find.text('so far'), findsOneWidget);

    // The year in a sentence, in the tense it deserves: nothing here is a new
    // sum, so the totals match the year report the user just left. Ten entries:
    // eight expenses, one salary credit and one fund contribution.
    expect(
      find.textContaining(
        'So far in 2026 you have spent ₹7,800 across 10 entries',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('₹50,000 came in, so you kept 84% of it'),
      findsOneWidget,
    );

    await scrollTo(tester, find.text('What stood out'), YearInReviewScreen);
    expect(find.text('₹1,300'), findsOneWidget);
    expect(find.textContaining('June 2026'), findsOneWidget);
    expect(
      find.textContaining('7 entries at an average of ₹1,100'),
      findsOneWidget,
    );
    // The largest payee and the most frequent one are the same here, so the
    // second row is not drawn rather than repeating the name and the total.
    expect(find.text('Paid most often'), findsNothing);

    await scrollTo(
      tester,
      find.text('Months inside their limits'),
      YearInReviewScreen,
    );
    // March and September stayed inside the ₹1,000 limit; five months did not.
    expect(find.text('2 of 7'), findsOneWidget);
    expect(
      find.textContaining('A month counts when it had spending'),
      findsOneWidget,
    );

    await scrollTo(tester, find.text('Against last year'), YearInReviewScreen);
    // The ledger starts in March 2026, so there is no whole year to compare
    // against and the card says so rather than inventing one (C7).
    expect(find.text('Not enough history'), findsOneWidget);
  });

  testWidgets('both screens lay out on a narrow phone', (tester) async {
    // 347 dp wide, the width that caught the Tier 0 bar-chart bugs: a value and a
    // label side by side is exactly the shape that overflows a phone.
    tester.view.devicePixelRatio = 3.5;
    tester.view.physicalSize = const Size(1216, 2400);
    addTearDown(tester.view.reset);

    final fixture = await withMonths();
    addTearDown(fixture.dispose);
    await pumpApp(tester, fixture);
    await openReports(tester);

    // Every chip, and every list, scrolled to the bottom of the report.
    for (final chip in <String>['Day', 'Week', 'Month', 'Quarter', 'Year']) {
      await tester.scrollUntilVisible(
        find.text(chip),
        80,
        scrollable: chipsScrollableIn(ReportsScreen),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(chip));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.textContaining('Every figure here comes from the same sums'),
        verticalScrollableIn(ReportsScreen),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    // And the review, which is the longest list in the app. The report is at its
    // bottom by now, so the link back at the top has to be scrolled up to.
    await tester.dragUntilVisible(
      find.text('Year in review'),
      verticalScrollableIn(ReportsScreen),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year in review'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.textContaining('matched exactly as they were typed'),
      verticalScrollableIn(YearInReviewScreen),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
