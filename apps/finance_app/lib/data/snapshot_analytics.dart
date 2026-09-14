import 'category_movement.dart';
import 'finance_snapshot.dart';
import 'snapshot_views.dart';

/// Comparisons against history.
///
/// Kept separate from [SnapshotViews] because these are the computations that
/// belong in a pure, well-tested analytics layer: they take numbers in and
/// return numbers out, with no widget or database dependency.
extension SnapshotAnalytics on FinanceSnapshot {
  /// Month-over-month change in total spend, as a percentage.
  ///
  /// The current month is partial, so the previous month is scaled to the same
  /// day-of-month before comparing. Comparing a part-month against a whole one
  /// would read as a large saving every single time, which is worse than
  /// showing nothing.
  double? get expenseChangePercent {
    final previous = previousMonth;
    if (previous == null || previous.expenseMinor == 0) {
      return null;
    }
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final scaled = previous.expenseMinor * (now.day / daysInMonth);
    if (scaled == 0) {
      return null;
    }
    return ((currentMonth.expenseMinor - scaled) / scaled) * 100;
  }

  /// Mean monthly spend per category across every month present.
  ///
  /// Comparing a month against the user's *own* history is what makes the
  /// figure meaningful. A fixed threshold would be arbitrary, and a peer
  /// comparison is neither available nor appropriate for private data.
  Map<String, double> get categoryMonthlyAverages {
    final totals = <String, int>{};
    for (final byCategory in categorySpendByMonth.values) {
      byCategory.forEach((category, amount) {
        totals.update(
          category,
          (value) => value + amount,
          ifAbsent: () => amount,
        );
      });
    }
    final months = categorySpendByMonth.isEmpty
        ? 1
        : categorySpendByMonth.length;
    return <String, double>{
      for (final entry in totals.entries) entry.key: entry.value / months,
    };
  }

  /// Movement of each category in [month] relative to its own average,
  /// largest increase first.
  ///
  /// Sorted by increase because the user's question is always "what got
  /// expensive", never "what got cheap".
  List<CategoryMovement> categoryMovement(DateTime month) {
    final averages = categoryMonthlyAverages;
    final movements = spendByCategory(month)
        .map(
          (spend) => CategoryMovement(
            category: spend.category,
            currentMinor: spend.totalMinor,
            averageMinor: (averages[spend.category] ?? 0).round(),
          ),
        )
        .toList();
    movements.sort(
      (a, b) => (b.deltaPercent ?? 0).compareTo(a.deltaPercent ?? 0),
    );
    return movements;
  }

  /// Savings rate as a percentage of income for the current month, or null when
  /// there was no income to save from.
  double? get currentSavingsRate => currentMonth.savingsRate;

  /// Savings rates for every month on record, oldest first.
  List<double> get savingsRateHistory => monthlySummaries
      .map((summary) => summary.savingsRate)
      .whereType<double>()
      .toList(growable: false);
}
