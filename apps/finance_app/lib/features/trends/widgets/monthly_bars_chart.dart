import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models.dart';

/// Income, spending, and investing, grouped by month.
///
/// Grouped rather than stacked on purpose: stacking would make the series share
/// a baseline and hide the fact that they are different quantities. Seeing the
/// gap between the red and green bars *is* the insight — that gap is savings —
/// and the blue bar shows how much of it went into assets.
class MonthlyBarsChart extends StatelessWidget {
  const MonthlyBarsChart({
    required this.summaries,
    this.height = 180,
    super.key,
  });

  final List<MonthlySummary> summaries;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (summaries.isEmpty) {
      return SizedBox(height: height);
    }
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);

    final maxValue = summaries
        .map(
          (summary) => <int>[
            summary.expenseMinor,
            summary.incomeMinor,
            summary.investmentMinor,
          ].reduce((a, b) => a > b ? a : b),
        )
        .fold<int>(1, (a, b) => a > b ? a : b);
    final axisMax = maxValue / 100 * 1.15;

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: axisMax,
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: axisMax / 3,
            getDrawingHorizontalLine: (value) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= summaries.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateLabels.shortMonth(summaries[index].month),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final summary = summaries[group.x];
                // Named rather than abbreviated to In/Out: a third bar makes
                // "blue" ambiguous, and the tooltip is the one place the user
                // can confirm what they are looking at.
                final label = switch (rodIndex) {
                  0 => 'Spent',
                  1 => 'Received',
                  _ => 'Invested',
                };
                return BarTooltipItem(
                  '${DateLabels.shortMonth(summary.month)}\n'
                  '$label  ${Money.format((rod.toY * 100).round())}',
                  TextStyle(
                    color: theme.colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          barGroups: <BarChartGroupData>[
            for (var i = 0; i < summaries.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 2,
                barRods: <BarChartRodData>[
                  BarChartRodData(
                    toY: summaries[i].expenseMinor / 100,
                    color: money.expense,
                    width: 8,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                  BarChartRodData(
                    toY: summaries[i].incomeMinor / 100,
                    color: money.income,
                    width: 8,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                  BarChartRodData(
                    toY: summaries[i].investmentMinor / 100,
                    color: money.investment,
                    width: 8,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
