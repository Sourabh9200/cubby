import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/recurring_candidate.dart';
import 'package:finance_app/data/snapshot_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// Tier 1.4: payees that look like they repeat, offered as a proposal.
///
/// A proposal and never a write (C14), matched on the payee string exactly as
/// recorded (C8), with the tolerances carried on the model so the UI can state
/// them rather than hide them.
void main() {
  /// A monthly trio for [payee], ending [lastDaysAgo] days before the test clock.
  List<Transaction> monthly(
    String payee,
    int amountMinor, {
    int months = 3,
    int lastDaysAgo = 8,
    String category = 'Groceries',
  }) => <Transaction>[
    for (var back = months - 1; back >= 0; back--)
      expenseOn(
        DateTime(2026, 9, 13).subtract(Duration(days: lastDaysAgo + 30 * back)),
        amountMinor,
        payee: payee,
        category: category,
      ),
  ];

  test('suggests a payee paid monthly for about the same amount', () {
    final snapshot = snapshotWith(
      transactions: <Transaction>[
        expenseOn(DateTime(2026, 7, 7), 30000, payee: 'Zomato'),
        // One odd month does not disqualify a real subscription.
        expenseOn(DateTime(2026, 8, 6), 31000, payee: 'Zomato'),
        expenseOn(DateTime(2026, 9, 5), 30000, payee: 'Zomato'),
      ],
    );

    final candidate = snapshot.recurringCandidates().single;

    expect(candidate.payee, 'Zomato');
    expect(candidate.occurrences, 3);
    expect(candidate.typicalAmountMinor, 30000);
    expect(candidate.lastDate, DateTime(2026, 9, 5));
    expect(candidate.category, 'Groceries');
  });

  test('ignores payees that are not monthly', () {
    final snapshot = snapshotWith(
      transactions: <Transaction>[
        // 45 days apart: two a season, not a month.
        expenseOn(DateTime(2026, 6, 1), 30000, payee: 'Gym'),
        expenseOn(DateTime(2026, 7, 16), 30000, payee: 'Gym'),
        expenseOn(DateTime(2026, 8, 30), 30000, payee: 'Gym'),
      ],
    );

    expect(snapshot.recurringCandidates(), isEmpty);
  });

  test('ignores payees whose amounts are not alike', () {
    final snapshot = snapshotWith(
      transactions: <Transaction>[
        // Monthly spacing, but ₹100, ₹300 and ₹900: not one subscription.
        expenseOn(DateTime(2026, 7, 10), 10000, payee: 'Odd'),
        expenseOn(DateTime(2026, 8, 9), 30000, payee: 'Odd'),
        expenseOn(DateTime(2026, 9, 8), 90000, payee: 'Odd'),
      ],
    );

    expect(snapshot.recurringCandidates(), isEmpty);
  });

  test('ignores a habit that stopped two cycles ago', () {
    final snapshot = snapshotWith(
      transactions: <Transaction>[...monthly('Old', 30000, lastDaysAgo: 75)],
    );

    // A subscription last seen in June is one that was cancelled; proposing it
    // would be proposing history.
    expect(snapshot.recurringCandidates(), isEmpty);
  });

  test('needs three occurrences before it will suggest anything', () {
    final snapshot = snapshotWith(
      transactions: <Transaction>[...monthly('Twice', 30000, months: 2)],
    );

    expect(snapshot.recurringCandidates(), isEmpty);
  });

  test('leaves a payee that already has a rule alone', () {
    final snapshot = snapshotWith(
      transactions: <Transaction>[...monthly('Netflix', 49900)],
      recurringRules: <RecurringRule>[
        ruleDue(
          nextDueOn: DateTime(2026, 10, 5),
          amountMinor: 49900,
          category: 'Subscriptions',
          payee: 'Netflix',
        ),
      ],
    );

    // Proposing a rule that already exists would be noise at best.
    expect(snapshot.recurringCandidates(), isEmpty);
  });

  test('only reads expenses, and only named payees', () {
    final snapshot = snapshotWith(
      transactions: <Transaction>[
        ...monthly(
          'Salary',
          5000000,
        ).map((txn) => txn.copyWith(direction: TxDirection.income)),
        ...monthly('', 30000),
      ],
    );

    expect(snapshot.recurringCandidates(), isEmpty);
  });

  test('orders proposals by what they cost over the window', () {
    final snapshot = snapshotWith(
      transactions: <Transaction>[
        ...monthly('Zomato', 30000),
        ...monthly('Cloud', 50000),
      ],
    );

    expect(snapshot.recurringCandidates().map((c) => c.payee), <String>[
      'Cloud',
      'Zomato',
    ]);
  });

  test('the tolerances it promises are the tolerances it uses', () {
    // Stated by the UI, so pinned here: a late payment costs the suggestion.
    final justLate = snapshotWith(
      transactions: <Transaction>[
        expenseOn(DateTime(2026, 7, 7), 30000, payee: 'Zomato'),
        expenseOn(DateTime(2026, 8, 4), 30000, payee: 'Zomato'),
        expenseOn(DateTime(2026, 9, 5), 30000, payee: 'Zomato'),
      ],
    );

    // 28 and 32 days: inside 30 ± 3.
    expect(justLate.recurringCandidates(), hasLength(1));
    expect(RecurringCandidate.toleranceDays, 3);
    expect(RecurringCandidate.minimumOccurrences, 3);
  });
}
