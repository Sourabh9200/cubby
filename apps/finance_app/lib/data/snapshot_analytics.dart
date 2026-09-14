import 'category_movement.dart';
import 'finance_snapshot.dart';
import 'models.dart';
import 'monthly_extremes.dart';
import 'period_views.dart';
import 'snapshot_views.dart';
import 'stats_period.dart';

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
  double? get expenseChangePercent => expenseChangeFor(currentMonth.month);

  /// Month-over-month change in total spend for [month].
  ///
  /// An adapter onto [PeriodViews.expenseChangeForRange], so a weekly comparison
  /// and a monthly one are the same arithmetic. A month that is over is compared
  /// whole against the month before it — scaling there would invent a figure that
  /// never happened. Only the month in progress is scaled, because only it is
  /// incomplete.
  double? expenseChangeFor(DateTime month) =>
      expenseChangeForRange(StatsRange.containing(StatsPeriod.month, month));

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

  /// Highest and lowest month on record for each of the three measures, plus
  /// the average over the months that recorded each one.
  ///
  /// Months with nothing recorded for a measure are skipped rather than counted
  /// as zero. A month in which nothing was invested is not "the month you
  /// invested least" — it is a month with no investing in it at all — and
  /// counting it would report every user's worst investing month as whichever
  /// month they happened to skip a contribution. The same reasoning makes the
  /// average a mean over recording months.
  List<MetricExtremes> get monthlyExtremes => <MetricExtremes>[
    _extremesFor(MetricMeasure.expense, (summary) => summary.expenseMinor),
    _extremesFor(MetricMeasure.income, (summary) => summary.incomeMinor),
    _extremesFor(
      MetricMeasure.investment,
      (summary) => summary.investmentMinor,
    ),
  ];

  MetricExtremes _extremesFor(
    MetricMeasure measure,
    int Function(MonthlySummary) read,
  ) {
    MonthPeak? highest;
    MonthPeak? lowest;
    var total = 0;
    var months = 0;
    for (final summary in monthlySummaries) {
      final value = read(summary);
      if (value <= 0) {
        continue;
      }
      total += value;
      months++;
      if (highest == null || value > highest.totalMinor) {
        highest = MonthPeak(month: summary.month, totalMinor: value);
      }
      if (lowest == null || value < lowest.totalMinor) {
        lowest = MonthPeak(month: summary.month, totalMinor: value);
      }
    }
    return MetricExtremes(
      measure: measure,
      highest: highest,
      lowest: lowest,
      // Integer division, because money in this app never becomes a double.
      averageMinor: months == 0 ? 0 : total ~/ months,
    );
  }

  /// Savings rates for every month on record, oldest first.
  List<double> get savingsRateHistory => monthlySummaries
      .map((summary) => summary.savingsRate)
      .whereType<double>()
      .toList(growable: false);
}
