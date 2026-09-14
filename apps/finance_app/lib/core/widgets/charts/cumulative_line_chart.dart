import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../format/money.dart';

/// Cumulative spend across the days of a month.
///
/// A cumulative curve answers the question a daily bar chart cannot: "am I
/// ahead of or behind my usual pace?" The slope at the right edge is the
/// current burn rate, which is what a forecast is built from.
class CumulativeSpendChart extends StatelessWidget {
  const CumulativeSpendChart({
    required this.cumulativeRupees,
    this.height = 160,
    super.key,
  });

  /// Index 0 is the origin; index N is the running total through day N.
  final List<double> cumulativeRupees;

  final double height;

  @override
  Widget build(BuildContext context) {
    if (cumulativeRupees.length < 2) {
      return SizedBox(height: height);
    }
    final theme = Theme.of(context);
    final maxY = cumulativeRupees.last;
    // Round the axis up so the line never touches the top edge, which would
    // read as "off the chart".
    final axisMax = maxY == 0 ? 100.0 : maxY * 1.18;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (cumulativeRupees.length - 1).toDouble(),
          minY: 0,
          maxY: axisMax,
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
                interval: (cumulativeRupees.length / 4).ceilToDouble(),
                getTitlesWidget: (value, meta) {
                  final day = value.round();
                  if (day <= 0 || day >= cumulativeRupees.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '$day',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map(
                    (spot) => LineTooltipItem(
                      'Day ${spot.x.round()}\n${Money.format((spot.y * 100).round())}',
                      TextStyle(
                        color: theme.colorScheme.onInverseSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          lineBarsData: <LineChartBarData>[
            LineChartBarData(
              spots: <FlSpot>[
                for (var day = 0; day < cumulativeRupees.length; day++)
                  FlSpot(day.toDouble(), cumulativeRupees[day]),
              ],
              isCurved: true,
              curveSmoothness: 0.22,
              preventCurveOverShooting: true,
              color: theme.colorScheme.primary,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    theme.colorScheme.primary.withValues(alpha: 0.28),
                    theme.colorScheme.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
