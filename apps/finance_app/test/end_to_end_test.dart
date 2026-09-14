import 'package:finance_app/app.dart';
import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/snapshot_views.dart';
import 'package:finance_db/finance_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

void main() {
  testWidgets('quick add refuses to save with no amount, then enables', (
    tester,
  ) async {
    // Scope is deliberately the UI contract only. Recording is asserted in the
    // repository test below, because a widget test that starts a real database
    // write and then tears down fights the test harness rather than the code.
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

    // Nothing typed: saving is refused rather than recording ₹0.
    expect(find.text('Enter an amount'), findsOneWidget);
    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Enter an amount'),
    );
    expect(saveButton.onPressed, isNull);

    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();

    expect(find.text('Save ₹25.00'), findsOneWidget);
    final enabledButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save ₹25.00'),
    );
    expect(enabledButton.onPressed, isNotNull);

    // The pad caps at eight digits, so a stray long press cannot produce an
    // absurd amount. "25" plus six more digits is the ceiling.
    for (var i = 0; i < 12; i++) {
      await tester.tap(find.text('9'));
      await tester.pump();
    }
    expect(find.text('Save ₹2,59,99,999.00'), findsOneWidget);
  });

  test('recording an entry persists it and moves every aggregate', () async {
    // The persistence half of the same flow, asserted where the future can
    // actually be awaited.
    final fixture = makeFixture();
    addTearDown(fixture.dispose);

    await fixture.repository.addTransaction(
      accountId: SeedIds.accountHdfc,
      categoryId: SeedIds.categoryGroceries,
      amountMinor: 12345,
      date: DateTime(2026, 9, 8),
      direction: TxDirection.expense,
      payee: 'Corner shop',
    );

    final snapshot = await fixture.snapshot();
    expect(snapshot.transactions, hasLength(1));

    final saved = snapshot.transactions.single;
    expect(saved.amountMinor, 12345);
    expect(saved.payee, 'Corner shop');
    expect(saved.category, 'Groceries');
    expect(saved.account, 'HDFC Savings');
    expect(saved.date, DateTime(2026, 9, 8));

    expect(snapshot.currentMonth.expenseMinor, 12345);
    expect(snapshot.spendByCategory(testNow).single.totalMinor, 12345);
    expect(snapshot.cumulativeDailySpend().last, closeTo(123.45, 0.01));
  });

  test('deleting an entry removes it from every aggregate', () async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);
    await seedMinimal(fixture);

    final before = await fixture.snapshot();
    expect(before.transactions, hasLength(2));
    final expense = before.transactions.firstWhere((txn) => txn.isExpense);

    await fixture.repository.deleteTransaction(expense.id);
    final after = await fixture.snapshot();

    expect(after.transactions, hasLength(1));
    expect(after.currentMonth.expenseMinor, 0);
    // A deleted entry must vanish from the charts too, not just the list.
    expect(after.spendByCategory(testNow), isEmpty);
  });

  test('sample data loads and can be erased', () async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);

    final inserted = await fixture.repository.loadSampleData();
    expect(inserted, greaterThan(50));

    final loaded = await fixture.snapshot();
    expect(loaded.transactions.length, inserted);
    expect(loaded.currentMonth.expenseMinor, greaterThan(0));
    expect(loaded.monthlySummaries.length, greaterThan(3));

    await fixture.repository.eraseTransactions();
    final erased = await fixture.snapshot();
    expect(erased.transactions, isEmpty);
    expect(erased.currentMonth.expenseMinor, 0);
  });

  test('a budget change is reflected in the budget bars', () async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);

    final categories = (await fixture.snapshot()).categories;
    final groceries = categories.firstWhere(
      (category) => category.name == 'Groceries',
    );
    expect(groceries.budgetMinor, 900000); // The seeded ₹9,000.

    await fixture.repository.setCategoryBudget(
      categoryId: groceries.id,
      budgetMinor: 1500000,
    );

    final updated = (await fixture.snapshot()).categories.firstWhere(
      (category) => category.name == 'Groceries',
    );
    expect(updated.budgetMinor, 1500000);
  });

  test('derived views agree with each other', () async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);
    await seedMinimal(fixture);
    final snapshot = await fixture.snapshot();

    // Category totals must sum to the headline figure, or the donut and the
    // total would disagree on screen.
    final spends = snapshot.spendByCategory(testNow);
    final summed = spends.fold(0, (sum, spend) => sum + spend.totalMinor);
    expect(summed, snapshot.currentMonth.expenseMinor);

    // Income must never leak into spend.
    expect(spends.any((spend) => spend.category == 'Income'), isFalse);

    // Budgets come from the seeded categories, so some must exist.
    expect(snapshot.budgetStatuses(), isNotEmpty);

    // The pace curve must end at the month total.
    final pace = snapshot.cumulativeDailySpend();
    expect(pace.last, closeTo(snapshot.currentMonth.expenseMinor / 100, 0.01));

    // The savings rate must reflect the seeded salary against the expense.
    expect(snapshot.currentMonth.savingsRate, isNotNull);
    expect(snapshot.currentMonth.savingsRate, greaterThan(90));
  });
}
