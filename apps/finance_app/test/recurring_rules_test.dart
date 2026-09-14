import 'package:finance_app/app.dart';
import 'package:finance_app/data/models.dart';
import 'package:finance_db/finance_db.dart' hide CategoryKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// Recurring rules, from the app's side.
///
/// The posting itself — catch-up, idempotency, the cap, day clamping — is pinned
/// in `packages/finance_db/test/recurring_test.dart`, where the clock is a
/// parameter. Everything here is deliberately independent of today's date, since
/// these run through the repository, which uses the real clock: asserting that a
/// back-dated rule posts three months would pass this year and fail next.
void main() {
  group('creating a rule', () {
    test('schedules the month after the entry it came from', () async {
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

      final rule = (await fixture.snapshot()).recurringRules.single;
      expect(rule.category, 'Rent');
      expect(rule.account, 'HDFC Savings');
      expect(rule.amountMinor, 1800000);
      expect(rule.payee, 'Monthly rent transfer');
      // The entry it was created from is already in the ledger, so repeating
      // from its own month would post that rent a second time.
      expect(rule.dayOfMonth, 13);
      expect(rule.nextDueOn, DateTime(2026, 10, 13));
      expect(rule.isExpense, isTrue);
    });

    test('carries the direction of the entry it was made from', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      await fixture.repository.addRecurringRule(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryMutualFunds,
        amountMinor: 2000000,
        direction: TxDirection.investment,
        startedOn: testNow,
      );

      final rule = (await fixture.snapshot()).recurringRules.single;
      // Stored on the rule rather than re-read from the category, so
      // re-kindling a category later cannot turn a fund contribution into
      // spending on the next posting.
      expect(rule.isInvestment, isTrue);
      expect(rule.isExpense, isFalse);
    });

    test('lists rules soonest due first', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      await fixture.repository.addRecurringRule(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryMutualFunds,
        amountMinor: 500000,
        direction: TxDirection.investment,
        startedOn: DateTime(2026, 9, 20),
      );
      await fixture.repository.addRecurringRule(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryRent,
        amountMinor: 1800000,
        direction: TxDirection.expense,
        startedOn: DateTime(2026, 9, 13),
      );

      expect(
        (await fixture.snapshot()).recurringRules.map((rule) => rule.category),
        <String>['Rent', 'Mutual Funds'],
      );
    });
  });

  test(
    'stopping a rule removes it without touching what it recorded',
    () async {
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
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryRent,
        amountMinor: 1800000,
        date: testNow,
        direction: TxDirection.expense,
        payee: 'Monthly rent transfer',
      );
      final rule = (await fixture.snapshot()).recurringRules.single;

      await fixture.repository.stopRecurringRule(rule.id);

      final snapshot = await fixture.snapshot();
      expect(snapshot.recurringRules, isEmpty);
      // "Not again" is not "erase the rent you already paid".
      expect(snapshot.transactions, hasLength(1));
      expect(snapshot.currentMonth.expenseMinor, 1800000);
    },
  );

  test('making an existing entry recurring starts next month, not in the past', () async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);

    // An entry from months ago, switched to recurring today.
    await fixture.repository.addRecurringRule(
      accountId: SeedIds.accountHdfc,
      categoryId: SeedIds.categoryRent,
      amountMinor: 1800000,
      direction: TxDirection.expense,
      startedOn: DateTime(2026, 1, 5),
      payee: 'Monthly rent transfer',
      postMissedMonths: false,
    );

    final snapshot = await fixture.snapshot();
    final rule = snapshot.recurringRules.single;

    // The day comes from the entry: rent falls on the 5th whatever day it
    // happened to be switched on.
    expect(rule.dayOfMonth, 5);
    // And nothing was posted for the months between January and today, because
    // the user may already have recorded them by hand. Of the two possible
    // mistakes, only a duplicate is visible on screen.
    expect(snapshot.transactions, isEmpty);
    expect(rule.nextDueOn.isAfter(DateTime.now()), isTrue);
    expect(rule.nextDueOn.day, 5);
  });

  testWidgets('an existing entry can be made recurring from the edit sheet', (
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

    expect(find.text('Repeat'), findsOneWidget);
    expect(find.text('Update ₹450.00'), findsOneWidget);

    await tester.tap(find.text('Repeat'));
    await tester.pumpAndSettle();

    // Saving is asserted at the repository level instead: a widget test that
    // starts a real database write and then tears down fights the harness rather
    // than the code.
    expect(find.text('Update ₹450.00 · monthly'), findsOneWidget);
  });

  testWidgets('the entry sheet offers Repeat and says so before saving', (
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

    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();
    expect(find.text('Save ₹5.00'), findsOneWidget);

    // The chip is the shortest honest control that fits beside the date chip, so
    // the button is where the consequence is stated.
    await tester.tap(find.text('Repeat'));
    await tester.pumpAndSettle();
    expect(find.text('Save ₹5.00 · monthly'), findsOneWidget);
  });

  testWidgets('settings lists an active rule and offers to stop it', (
    tester,
  ) async {
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

    await tester.pumpWidget(
      FinanceApp(
        repository: fixture.repository,
        initialSnapshot: await fixture.snapshot(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final recurring = find.ancestor(
      of: find.text('Recurring'),
      matching: find.byType(Card),
    );
    await tester.scrollUntilVisible(recurring, 300);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: recurring, matching: find.text('Rent · ₹18,000')),
      findsOneWidget,
    );
    // The day is spelled the way a rent is described, not as a raw number.
    expect(
      find.descendant(
        of: recurring,
        matching: find.text('Every month on the 13th · next 13 Oct'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: recurring,
        matching: find.byIcon(Icons.stop_circle_outlined),
      ),
      findsOneWidget,
    );
  });
}
