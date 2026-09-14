import 'package:flutter/foundation.dart';

import 'models.dart';
import 'stats_period.dart';

/// One range against an earlier one, for all three measures.
///
/// Two comparisons in the app are built on this: the year-over-year card, where
/// the earlier range is the same window a year before — the only comparison that
/// strips out season — and a report's "against the previous period" section,
/// where it is the same span immediately before. One type means the two cannot
/// scale or subtract differently.
///
/// The measures stay apart rather than being folded into a single "change"
/// figure: a delta that mixed consumption with investing would move for a reason
/// the user cannot act on (C1), and income is lumpy enough that a combined line
/// would mostly report the lumpiness (C15).
@immutable
class PeriodComparison {
  const PeriodComparison({
    required this.range,
    required this.current,
    required this.previous,
    required this.previousScale,
  });

  /// The range on screen.
  final StatsRange range;

  /// Totals for [range].
  final PeriodTotals current;

  /// Totals for the earlier range, before any scaling.
  final PeriodTotals previous;

  /// What [previous] is multiplied by before comparing: 1 for a range that is
  /// over, the elapsed fraction for one still in progress.
  ///
  /// Without it, thirteen days of August compared against the whole of last
  /// August would read as a saving every single time (C6).
  final double previousScale;

  /// The earlier range's expense over the same part of it.
  int get comparableExpenseMinor =>
      (previous.expenseMinor * previousScale).round();

  /// The earlier range's income over the same part of it.
  int get comparableIncomeMinor =>
      (previous.incomeMinor * previousScale).round();

  /// The earlier range's investing over the same part of it.
  int get comparableInvestmentMinor =>
      (previous.investmentMinor * previousScale).round();

  /// Change in spend, as a percentage, or null when there is nothing to compare
  /// against.
  double? get expenseChangePercent =>
      _percentChange(current.expenseMinor, comparableExpenseMinor);

  /// Change in income, as a percentage, or null.
  double? get incomeChangePercent =>
      _percentChange(current.incomeMinor, comparableIncomeMinor);

  /// Change in investing, as a percentage, or null.
  double? get investmentChangePercent =>
      _percentChange(current.investmentMinor, comparableInvestmentMinor);

  /// Percentage change, or null when the earlier figure is zero and the change
  /// is therefore undefined rather than infinite.
  static double? _percentChange(int current, int previous) =>
      previous == 0 ? null : (current - previous) / previous * 100;
}
