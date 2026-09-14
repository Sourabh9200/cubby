import 'package:finance_app/app.dart';
import 'package:finance_app/core/widgets/charts/chart_bar.dart';
import 'package:finance_app/data/models.dart';
import 'package:finance_app/features/dashboard/dashboard_screen.dart';
import 'package:finance_app/features/dashboard/widgets/committed_spend_card.dart';
import 'package:finance_app/features/dashboard/widgets/composition_card.dart';
import 'package:finance_app/features/trends/payee_detail_screen.dart';
import 'package:finance_app/features/trends/trends_screen.dart';
import 'package:finance_app/features/trends/widgets/composition_over_time_card.dart';
import 'package:finance_app/features/trends/widgets/spending_rhythm_card.dart';
import 'package:finance_app/features/trends/widgets/top_payees_card.dart';
import 'package:finance_app/features/trends/widgets/year_over_year_card.dart';
import 'package:finance_db/finance_db.dart' hide CategoryKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// The Tier 0 cards, as the user meets them.
///
/// The arithmetic is pinned in the pure-function suites. This file asserts the
/// contract the screens owe: which card appears where, which caveat is on screen
/// beside it, and that a top payee opens its own history.
void main() {
  /// ₹80,000 of income, ₹450 of groceries, ₹800 at Amazon, ₹2,000 invested, and
  /// a second month so the history cards have something to span.
  Future<Fixture> populated() async {
    final fixture = makeFixture();
    for (final (date, amount, payee, categoryId, direction)
        in <(DateTime, int, String, String, TxDirection)>[
          (
            DateTime(2026, 8, 20),
            25000,
            'BigBasket',
            SeedIds.categoryGroceries,
            TxDirection.expense,
          ),
          (
            DateTime(2026, 9, 1),
            8000000,
            'Salary credit',
            SeedIds.categoryIncome,
            TxDirection.income,
          ),
          (
            DateTime(2026, 9, 5),
            45000,
            'BigBasket',
            SeedIds.categoryGroceries,
            TxDirection.expense,
          ),
          (
            DateTime(2026, 9, 6),
            80000,
            'Amazon',
            SeedIds.categoryShopping,
            TxDirection.expense,
          ),
          (
            DateTime(2026, 9, 7),
            200000,
            'SIP',
            SeedIds.categoryMutualFunds,
            TxDirection.investment,
          ),
        ]) {
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: categoryId,
        amountMinor: amount,
        date: date,
        direction: direction,
        payee: payee,
      );
    }
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

  /// The screen's own scroll view.
  ///
  /// Named by axis rather than assumed: the overview's period chips are a
  /// horizontal `ListView`, which is a `Scrollable` too, so the first
  /// `Scrollable` in the tree is not necessarily the screen.
  Finder verticalScrollableIn(Type screen) => find.descendant(
    of: find.byType(screen),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );

  testWidgets('the overview splits the period three ways', (tester) async {
    final fixture = await populated();
    addTearDown(fixture.dispose);
    await pumpApp(tester, fixture);

    final card = find.byType(CompositionCard);
    await tester.scrollUntilVisible(
      card,
      300,
      scrollable: verticalScrollableIn(DashboardScreen),
    );
    await tester.pumpAndSettle();

    Finder inCard(String label) =>
        find.descendant(of: card, matching: find.text(label));

    expect(inCard('Spent'), findsOneWidget);
    expect(inCard('Invested'), findsOneWidget);
    expect(inCard('Unallocated'), findsOneWidget);
    // ₹80,000 − ₹1,250 spent − ₹2,000 invested = ₹76,750 left in the bank.
    expect(inCard('₹76,750'), findsOneWidget);
    expect(inCard('₹1,250'), findsOneWidget);
    // A month's income is lumpy, so the monthly caveat is shown with the split.
    expect(
      inCard(
        'One month of income is lumpy — a single invoice or bonus can double '
        'it. The quarter or the year is the honest place to read this split.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the overview says what recurring rules account for', (
    tester,
  ) async {
    final fixture = await populated();
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

    final card = find.byType(CommittedSpendCard);
    await tester.scrollUntilVisible(
      card,
      300,
      scrollable: verticalScrollableIn(DashboardScreen),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: card, matching: find.text('Scheduled spending')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('₹18,000')),
      findsOneWidget,
    );
    // The wording is "scheduled", never "owed": a rule is a habit, not a debt.
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('it is not a commitment'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the trends screen shows the history cards', (tester) async {
    final fixture = await populated();
    addTearDown(fixture.dispose);
    await pumpApp(tester, fixture);

    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();

    // A sliver list does not build what is off screen, and the shell keeps every
    // tab alive, so the scrollable is named rather than assumed.
    final scrollable = verticalScrollableIn(TrendsScreen);

    await tester.scrollUntilVisible(
      find.byType(CompositionOverTimeCard),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    Finder inComposition(String label) => find.descendant(
      of: find.byType(CompositionOverTimeCard),
      matching: find.text(label),
    );
    expect(inComposition('Unallocated'), findsOneWidget);
    // The month in progress is marked, so a short column is not read as a
    // collapse in saving (C6).
    expect(inComposition('Sep*'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byType(YearOverYearCard),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Against last year'), findsOneWidget);
    // The fixture holds weeks of history, so the card says so rather than
    // comparing against a window the ledger did not exist for.
    expect(find.text('Not enough history'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byType(TopPayeesCard),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Top places'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TopPayeesCard),
        matching: find.text('Amazon'),
      ),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.byType(SpendingRhythmCard),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Rhythm'), findsOneWidget);
    expect(find.text('Average per active day'), findsOneWidget);
    // Recorded, not spent: a quiet day is a day nothing was entered (C11).
    expect(
      find.textContaining('days so far have nothing recorded'),
      findsOneWidget,
    );
  });

  testWidgets('a top payee opens its own history', (tester) async {
    final fixture = await populated();
    addTearDown(fixture.dispose);
    await pumpApp(tester, fixture);

    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(TopPayeesCard),
      300,
      scrollable: verticalScrollableIn(TrendsScreen),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(TopPayeesCard),
        matching: find.text('Amazon'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PayeeDetailScreen), findsOneWidget);
    final detail = find.byType(PayeeDetailScreen);
    expect(
      find.descendant(of: detail, matching: find.text('Spent here')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detail, matching: find.text('Shopping')),
      findsOneWidget,
    );
    // ₹800 at Amazon, once.
    expect(
      find.descendant(of: detail, matching: find.text('₹800')),
      findsWidgets,
    );
    // The drill-down's month bar has real width: a decoration-only Container
    // inside a Column collapses to nothing (see core/widgets/charts/chart_bar).
    final bars = find.descendant(of: detail, matching: find.byType(ChartBar));
    expect(bars, findsOneWidget);
    expect(tester.getSize(bars).width, greaterThan(0));
  });
}
