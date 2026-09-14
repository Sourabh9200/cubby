import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/period_views.dart';
import 'package:finance_app/data/stats_period.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// Tier 1.1 and 1.2: where a period is heading, and what that leaves per day.
///
/// The rules are assembled by hand rather than written through the repository,
/// because the writer advances a rule's due date against the real clock: a test
/// about "what is still to post this month" would pass this week and fail the
/// next. The spending is hand-written for the same reason — every figure here is
/// arithmetic over rows, and the rows are the input.
void main() {
  /// 46 recorded days from 1 March out of the 184 days to 1 September, so the
  /// expected day is ₹1,000 × 46 ÷ 184 = ₹250.
  List<Transaction> history() => <Transaction>[
    for (var day = 0; day < 46; day++)
      expenseOn(DateTime(2026, 3, 1 + day), 100000),
  ];

  test('projects a period from its own recorded days', () {
    final snapshot = snapshotWith(
      transactions: <Transaction>[
        ...history(),
        expenseOn(DateTime(2026, 9, 5), 500000),
      ],
      recurringRules: <RecurringRule>[
        // Due inside the month, so it is committed.
        ruleDue(nextDueOn: DateTime(2026, 9, 20), amountMinor: 200000),
        // An investing rule is money moved, not money spent (C1).
        ruleDue(
          nextDueOn: DateTime(2026, 9, 25),
          amountMinor: 500000,
          direction: TxDirection.investment,
          id: 'rule-invest',
        ),
        // Due after the month ends, so it is not committed to *this* period.
        ruleDue(
          nextDueOn: DateTime(2026, 10, 5),
          amountMinor: 900000,
          id: 'rule-next',
        ),
      ],
    );

    final projection = snapshot.projectionFor(
      StatsRange.containing(StatsPeriod.month, testNow),
    );

    expect(projection, isNotNull);
    expect(projection!.spentMinor, 500000);
    expect(projection.committedMinor, 200000);
    expect(projection.ruleCount, 1);
    // 13 of September's 30 days have happened.
    expect(projection.daysRemaining, 17);
    expect(projection.activeDayMedianMinor, 100000);
    expect(projection.recordedDays, 46);
    // ₹250 a day expected × 17 days left.
    expect(projection.dailyRateMinor, 25000);
    expect(projection.projectedVariableMinor, 425000);
    expect(projection.projectedTotalMinor, 1125000);
    expect(projection.hasBasis, isTrue);
  });

  test('says nothing about a period that is over', () {
    final snapshot = snapshotWith(
      transactions: <Transaction>[
        ...history(),
        expenseOn(DateTime(2026, 8, 5), 500000),
      ],
    );

    // A projection of a finished month is a statement about the past dressed up
    // as a forecast (C5).
    expect(
      snapshot.projectionFor(
        StatsRange.containing(StatsPeriod.month, DateTime(2026, 8, 15)),
      ),
      isNull,
    );
  });

  test('clips its window to the ledger, not to the months asked for', () {
    final snapshot = snapshotWith(
      transactions: <Transaction>[
        for (var day = 0; day < 10; day++)
          expenseOn(DateTime(2026, 8, 1 + day), 100000),
      ],
    );

    final projection = snapshot.projectionFor(
      StatsRange.containing(StatsPeriod.month, testNow),
    )!;

    expect(projection.monthsOfHistory, 1);
    expect(projection.recordedDays, 10);
    // ₹1,000 × 10 days ÷ the 31 days of August, not ÷ the 184 days of six
    // months the app did not exist for.
    expect(projection.dailyRateMinor, 32258);
  });

  test('a period with nothing behind it has no basis', () {
    final empty = snapshotWith();
    final projection = empty.projectionFor(
      StatsRange.containing(StatsPeriod.month, testNow),
    )!;

    expect(projection.hasBasis, isFalse);
    expect(projection.projectedTotalMinor, 0);
    expect(projection.dailyRateMinor, 0);
    // The screen's job is to say "not enough history" rather than to print a
    // confident ₹0 (C5, C11).
    expect(
      empty
          .projectionFor(StatsRange.containing(StatsPeriod.week, testNow))!
          .hasBasis,
      isFalse,
    );
  });

  test('a week gets what is committed and nothing more', () {
    final snapshot = snapshotWith(
      transactions: <Transaction>[...history(), expenseOn(testNow, 200000)],
      recurringRules: <RecurringRule>[
        ruleDue(nextDueOn: DateTime(2026, 9, 13), amountMinor: 100000),
      ],
    );

    final projection = snapshot.projectionFor(
      StatsRange.containing(StatsPeriod.week, testNow),
    )!;

    // The week ends today, so nothing is left to project and the rule due today
    // is the last thing in it.
    expect(projection.daysRemaining, 0);
    expect(projection.projectedVariableMinor, 0);
    expect(projection.committedMinor, 100000);
  });

  group('safe to spend', () {
    test('spreads what is left of the limits over the days remaining', () {
      final snapshot = snapshotWith(
        transactions: <Transaction>[
          ...history(),
          expenseOn(DateTime(2026, 9, 5), 500000),
        ],
        categories: <Category>[
          spendingCategory('Groceries', budgetMinor: 300000),
          spendingCategory('Dining Out', budgetMinor: 200000),
          // A category with no limit is not part of the plan (C4).
          spendingCategory('Shopping'),
        ],
      );
      final range = StatsRange.containing(StatsPeriod.month, testNow);
      final projection = snapshot.projectionFor(range)!;

      expect(snapshot.budgetLimitIn(range), 500000);
      // Heading for ₹9,250 against ₹5,000 of limits: nothing is left, and the
      // figure is floored rather than reported as a negative allowance.
      expect(projection.projectedTotalMinor, 925000);
      expect(projection.overshoots(500000), isTrue);
      expect(projection.safePerDayMinor(500000), 0);
      // Against ₹20,000 of limits: ₹10,750 left over 17 days.
      expect(projection.overshoots(2000000), isFalse);
      expect(projection.safePerDayMinor(2000000), 63235);
    });

    test('a week holds no whole month, so it holds no daily allowance', () {
      final snapshot = snapshotWith(
        transactions: <Transaction>[expenseOn(testNow, 100000)],
        categories: <Category>[
          spendingCategory('Groceries', budgetMinor: 300000),
        ],
      );

      expect(
        snapshot.budgetLimitIn(
          StatsRange.containing(StatsPeriod.week, testNow),
        ),
        0,
      );
    });

    test('a quarter scales the limits it is measured against', () {
      final snapshot = snapshotWith(
        categories: <Category>[
          spendingCategory('Groceries', budgetMinor: 300000),
        ],
      );

      expect(
        snapshot.budgetLimitIn(
          StatsRange.containing(StatsPeriod.quarter, testNow),
        ),
        900000,
      );
      expect(
        snapshot.budgetLimitIn(
          StatsRange.containing(StatsPeriod.year, testNow),
        ),
        3600000,
      );
    });
  });
}
