import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/scheduled_views.dart';
import 'package:finance_app/data/subscription.dart';
import 'package:finance_db/finance_db.dart' hide CategoryKind;
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// Tier 1.3: what repeats, and what it costs over a year.
///
/// "₹499 a month" is a decision nobody makes; "₹5,988 a year" is one they do, so
/// the annual figure is the reason the list exists and the order it is shown in.
void main() {
  test('annualises every expense rule and sorts by the yearly cost', () {
    final snapshot = snapshotWith(
      recurringRules: <RecurringRule>[
        ruleDue(
          nextDueOn: DateTime(2026, 10, 5),
          amountMinor: 49900,
          category: 'Subscriptions',
          payee: 'Netflix',
          id: 'rule-netflix',
        ),
        ruleDue(
          nextDueOn: DateTime(2026, 10, 13),
          amountMinor: 1800000,
          category: 'Rent',
          payee: 'Monthly rent transfer',
          id: 'rule-rent',
        ),
        // Money moved, not money spent: a subscription list is about cost (C1).
        ruleDue(
          nextDueOn: DateTime(2026, 10, 1),
          amountMinor: 2000000,
          category: 'Mutual Funds',
          direction: TxDirection.investment,
          id: 'rule-invest',
        ),
        // Income is not a cost at all.
        ruleDue(
          nextDueOn: DateTime(2026, 10, 1),
          amountMinor: 5000000,
          category: 'Income',
          direction: TxDirection.income,
          id: 'rule-income',
        ),
      ],
    );

    final subscriptions = snapshot.subscriptions;

    expect(subscriptions.map((item) => item.category), <String>[
      'Rent',
      'Subscriptions',
    ]);
    expect(subscriptions.first.annualMinor, 21600000);
    expect(subscriptions.last.annualMinor, 598800);
    expect(subscriptions.last.payee, 'Netflix');
    expect(subscriptions.last.nextDueOn, DateTime(2026, 10, 5));
    // The monthly figure is still on the model: a list that only annualises
    // cannot be reconciled with the entry the user recorded.
    expect(subscriptions.last.amountMinor, 49900);
    expect(snapshot.annualSubscriptionsMinor, 22198800);
  });

  test('a rule with no payee is still listed', () {
    final snapshot = snapshotWith(
      recurringRules: <RecurringRule>[
        ruleDue(nextDueOn: DateTime(2026, 10, 13), amountMinor: 1800000),
      ],
    );

    expect(snapshot.subscriptions.single.payee, isEmpty);
  });

  test('nothing repeats, so nothing is annualised', () {
    final snapshot = snapshotWith();
    expect(snapshot.subscriptions, isEmpty);
    expect(snapshot.annualSubscriptionsMinor, 0);
  });

  test('a rule written through the repository is annualised too', () async {
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

    final subscription = (await fixture.snapshot()).subscriptions.single;

    expect(subscription.category, 'Rent');
    expect(subscription.payee, 'Monthly rent transfer');
    expect(subscription.annualMinor, 1800000 * Subscription.periodsPerYear);
  });
}
