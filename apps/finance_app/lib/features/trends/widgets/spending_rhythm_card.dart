import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/charts/chart_bar.dart';
import '../../../core/widgets/indicators.dart';
import '../../../core/widgets/section_card.dart';
import '../../../data/spending_rhythm.dart';

/// Which days of the week this ledger spends on, and how many days it says
/// nothing at all.
///
/// Every figure here is a statement about the ledger. A day with no entry is a
/// day *nothing was recorded*, which is not the same as a day nothing was spent:
/// cash does not pass through this app between deposits, and the wording says so
/// everywhere (C11).
class SpendingRhythmCard extends StatelessWidget {
  const SpendingRhythmCard({required this.rhythm, super.key});

  final SpendingRhythm rhythm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);

    if (!rhythm.hasData) {
      return const SectionCard(
        title: 'Rhythm',
        child: EmptyState(
          dense: true,
          icon: Icons.calendar_month_rounded,
          title: 'Nothing recorded yet',
          message:
              'Record a few expenses and the days of the week they fall on '
              'appear here.',
        ),
      );
    }

    final busiest = rhythm.busiest;

    return SectionCard(
      title: 'Rhythm',
      trailing: Pill(
        text: '${rhythm.recordedDays} days',
        color: theme.colorScheme.primary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: 'Busiest day',
                  value: busiest == null ? '—' : weekdayName(busiest.weekday),
                  icon: Icons.calendar_month_rounded,
                  deltaText: busiest == null
                      ? null
                      : '${Money.format(busiest.averageMinor)} on average',
                  deltaColor: money.neutral,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StatTile(
                  label: 'Average per active day',
                  value: Money.compact(rhythm.averagePerActiveDayMinor),
                  icon: Icons.today_rounded,
                  deltaText: '${rhythm.activeDays} days with entries',
                  deltaColor: money.neutral,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _WeekdayBars(byWeekday: rhythm.byWeekday),
          const SizedBox(height: 10),
          Text(
            '${rhythm.quietDays} of the ${rhythm.recordedDays} days so far have '
            'nothing recorded. A blank day means nothing was entered, not that '
            'nothing was spent — cash does not pass through this app between '
            'deposits.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The week's days, with the average spent on each.
class _WeekdayBars extends StatelessWidget {
  const _WeekdayBars({required this.byWeekday});

  final List<WeekdaySpend> byWeekday;

  /// Height of the bars themselves, not of the whole chart.
  ///
  /// The labels below take whatever height they need, so a narrow column or a
  /// larger text scale cannot overflow the chart: the reserve is exactly what a
  /// bar may use, and a bar is never taller than the reserve.
  static const double barHeight = 66;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);

    var maxAverage = 0;
    for (final day in byWeekday) {
      if (day.averageMinor > maxAverage) {
        maxAverage = day.averageMinor;
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (final day in byWeekday)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    height: barHeight,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: ChartBar(
                        // Two pixels for a day with nothing recorded: the column
                        // reads as "nothing here" rather than as a missing day.
                        height: maxAverage == 0 || day.averageMinor == 0
                            ? 2
                            : (day.averageMinor / maxAverage * barHeight).clamp(
                                4,
                                barHeight,
                              ),
                        color: day.averageMinor == 0
                            ? theme.colorScheme.surfaceContainerHighest
                            : money.expense.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      shortWeekday(day.weekday),
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
}

const List<String> _weekdayNames = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// How a weekday is named in a sentence.
String weekdayName(int weekday) => _weekdayNames[weekday - DateTime.monday];

/// The three-letter form, for a chart axis.
String shortWeekday(int weekday) => weekdayName(weekday).substring(0, 3);
