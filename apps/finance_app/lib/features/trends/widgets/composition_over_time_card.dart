import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/charts/chart_bar.dart';
import '../../../core/widgets/indicators.dart';
import '../../../core/widgets/section_card.dart';
import '../../../data/composition.dart';

/// The same three measures as stacked columns, one column per month.
///
/// The grouped bars above answer "what came in and what went out". This answers
/// what a grouped chart cannot: of what came in, how much was consumed, how much
/// was put away, and how much simply stayed. Watching the middle band thicken
/// across the year is the difference between investing that is growing and
/// investing that is merely present.
class CompositionOverTimeCard extends StatelessWidget {
  const CompositionOverTimeCard({required this.points, super.key});

  /// One point per month, oldest first, from
  /// `PeriodViews.compositionByMonthIn`.
  final List<CompositionPoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);

    if (points.isEmpty) {
      return const SectionCard(
        title: 'Composition by month',
        child: EmptyState(
          dense: true,
          icon: Icons.stacked_bar_chart_rounded,
          title: 'No months to show',
          message: 'Record income or spending and each month gets a column.',
        ),
      );
    }

    final anyOverdrawn = points.any((point) => point.totals.isOverdrawn);
    final anyPartial = points.any((point) => point.isPartial);

    return SectionCard(
      title: 'Composition by month',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: <Widget>[
              LegendDot(color: money.expense, label: 'Spent'),
              LegendDot(color: money.investment, label: 'Invested'),
              LegendDot(color: money.neutral, label: 'Unallocated'),
              if (anyOverdrawn)
                LegendDot(color: money.warning, label: 'Over income'),
            ],
          ),
          const SizedBox(height: 16),
          _StackedColumns(points: points),
          const SizedBox(height: 10),
          Text(
            'Each column is one month split the same three ways as the '
            'overview: spent at the bottom, invested above it, and what was '
            'left on top.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (anyOverdrawn) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'An orange cap is a month that spent and invested more than it '
              'earned.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (anyPartial) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '* is the month in progress: its column is short because the '
              'month is not over, not because anything slowed down.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One stacked column per month, scaled against the tallest month.
class _StackedColumns extends StatelessWidget {
  const _StackedColumns({required this.points});

  final List<CompositionPoint> points;

  /// Height of the bars themselves, not of the whole chart.
  ///
  /// The month labels below take whatever height they need: twelve columns on a
  /// narrow phone leave about twenty dp each, three letters wrap at that width,
  /// and a wrapped label inside a fixed chart height is a 19-pixel overflow.
  static const double barHeight = 132;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);

    // The tallest month sets the scale: the stack is income when nothing was
    // overspent and the outflow when it was, so the taller of the two across
    // every month is the tallest column that will be drawn.
    var maxTotal = 0;
    for (final point in points) {
      final stack = _columnTotalOf(point.totals);
      if (stack > maxTotal) {
        maxTotal = stack;
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (final point in points)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    height: barHeight,
                    // Bottom-aligned, so every month's column grows up from the
                    // same baseline whatever its height.
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      // A partial month keeps its place in the timeline but is
                      // visibly not a whole one (C6).
                      child: Opacity(
                        opacity: point.isPartial ? 0.45 : 1,
                        child: _Stack(
                          point: point,
                          maxTotal: maxTotal,
                          money: money,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Scaled down rather than wrapped: an axis label never eats
                  // into the bars' height.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${DateLabels.shortMonth(point.month)}'
                      '${point.isPartial ? '*' : ''}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// What a month's column adds up to: its income when nothing was overspent,
  /// and its outflow when something was.
  static int _columnTotalOf(CompositionTotals totals) {
    final income = totals.incomeMinor;
    final outflow = totals.outflowMinor;
    return outflow > income ? outflow : income;
  }
}

/// One month's column, bottom band first.
class _Stack extends StatelessWidget {
  const _Stack({
    required this.point,
    required this.maxTotal,
    required this.money,
  });

  final CompositionPoint point;
  final int maxTotal;
  final MoneyColors money;

  @override
  Widget build(BuildContext context) {
    final totals = point.totals;
    final bands = <_Band>[
      _Band(totals.expenseMinor, money.expense),
      _Band(totals.investmentMinor, money.investment),
      if (totals.unallocatedMinor > 0)
        _Band(totals.unallocatedMinor, money.neutral),
      // A month that consumed more than it earned gets the excess drawn on top
      // in the warning colour, so its column is the outflow rather than a
      // pretend income.
      if (totals.unallocatedMinor < 0)
        _Band(-totals.unallocatedMinor, money.warning),
    ].where((band) => band.amountMinor > 0).toList(growable: false);

    if (bands.isEmpty) {
      // Two pixels for a month with nothing recorded, so a gap reads as a quiet
      // month rather than as a missing one.
      return ChartBar(height: 2, color: money.neutral);
    }

    final scale = _StackedColumns.barHeight / maxTotal;
    final column = _StackedColumns._columnTotalOf(totals) * scale;

    return SizedBox(
      width: double.infinity,
      height: column.clamp(2, _StackedColumns.barHeight),
      // The bands share the column's height by flex, so they always add up to
      // exactly it. Pixel arithmetic would overflow the column by a rounding
      // error, and a "minimum visible band" would overflow it on purpose.
      child: Column(
        verticalDirection: VerticalDirection.up,
        children: <Widget>[
          for (var index = 0; index < bands.length; index++)
            Expanded(
              flex: bands[index].amountMinor,
              child: SizedBox(
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: bands[index].color,
                    borderRadius: index == bands.length - 1
                        ? const BorderRadius.vertical(top: Radius.circular(3))
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One band of a column: an amount and the colour it reads in.
class _Band {
  const _Band(this.amountMinor, this.color);

  final int amountMinor;
  final Color color;
}
