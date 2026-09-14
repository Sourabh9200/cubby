import 'package:finance_app/app.dart';
import 'package:finance_app/data/models.dart';
import 'package:finance_app/features/dashboard/dashboard_screen.dart';
import 'package:finance_app/features/dashboard/widgets/budget_row.dart';
import 'package:finance_app/features/trends/net_worth_screen.dart';
import 'package:finance_app/features/trends/trends_screen.dart';
import 'package:finance_db/finance_db.dart' hide CategoryKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// The Tier 1 figures as the user meets them: a line where the question is
/// already being asked, the working-out behind a tap, and nothing at all when
/// there is not enough history to be honest (C5, C7, C11).
///
/// This file is also the guard on the decision that Tier 1 would not bloat the
/// screens: the projection is one line that opens a sheet, the budget row swaps
/// one figure for another rather than adding a row, and the proposals card does
/// not exist when there is nothing to propose.
void main() {
  /// Six complete months of groceries history, a September so far, and limits to
  /// measure them against.
  ///
  /// The groceries entries run from 1 March so the six-month window is inside the
  /// ledger, which is what `suggestedLimits` requires before it will say anything
  /// (C7). The amounts step so the median and the p90 are different figures.
  Future<Fixture> withHistory() async {
    final fixture = makeFixture();
    for (final (date, amount, categoryId) in <(DateTime, int, String)>[
      (DateTime(2026, 3, 1), 100000, SeedIds.categoryGroceries),
      (DateTime(2026, 4, 5), 120000, SeedIds.categoryGroceries),
      (DateTime(2026, 5, 5), 110000, SeedIds.categoryGroceries),
      (DateTime(2026, 6, 5), 130000, SeedIds.categoryGroceries),
      (DateTime(2026, 7, 5), 105000, SeedIds.categoryGroceries),
      (DateTime(2026, 8, 5), 115000, SeedIds.categoryGroceries),
      // September: ₹900 of groceries and ₹100 of dining so far.
      (DateTime(2026, 9, 5), 90000, SeedIds.categoryGroceries),
      (DateTime(2026, 9, 6), 10000, SeedIds.categoryDining),
    ]) {
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: categoryId,
        amountMinor: amount,
        date: date,
        direction: TxDirection.expense,
        payee: categoryId == SeedIds.categoryDining ? 'Swiggy' : 'BigBasket',
      );
    }
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

  /// The vertical scroll view of a screen, never the period chips' horizontal
  /// one.
  Finder verticalScrollableIn(Type screen) => find.descendant(
    of: find.byType(screen),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );

  testWidgets('the pace card says where the month lands, and explains itself', (
    tester,
  ) async {
    final fixture = await withHistory();
    addTearDown(fixture.dispose);
    await pumpApp(tester, fixture);

    final scrollable = verticalScrollableIn(DashboardScreen);
    await tester.scrollUntilVisible(
      find.text('Spending pace'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    // One line, with the figure: ₹1,000 spent, ₹36.68 a day expected for the 17
    // days left. Nothing is committed because no rule falls due this month.
    expect(
      find.textContaining('At this rate, ₹1,624 this month'),
      findsOneWidget,
    );

    await tester.tap(find.text('How'));
    await tester.pumpAndSettle();

    expect(find.text('Where this month is heading'), findsOneWidget);
    expect(find.text('Still to post · 0 rules'), findsOneWidget);
    expect(find.text('Expected · ₹36.68 a day × 17 days'), findsOneWidget);
    // The basis is shown rather than implied (C5). The seeded categories keep
    // their own limits, so the total is ₹44,000: ₹1,000 + ₹5,000 set here plus
    // the limits the app ships with.
    expect(
      find.textContaining(
        'From 6 months of history, 6 days with entries, and a typical '
        'recorded day of ₹1,125.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('keeps you inside your ₹44,000 of limits'),
      findsOneWidget,
    );
    expect(find.textContaining('never a promise'), findsOneWidget);
  });

  testWidgets('a projection with no basis says nothing at all', (tester) async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);
    await pumpApp(tester, fixture);

    // A fresh install: no history and nothing scheduled, so the app says nothing
    // rather than printing a confident zero (C5, C11).
    expect(find.textContaining('At this rate'), findsNothing);
    expect(find.text('How'), findsNothing);
  });

  testWidgets('a budget row says where it is heading only when that is a '
      'problem', (tester) async {
    final fixture = await withHistory();
    addTearDown(fixture.dispose);
    await pumpApp(tester, fixture);

    final scrollable = verticalScrollableIn(DashboardScreen);
    // Scrolled to the *line inside the row*, not to the row itself: the sliver
    // list builds a little beyond the fold, and a finder that matches off-stage
    // would stop the scroll before anything can be read.
    await tester.scrollUntilVisible(
      find.text('heading for ₹2,077'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    // Groceries: ₹900 by the 13th projects to ₹2,077 against a ₹1,000 limit, so
    // the row swaps its reassuring "left" figure for what is coming.
    expect(find.text('heading for ₹2,077'), findsOneWidget);
    // Dining Out is comfortably inside its limit, so its row is exactly what it
    // was before Tier 1 existed.
    await tester.scrollUntilVisible(
      find.text('₹4,900 left'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('₹4,900 left'), findsOneWidget);
    expect(find.text('heading for ₹4,900'), findsNothing);
  });

  testWidgets('the editor offers a limit from the user\'s own months', (
    tester,
  ) async {
    final fixture = await withHistory();
    addTearDown(fixture.dispose);
    await pumpApp(tester, fixture);

    final groceriesRow = find.byWidgetPredicate(
      (widget) => widget is BudgetRow && widget.budget.category == 'Groceries',
    );
    await tester.scrollUntilVisible(
      find.text('heading for ₹2,077'),
      300,
      scrollable: verticalScrollableIn(DashboardScreen),
    );
    await tester.pumpAndSettle();
    // Tapped through the row's own line: a scroll can leave a row's centre off
    // screen while its text is visible, and a tap on the row itself would then
    // miss whatever is under the finger.
    await tester.ensureVisible(groceriesRow);
    await tester.pumpAndSettle();
    await tester.tap(groceriesRow);
    await tester.pumpAndSettle();

    // A suggestion from the user's own six months: the median is ₹1,125 and the
    // busiest month ₹1,300.
    expect(find.text('Use ₹1,125 · your median'), findsOneWidget);
    expect(find.text('Use ₹1,300 · your busiest'), findsOneWidget);
    expect(
      find.textContaining('a suggestion, not a budget you agreed to'),
      findsOneWidget,
    );
    // The pace is here too, so the decision is made with the projection in front
    // of the user rather than from memory.
    expect(
      find.textContaining('At this pace you land at ₹2,077'),
      findsOneWidget,
    );

    // Nothing is applied until it is tapped.
    await tester.tap(find.text('Use ₹1,125 · your median'));
    await tester.pumpAndSettle();
    expect(find.text('1125'), findsOneWidget);
  });

  testWidgets('proposals appear only when the payments look recurring', (
    tester,
  ) async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);
    // Three payments, thirty days apart, for about the same amount: the shape the
    // heuristic looks for. (Thirty days is not "the fifth of every month" — see
    // the tolerance test in recurring_candidates_test.)
    for (final date in <DateTime>[
      DateTime(2026, 7, 7),
      DateTime(2026, 8, 6),
      DateTime(2026, 9, 5),
    ]) {
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryDining,
        amountMinor: 30000,
        date: date,
        direction: TxDirection.expense,
        payee: 'Zomato',
      );
    }
    await pumpApp(tester, fixture);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    final scrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    await tester.scrollUntilVisible(
      find.text('Looks recurring'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Zomato · ₹300'), findsOneWidget);
    expect(
      find.text('3 entries about a month apart · last 5 Sep'),
      findsOneWidget,
    );
    expect(find.text('Add monthly'), findsWidgets);
    // It says why, including the false positive, rather than hiding the heuristic.
    expect(
      find.textContaining('nothing repeats until you say so'),
      findsOneWidget,
    );

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Looks recurring'), findsNothing);
  });

  testWidgets('the recurring card annualises what repeats', (tester) async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);
    await fixture.repository.addRecurringRule(
      accountId: SeedIds.accountHdfc,
      categoryId: SeedIds.categoryRent,
      amountMinor: 1800000,
      direction: TxDirection.expense,
      startedOn: testNow,
      payee: 'Monthly rent transfer',
    );
    await pumpApp(tester, fixture);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Recurring'),
      300,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.pumpAndSettle();

    // ₹18,000 a month is the figure nobody acts on; ₹2.2L a year is (Tier 1.3).
    expect(find.textContaining('₹2.2L a year'), findsWidgets);
    expect(find.text('₹2.2L a year in recurring spending.'), findsOneWidget);
  });

  testWidgets('net worth is a screen of its own, at cost and saying so', (
    tester,
  ) async {
    final fixture = await withHistory();
    addTearDown(fixture.dispose);
    await fixture.repository.addTransaction(
      accountId: SeedIds.accountHdfc,
      categoryId: SeedIds.categoryMutualFunds,
      amountMinor: 200000,
      date: DateTime(2026, 9, 7),
      direction: TxDirection.investment,
      payee: 'SIP',
    );
    await pumpApp(tester, fixture);

    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    final link = find.text('Net worth, at cost');
    await tester.scrollUntilVisible(
      link,
      300,
      scrollable: verticalScrollableIn(TrendsScreen),
    );
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(find.byType(NetWorthScreen), findsOneWidget);
    expect(find.text('Month by month'), findsOneWidget);
    expect(find.text('Bank, cash and wallet'), findsOneWidget);
    expect(find.text('Cards, money owed'), findsOneWidget);
    expect(find.text('Investments, at cost'), findsOneWidget);
    // The caveat is the reason this is a screen rather than a card (C3).
    expect(find.textContaining('no price feed by design'), findsOneWidget);
  });
}
