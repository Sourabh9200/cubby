import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/section_card.dart';
import '../../data/net_worth.dart';
import '../../data/period_views.dart';
import '../../data/repository_scope.dart';
import '../../data/stats_period.dart';

/// What the user owns less what they owe, over the last year.
///
/// A screen of its own rather than a card, because it is the one figure in this
/// app that cannot be fully honest: investments are counted at *cost*, and that
/// caveat has to be read rather than tucked under a chart (C3). The app has no
/// price feed by design, so a market value would be a stale guess — this is what
/// was paid, which is a figure the ledger can support.
class NetWorthScreen extends StatelessWidget {
  const NetWorthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final snapshot = RepositoryScope.of(context);
    final points = snapshot.netWorthSeries(
      StatsRange.containing(StatsPeriod.year, snapshot.now),
    );
    final today = snapshot.currentNetWorth;

    return Scaffold(
      appBar: AppBar(title: const Text('Net worth')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: <Widget>[
          SectionCard(
            child: StatTile(
              label: 'Net worth, at cost',
              value: Money.format(today.netWorthMinor, decimals: false),
              icon: Icons.account_balance_wallet_outlined,
              deltaText: today.netWorthMinor >= 0
                  ? 'Everything you own, less what you owe'
                  : 'More owed than owned',
              deltaColor: today.netWorthMinor >= 0
                  ? money.income
                  : money.expense,
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Month by month',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _NetWorthChart(points: points),
                const SizedBox(height: 12),
                _ComponentRow(
                  label: 'Bank, cash and wallet',
                  value: today.liquidMinor,
                ),
                _ComponentRow(
                  label: 'Cards, money owed',
                  value: today.cardMinor,
                ),
                _ComponentRow(
                  label: 'Investments, at cost',
                  value: today.investedMinor,
                  color: money.investment,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Investments are counted at what you paid for them, and this app has '
            'no price feed by design — a market value would be a guess that goes '
            'stale between reads. So a fall here means money was spent or a card '
            'was used, never that a fund lost value.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The line itself: one point per month end.
class _NetWorthChart extends StatelessWidget {
  const _NetWorthChart({required this.points});

  final List<NetWorthPoint> points;

  /// Height of the chart, axis labels included.
  static const double height = 180;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (points.length < 2) {
      // A line through one point is a dot, and a dot says nothing about a trend.
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'One month so far — the line needs two.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final values = <double>[
      for (final point in points) point.netWorthMinor / 100,
    ];
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final minY = values.reduce((a, b) => a < b ? a : b);
    // A line that touches an edge reads as "off the chart", so the axis keeps a
    // little room either side of the range.
    final span = (maxY - minY).abs();
    final padding = span == 0 ? maxY.abs() * 0.2 + 100 : span * 0.16;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          minY: minY - padding,
          maxY: maxY + padding,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
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
                // Every month would be a smear of overlapping labels on a phone,
                // so about four of them identify the axis.
                interval: (points.length / 4).ceilToDouble(),
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateLabels.shortMonth(points[index].month),
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
                      '${DateLabels.monthYear(points[spot.x.round()].month)}\n'
                      '${Money.format((spot.y * 100).round(), decimals: false)}',
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
                for (var index = 0; index < values.length; index++)
                  FlSpot(index.toDouble(), values[index]),
              ],
              isCurved: false,
              color: theme.colorScheme.primary,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    theme.colorScheme.primary.withValues(alpha: 0.24),
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

/// One part of the total, so the headline can be taken apart.
class _ComponentRow extends StatelessWidget {
  const _ComponentRow({required this.label, required this.value, this.color});

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            Money.format(value, decimals: false),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
