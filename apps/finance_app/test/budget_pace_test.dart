import 'package:finance_app/data/finance_snapshot.dart';
import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/period_views.dart';
import 'package:finance_app/data/snapshot_analytics.dart';
import 'package:finance_app/data/stats_period.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// Tier 1.5 and 1.6: a limit read at the pace actually being spent, and a limit
/// offered from what the user's own months cost.
///
/// Both are figures about *acting in time*, so both are only allowed to exist
/// while the period is running and while there is enough history to be honest
/// about (C4, C6, C7).
void main() {
  group('budget pace', () {
    /// ₹10,000 of groceries and ₹1,000 of dining by the 13th, with limits of
    /// ₹15,000 and ₹5,000, and a category with no limit at all.
    FinanceSnapshot paceFixture() => snapshotWith(
      transactions: <Transaction>[
        expenseOn(DateTime(2026, 9, 5), 1000000),
        expenseOn(
          DateTime(2026, 9, 6),
          100000,
          category: 'Dining Out',
          payee: 'Swiggy',
        ),
      ],
      categories: <Category>[
        spendingCategory('Groceries', budgetMinor: 1500000),
        spendingCategory('Dining Out', budgetMinor: 500000),
        spendingCategory('Shopping'),
      ],
    );

    test('projects each limited category and puts the one at risk first', () {
      final snapshot = paceFixture();
      final paces = snapshot.budgetPaceIn(
        StatsRange.containing(StatsPeriod.month, testNow),
      );

      // A category with no limit is not part of the plan (C4).
      expect(paces.map((pace) => pace.category), <String>[
        'Groceries',
        'Dining Out',
      ]);

      final groceries = paces.first;
      expect(groceries.spentMinor, 1000000);
      // 13 of 30 days elapsed, so this pace lands at ₹23,077 against ₹15,000.
      expect(groceries.projectedMinor, 2307692);
      expect(groceries.isProjectedOver, isTrue);
      expect(groceries.overshootMinor, 807692);
      // ₹50,000 still inside the limit, over 17 days.
      expect(groceries.safePerDayMinor, 29411);

      final dining = paces.last;
      expect(dining.isProjectedOver, isFalse);
      expect(dining.overshootMinor, 0);
      expect(dining.safePerDayMinor, 23529);
    });

    test('a period that is over has no pace to read', () {
      final snapshot = paceFixture();

      // "Heading for" about a finished month is a statement about the past
      // dressed up as a warning.
      expect(
        snapshot.budgetPaceIn(
          StatsRange.containing(StatsPeriod.month, DateTime(2026, 8, 10)),
        ),
        isEmpty,
      );
    });

    test('the last day of a month leaves no days and no allowance', () {
      final snapshot = snapshotWith(
        transactions: <Transaction>[expenseOn(DateTime(2026, 9, 20), 500000)],
        categories: <Category>[
          spendingCategory('Groceries', budgetMinor: 1500000),
        ],
        now: DateTime(2026, 9, 30, 12),
      );

      expect(
        snapshot.budgetPaceIn(
          StatsRange.containing(StatsPeriod.month, DateTime(2026, 9, 30)),
        ),
        isEmpty,
      );
    });

    test('a category well inside its limit is not flagged', () {
      final snapshot = snapshotWith(
        transactions: <Transaction>[expenseOn(DateTime(2026, 9, 5), 100000)],
        categories: <Category>[
          spendingCategory('Groceries', budgetMinor: 1500000),
        ],
      );

      final pace = snapshot
          .budgetPaceIn(StatsRange.containing(StatsPeriod.month, testNow))
          .single;

      expect(pace.isProjectedOver, isFalse);
      // ₹14,000 left over 17 days.
      expect(pace.safePerDayMinor, 82352);
    });
  });

  group('suggested limits', () {
    /// Six complete months of history, so the window is covered, with groceries
    /// in every one of them and two categories that are not monthly habits.
    FinanceSnapshot historyFixture() => snapshotWith(
      // One entry on the first day of the window: this is what makes the window
      // "inside the ledger's life" rather than before it (C7).
      transactions: <Transaction>[
        expenseOn(DateTime(2026, 3, 1), 1, category: 'Misc', payee: 'Anchor'),
      ],
      categories: <Category>[
        spendingCategory('Groceries'),
        spendingCategory('Coffee'),
        spendingCategory('Insurance'),
      ],
      categorySpendByMonth: <String, Map<String, int>>{
        '2026-03': <String, int>{'Groceries': 500000, 'Insurance': 1800000},
        '2026-04': <String, int>{'Groceries': 600000},
        '2026-05': <String, int>{'Groceries': 700000},
        '2026-06': <String, int>{'Groceries': 800000, 'Coffee': 20000},
        '2026-07': <String, int>{'Groceries': 1500000, 'Coffee': 22000},
        '2026-08': <String, int>{'Groceries': 900000},
      },
    );

    test('offers the median and the p90 of the window', () {
      final suggestion = historyFixture().suggestedLimits().single;

      expect(suggestion.category, 'Groceries');
      expect(suggestion.medianMinor, 750000);
      expect(suggestion.p90Minor, 1500000);
      expect(suggestion.monthsRecorded, 6);
      // The proposal is the median: a limit set at the p90 would leave the user
      // "within budget" in the very months they overspent.
      expect(suggestion.suggestedMinor, 750000);
      expect(suggestion.hasSpread, isTrue);
    });

    test('says nothing about a category that is not a monthly habit', () {
      final categories = historyFixture().suggestedLimits().map(
        (suggestion) => suggestion.category,
      );

      // Insurance appears in one month of six: five zeros and one large month
      // have a median of zero, and a limit of nothing is not a limit.
      expect(categories, isNot(contains('Insurance')));
      // Coffee appears in two, which is still mostly zeros.
      expect(categories, isNot(contains('Coffee')));
    });

    test('says nothing when the window is not inside the ledger', () {
      final snapshot = snapshotWith(
        // The ledger starts a month after the window does, so "your average
        // month" would be an average over months the app did not exist for.
        transactions: <Transaction>[expenseOn(DateTime(2026, 4, 1), 1)],
        categories: <Category>[spendingCategory('Groceries')],
        categorySpendByMonth: <String, Map<String, int>>{
          '2026-04': <String, int>{'Groceries': 600000},
        },
      );

      expect(snapshot.suggestedLimits(), isEmpty);
    });

    test('refuses to be asked for less history than the minimum', () {
      expect(historyFixture().suggestedLimits(months: 3), isEmpty);
      expect(historyFixture().suggestedLimits(months: 0), isEmpty);
    });

    test('an empty ledger suggests nothing at all', () {
      expect(snapshotWith().suggestedLimits(), isEmpty);
    });
  });
}
