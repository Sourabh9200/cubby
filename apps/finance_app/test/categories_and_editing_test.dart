import 'package:finance_app/app.dart';
import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/snapshot_analytics.dart';
import 'package:finance_app/data/snapshot_views.dart';
import 'package:finance_app/features/transactions/widgets/transaction_sheet.dart';
import 'package:finance_db/finance_db.dart' hide CategoryKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// Custom categories, editing, and investing.
///
/// Repository behaviour is asserted with plain `test`s and UI behaviour with
/// `testWidgets`, for the reason recorded in the other suites: a widget test
/// that starts a real database write and then tears down fights the harness
/// rather than the code.
void main() {
  group('custom categories', () {
    test('a category created as investing keeps that kind', () async {
      // The bug this guards. The writer used to map the kind with
      // `kind == income ? income : expense`, so a category the user added as
      // investing silently became a spending one — and every contribution
      // recorded against it inflated the spending total.
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      await fixture.repository.addCategory(
        name: 'Gold ETF',
        kind: CategoryKind.investment,
        budgetMinor: 0,
      );

      final category = (await fixture.snapshot()).categoryNamed('Gold ETF')!;
      expect(category.kind, CategoryKind.investment);
      expect(category.isInvestment, isTrue);
      expect(category.isSpending, isFalse);
      expect(category.isSystem, isFalse);
    });

    test('a custom spending category joins the spending picker only', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      await fixture.repository.addCategory(
        name: 'Coffee',
        kind: CategoryKind.expense,
        budgetMinor: 250000,
      );

      final snapshot = await fixture.snapshot();
      expect(
        snapshot.expenseCategories.map((category) => category.name),
        contains('Coffee'),
      );
      expect(
        snapshot.investmentCategories.map((category) => category.name),
        isNot(contains('Coffee')),
      );
      expect(snapshot.categoryNamed('Coffee')!.budgetMinor, 250000);
    });

    test('a custom category reaches every aggregate once an entry uses it', () async {
      // Reported from a device: creating a category and recording against it
      // appeared to change nothing on the overview, the ledger, or trends. The
      // aggregation turned out to be correct, so this pins it — if a custom
      // category ever stops reaching the donut, the month summary, the budget
      // bars, or the trend movement, this fails rather than a user noticing.
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      await fixture.repository.addCategory(
        name: 'Subscriptions',
        kind: CategoryKind.expense,
        budgetMinor: 50000,
      );
      final created = (await fixture.snapshot()).categoryNamed(
        'Subscriptions',
      )!;
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: created.id,
        amountMinor: 30000,
        date: DateTime(2026, 9, 10),
        direction: TxDirection.expense,
        payee: 'Netflix',
      );

      final snapshot = await fixture.snapshot();
      // The ledger resolves the name through the category join.
      expect(
        snapshot.transactions.map((txn) => txn.category),
        contains('Subscriptions'),
      );
      // The overview's donut and its budget bars.
      expect(
        snapshot.spendByCategory(testNow).map((spend) => spend.category),
        contains('Subscriptions'),
      );
      expect(
        snapshot.budgetStatuses().map((status) => status.category),
        contains('Subscriptions'),
      );
      // Trends: the month total and the month-over-month movement.
      expect(snapshot.currentMonth.expenseMinor, 30000);
      expect(
        snapshot.categoryMovement(testNow).map((move) => move.category),
        contains('Subscriptions'),
      );
    });

    test('a custom income category is available for income entries', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      await fixture.repository.addCategory(
        name: 'Rental income',
        kind: CategoryKind.income,
        budgetMinor: 0,
      );

      final category = (await fixture.snapshot()).categoryNamed(
        'Rental income',
      )!;
      expect(category.isIncome, isTrue);
      expect(category.isSpending, isFalse);
    });
  });

  group('editing an entry', () {
    test('an edited amount and category move every total', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      await seedMinimal(fixture);

      final before = await fixture.snapshot();
      expect(before.currentMonth.expenseMinor, 45000);
      final expense = before.transactions.firstWhere((txn) => txn.isExpense);

      await fixture.repository.updateTransaction(
        id: expense.id,
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryDining,
        amountMinor: 120000,
        date: DateTime(2026, 9, 12),
        direction: TxDirection.expense,
        payee: 'Dinner out',
      );

      final after = await fixture.snapshot();
      // Still one entry, not two. An edit that appended a row would double every
      // total the user then looked at.
      expect(after.transactions, hasLength(2));
      expect(after.currentMonth.expenseMinor, 120000);

      final updated = after.transactions.firstWhere(
        (txn) => txn.id == expense.id,
      );
      expect(updated.amountMinor, 120000);
      expect(updated.category, 'Dining Out');
      expect(updated.payee, 'Dinner out');

      // The donut must follow the new category rather than keep the old slice.
      final spends = after.spendByCategory(testNow);
      expect(spends.single.category, 'Dining Out');
      expect(spends.single.totalMinor, 120000);
    });

    test('an edit can move an entry into another month', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      await seedMinimal(fixture);

      final expense = (await fixture.snapshot()).transactions.firstWhere(
        (txn) => txn.isExpense,
      );
      expect((await fixture.snapshot()).currentMonth.expenseMinor, 45000);

      await fixture.repository.updateTransaction(
        id: expense.id,
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryGroceries,
        amountMinor: 45000,
        date: DateTime(2026, 8, 9),
        direction: TxDirection.expense,
        payee: 'BigBasket',
      );

      final after = await fixture.snapshot();
      // The local `occurred_on` column is what grouping reads, so an edit that
      // updated only the timestamp would leave the entry filed under September.
      expect(
        after.currentMonth.expenseMinor,
        0,
        reason: 'September must release it',
      );
      expect(after.summaryFor(DateTime(2026, 8)).expenseMinor, 45000);
      expect(after.spendByCategory(testNow), isEmpty);
    });
  });

  group('investments', () {
    test('are tracked apart from spending', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryMutualFunds,
        amountMinor: 2000000,
        date: DateTime(2026, 9, 5),
        direction: TxDirection.investment,
        payee: 'Index fund SIP',
      );

      final snapshot = await fixture.snapshot();
      expect(snapshot.currentMonth.investmentMinor, 2000000);
      // The headline the user reads as "spending" must not move.
      expect(snapshot.currentMonth.expenseMinor, 0);
      // Nor may it be a slice of the spending donut.
      expect(snapshot.spendByCategory(testNow), isEmpty);

      final invested = snapshot.investedByCategory(testNow);
      expect(invested.single.category, 'Mutual Funds');
      expect(invested.single.totalMinor, 2000000);

      // It is savings, so the month kept its money — but the cash did leave.
      expect(snapshot.currentMonth.netMinor, 0);
      expect(snapshot.currentMonth.cashLeftMinor, -2000000);
    });

    test('do not inflate the savings rate', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryIncome,
        amountMinor: 10000000,
        date: DateTime(2026, 9, 1),
        direction: TxDirection.income,
        payee: 'Salary credit',
      );
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryGroceries,
        amountMinor: 3000000,
        date: DateTime(2026, 9, 4),
        direction: TxDirection.expense,
        payee: 'Groceries',
      );
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryMutualFunds,
        amountMinor: 2000000,
        date: DateTime(2026, 9, 5),
        direction: TxDirection.investment,
        payee: 'Index fund SIP',
      );

      final month = (await fixture.snapshot()).currentMonth;
      // Earned ₹1,00,000, consumed ₹30,000, invested ₹20,000. The rate measures
      // what was kept, so it is 70% — not the 50% that treating the SIP as spend
      // would produce. This is the number the whole feature exists to protect.
      expect(month.savingsRate, closeTo(70, 0.01));
      expect(month.investmentRate, closeTo(20, 0.01));
      expect(month.cashLeftMinor, 5000000);
    });

    test('are listed as targets, never as spending budgets', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      final snapshot = await fixture.snapshot();
      // The seed gives Mutual Funds a target, so both lists have content.
      expect(
        snapshot.investmentTargets().map((status) => status.category),
        contains('Mutual Funds'),
      );
      expect(
        snapshot.budgetStatuses().map((status) => status.category),
        isNot(contains('Mutual Funds')),
      );
      expect(snapshot.investmentTargets().single.isInvestmentTarget, isTrue);
    });

    test('overfunding a target reads as achieved, not exceeded', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryMutualFunds,
        amountMinor: 2500000,
        date: DateTime(2026, 9, 5),
        direction: TxDirection.investment,
        payee: 'Index fund SIP',
      );

      final target = (await fixture.snapshot()).investmentTargets().firstWhere(
        (status) => status.category == 'Mutual Funds',
      );
      expect(target.budgetMinor, 2000000); // The seeded ₹20,000 target.
      expect(target.spentMinor, 2500000);
      expect(target.isOver, isTrue);
      expect(target.isMet, isTrue);
      // The kind is what lets the row render "Target met" instead of a red
      // "Over by", which would punish the user for succeeding.
      expect(target.isInvestmentTarget, isTrue);
    });

    test('the seeded umbrella reports the whole investing total', () async {
      // The bug this guards, reported from a device: ₹60,000 into mutual funds
      // left "Mutual Funds ₹60,000" beside "Investments ₹0", so the two read as
      // unrelated figures rather than a total and one of its parts.
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryMutualFunds,
        amountMinor: 6000000,
        date: DateTime(2026, 9, 5),
        direction: TxDirection.investment,
        payee: 'Index fund SIP',
      );

      final snapshot = await fixture.snapshot();
      final umbrella = snapshot.categoryNamed('Investments')!;
      expect(snapshot.isInvestmentRollup(umbrella), isTrue);
      expect(snapshot.investedForCategory(umbrella, testNow), 6000000);

      // A fund is a bucket, not a roll-up: it reports only its own entries.
      final funds = snapshot.categoryNamed('Mutual Funds')!;
      expect(snapshot.isInvestmentRollup(funds), isFalse);
      expect(snapshot.investedForCategory(funds, testNow), 6000000);

      // The breakdown the trends card draws still holds only what money was
      // actually filed against, so the umbrella reporting the total cannot have
      // it counted twice.
      expect(
        snapshot.investedByCategory(testNow).map((row) => row.category),
        <String>['Mutual Funds'],
      );
      expect(snapshot.investmentTotal(testNow), 6000000);
    });
  });

  testWidgets('the entry sheet names all three kinds of money movement', (
    tester,
  ) async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);

    await tester.pumpWidget(
      FinanceApp(
        repository: fixture.repository,
        initialSnapshot: await fixture.snapshot(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    // Scoped to the sheet: the shell keeps every screen alive in an
    // IndexedStack, so the dashboard's own "Income" tile and its "Mutual Funds"
    // target row are in the tree behind the sheet and would match too.
    Finder inSheet(String label) => find.descendant(
      of: find.byType(TransactionSheet),
      matching: find.text(label),
    );

    // The kind labels are what make investing discoverable. Without them a
    // user would have to already know that "Mutual Funds" behaves differently
    // from "Groceries" — and guessing wrong is what makes the totals wrong.
    expect(inSheet('Spending'), findsOneWidget);
    expect(inSheet('Investing'), findsOneWidget);
    expect(inSheet('Income'), findsOneWidget);

    // Order carries meaning: the two ways money leaves come first, and income
    // last. Relying on the enum's declaration order produced
    // Spending / Income / Investing on the device, which reads as though
    // investing were a kind of income.
    final spendingX = tester.getCenter(inSheet('Spending')).dx;
    final investingX = tester.getCenter(inSheet('Investing')).dx;
    final incomeX = tester.getCenter(inSheet('Income')).dx;
    expect(spendingX, lessThan(investingX));
    expect(investingX, lessThan(incomeX));

    // The seeded investing categories appear once investing is chosen, which is
    // the whole point of the kind selector — a user should not have to know
    // that "Mutual Funds" behaves differently from "Groceries" to find it.
    await tester.tap(inSheet('Investing'));
    await tester.pumpAndSettle();
    expect(inSheet('Mutual Funds'), findsOneWidget);
    expect(inSheet('Fixed Deposit'), findsOneWidget);

    // Switching kind moves the selection with it, so the sheet stays saveable
    // rather than silently holding a category the user can no longer see.
    expect(inSheet('Pick a category'), findsNothing);
    expect(inSheet('Enter an amount'), findsOneWidget);
  });

  testWidgets('a ledger row offers edit and delete', (tester) async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);
    await seedMinimal(fixture);

    await tester.pumpWidget(
      FinanceApp(
        repository: fixture.repository,
        initialSnapshot: await fixture.snapshot(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ledger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BigBasket'));
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    // The placeholder that used to sit here claimed editing was not built yet.
    expect(find.textContaining('arrive with the database layer'), findsNothing);
  });

  testWidgets('deleting asks first and names what will go', (tester) async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);
    await seedMinimal(fixture);

    await tester.pumpWidget(
      FinanceApp(
        repository: fixture.repository,
        initialSnapshot: await fixture.snapshot(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ledger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BigBasket'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // The prompt restates the entry rather than asking a bare "are you sure?".
    // Opening the wrong row in a long ledger is easy, and this is what catches
    // it. The deletion itself is asserted in the repository test above, because
    // a widget test must not start a real write and then tear down.
    expect(find.text('Delete this entry?'), findsOneWidget);
    expect(find.text('Keep it'), findsOneWidget);
    expect(find.textContaining('₹450.00 under Groceries'), findsOneWidget);
  });

  testWidgets('editing opens the sheet prefilled with the entry', (
    tester,
  ) async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);
    await seedMinimal(fixture);

    await tester.pumpWidget(
      FinanceApp(
        repository: fixture.repository,
        initialSnapshot: await fixture.snapshot(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ledger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BigBasket'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit transaction'), findsOneWidget);
    // Prefilled with the existing amount, so an edit is a correction rather than
    // a re-entry from memory.
    expect(find.text('Update ₹450.00'), findsOneWidget);
  });

  testWidgets('the entry sheet keeps the pad and Save reachable', (
    tester,
  ) async {
    // A regression guard with a real story behind it. Adding the third category
    // kind once pushed the numeric pad below the viewport on a short screen, so
    // tapping a digit silently missed and the sheet appeared to ignore input.
    // This asserts the requirement directly: on a realistic phone, a digit and
    // the save button are tappable without scrolling first.
    final fixture = makeFixture();
    addTearDown(fixture.dispose);

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      FinanceApp(
        repository: fixture.repository,
        initialSnapshot: await fixture.snapshot(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();

    expect(find.text('Save ₹5.00'), findsOneWidget);
    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save ₹5.00'),
    );
    expect(saveButton.onPressed, isNotNull);
  });
}
