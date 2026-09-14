import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/scheduled_views.dart';
import 'package:finance_db/finance_db.dart' hide CategoryKind;
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// Tier 0.6: what recurring rules already account for.
///
/// A rule describes a habit, never an obligation (C14), so every figure here
/// means *scheduled*. The rules are assembled by hand rather than written
/// through the repository, because the writer advances `nextDueOn` against the
/// real clock — a test about what falls due next would pass this week and fail
/// the next.
void main() {
  group('committed spend', () {
    test('sums the live expense rules', () {
      final snapshot = snapshotWith(
        recurringRules: <RecurringRule>[
          ruleDue(
            nextDueOn: DateTime(2026, 10, 13),
            amountMinor: 1800000,
            category: 'Rent',
            payee: 'Monthly rent transfer',
          ),
          ruleDue(
            nextDueOn: DateTime(2026, 10, 20),
            amountMinor: 99900,
            category: 'Utilities',
            id: 'rule-2',
          ),
        ],
      );

      expect(snapshot.committedMonthlyMinor, 1899900);
      expect(snapshot.scheduledExpenseRules, hasLength(2));
    });

    test('keeps investing and income rules out of the spending figure', () {
      final snapshot = snapshotWith(
        recurringRules: <RecurringRule>[
          ruleDue(
            nextDueOn: DateTime(2026, 10, 13),
            amountMinor: 1800000,
            category: 'Rent',
          ),
          ruleDue(
            nextDueOn: DateTime(2026, 10, 1),
            amountMinor: 2000000,
            category: 'Mutual Funds',
            direction: TxDirection.investment,
            id: 'rule-invest',
          ),
          ruleDue(
            nextDueOn: DateTime(2026, 10, 1),
            amountMinor: 5000000,
            category: 'Income',
            direction: TxDirection.income,
            id: 'rule-income',
          ),
        ],
      );

      // A SIP is not consumption, and a salary rule is not a guarantee (C1).
      expect(snapshot.committedMonthlyMinor, 1800000);
      expect(snapshot.committedInvestmentMinor, 2000000);
      expect(snapshot.committedIncomeMinor, 5000000);
    });

    test('is zero when nothing repeats', () {
      final snapshot = snapshotWith();
      expect(snapshot.committedMonthlyMinor, 0);
      expect(snapshot.committedInvestmentMinor, 0);
      expect(snapshot.committedIncomeMinor, 0);
      expect(snapshot.upcomingDues(), isEmpty);
    });
  });

  group('upcomingDues', () {
    /// One rule per boundary of the window: today, inside it, at its end, past
    /// it and beyond it.
    List<RecurringRule> boundaryRules() => <RecurringRule>[
      // Exactly thirty days away, which is outside a thirty-day window.
      ruleDue(
        nextDueOn: DateTime(2026, 10, 13),
        amountMinor: 100,
        id: 'day-30',
      ),
      ruleDue(nextDueOn: DateTime(2026, 9, 20), amountMinor: 200, id: 'inside'),
      ruleDue(nextDueOn: DateTime(2026, 9, 13), amountMinor: 300, id: 'today'),
      ruleDue(
        nextDueOn: DateTime(2026, 9, 12),
        amountMinor: 400,
        id: 'yesterday',
      ),
      ruleDue(
        nextDueOn: DateTime(2026, 10, 12),
        amountMinor: 500,
        id: 'day-29',
      ),
    ];

    test('lists what falls due in the window, today included', () {
      final dues = snapshotWith(recurringRules: boundaryRules()).upcomingDues();

      // A rule due today has not posted yet, so it is still coming.
      expect(dues.map((due) => due.ruleId), <String>[
        'today',
        'inside',
        'day-29',
      ]);
      expect(dues.first.dueOn, DateTime(2026, 9, 13));
    });

    test('a longer window reaches further', () {
      final dues = snapshotWith(recurringRules: boundaryRules())
          .upcomingDues(days: 31);

      expect(dues.map((due) => due.ruleId), contains('day-30'));
    });

    test('breaks a shared date by category', () {
      final snapshot = snapshotWith(
        recurringRules: <RecurringRule>[
          ruleDue(
            nextDueOn: DateTime(2026, 9, 20),
            amountMinor: 100,
            category: 'Utilities',
            id: 'utilities',
          ),
          ruleDue(
            nextDueOn: DateTime(2026, 9, 20),
            amountMinor: 200,
            category: 'Rent',
            id: 'rent',
          ),
        ],
      );

      expect(snapshot.upcomingDues().map((due) => due.ruleId), <String>[
        'rent',
        'utilities',
      ]);
    });

    test('carries the payee, category and direction of the rule', () {
      final snapshot = snapshotWith(
        recurringRules: <RecurringRule>[
          ruleDue(
            nextDueOn: DateTime(2026, 9, 20),
            amountMinor: 2000000,
            category: 'Mutual Funds',
            direction: TxDirection.investment,
            payee: 'SIP',
          ),
        ],
      );

      final due = snapshot.upcomingDues().single;
      expect(due.payee, 'SIP');
      expect(due.category, 'Mutual Funds');
      expect(due.isInvestment, isTrue);
      expect(due.isExpense, isFalse);
      expect(due.amountMinor, 2000000);
    });
  });

  test('stopping a rule takes it out of the figure immediately', () async {
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

    var snapshot = await fixture.snapshot();
    expect(snapshot.committedMonthlyMinor, 1800000);

    // Rules are soft-deleted and the snapshot only carries live rows, so the
    // figure cannot lag behind a stopped rule (C14).
    await fixture.repository.stopRecurringRule(
      snapshot.recurringRules.single.id,
    );
    snapshot = await fixture.snapshot();
    expect(snapshot.committedMonthlyMinor, 0);
    expect(snapshot.recurringRules, isEmpty);
  });
}
