import 'package:finance_app/app.dart';
import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/snapshot_views.dart';
import 'package:finance_db/finance_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

void main() {
  group('budgets', () {
    test('any category budget can be changed', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      final groceries = (await fixture.snapshot()).categories.firstWhere(
        (category) => category.name == 'Groceries',
      );
      expect(groceries.budgetMinor, 900000); // The seeded ₹9,000.

      await fixture.repository.setCategoryBudget(
        categoryId: groceries.id,
        budgetMinor: 2500000,
      );

      final after = await fixture.snapshot();
      expect(after.categoryNamed('Groceries')!.budgetMinor, 2500000);

      // The dashboard's budget bars must pick up the new figure, or the edit
      // would appear to do nothing.
      final status = after.budgetStatuses().firstWhere(
        (candidate) => candidate.category == 'Groceries',
      );
      expect(status.budgetMinor, 2500000);
    });

    test('clearing a budget removes it from the budget list', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      final before = await fixture.snapshot();
      expect(before.budgetStatuses().any((s) => s.category == 'Misc'), isTrue);

      final misc = before.categoryNamed('Misc')!;
      await fixture.repository.setCategoryBudget(
        categoryId: misc.id,
        budgetMinor: 0,
      );

      final after = await fixture.snapshot();
      expect(after.budgetStatuses().any((s) => s.category == 'Misc'), isFalse);
      // The category itself survives; only its limit is gone. That is what makes
      // the budgets screen's "no budget set" state reachable.
      expect(after.categoryNamed('Misc'), isNotNull);
    });
  });

  group('back-dating', () {
    test('an entry lands in the month it was dated', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      // Dated in August while the app's clock says 13 September.
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryGroceries,
        amountMinor: 45000,
        date: DateTime(2026, 8, 20),
        direction: TxDirection.expense,
        payee: 'Last month groceries',
      );

      final snapshot = await fixture.snapshot();
      expect(snapshot.transactions.single.date, DateTime(2026, 8, 20));
      expect(snapshot.summaryFor(DateTime(2026, 8)).expenseMinor, 45000);
      expect(
        snapshot.currentMonth.expenseMinor,
        0,
        reason: 'September must stay empty',
      );
    });
  });

  testWidgets('the entry sheet defaults to today and offers a date picker', (
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

    // Defaults to today, and says so.
    expect(find.text('Today'), findsOneWidget);

    // The control opens a real picker, so a back-dated entry is possible.
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);

    // Scoped to the dialog: the entry sheet behind it also has a "Cancel".
    await tester.tap(
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
  });
}
