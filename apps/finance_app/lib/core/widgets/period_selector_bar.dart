import 'package:flutter/material.dart';

import '../../data/stats_period.dart';
import '../format/money.dart';

/// The period lengths the overview can show, as a single-select row.
///
/// Defaults to the four the overview offers. Reports passes its own list, which
/// adds a single day and a custom range — the two lengths that make a report
/// rather than a glance, and that the dashboard has no room for.
class PeriodChips extends StatelessWidget {
  const PeriodChips({
    required this.period,
    required this.onChanged,
    this.periods = overviewPeriods,
    super.key,
  });

  final StatsPeriod period;
  final ValueChanged<StatsPeriod> onChanged;

  /// The lengths to offer, in order.
  final List<StatsPeriod> periods;

  /// What the overview shows: week through year, never a single day.
  static const List<StatsPeriod> overviewPeriods = <StatsPeriod>[
    StatsPeriod.week,
    StatsPeriod.month,
    StatsPeriod.quarter,
    StatsPeriod.year,
  ];

  /// Height the app bar reserves for this row.
  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: periods.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = periods[index];
          return Center(
            child: ChoiceChip(
              label: Text(periodLabel(option)),
              selected: option == period,
              onSelected: (_) => onChanged(option),
            ),
          );
        },
      ),
    );
  }
}

/// The period being shown, with a step either way and a way back to now.
///
/// Stepping is bounded by the data rather than by the clock alone: back stops at
/// the period that still contains an entry, because wandering into periods with
/// nothing in them shows a screen of ₹0 that reads as lost data rather than absent
/// data. Forward stops at the period in progress, which is the newest that can
/// have anything in it.
class PeriodStepper extends StatelessWidget {
  const PeriodStepper({
    required this.range,
    required this.current,
    required this.earliest,
    required this.onChanged,
    super.key,
  });

  /// The period being shown.
  final StatsRange range;

  /// The period containing today.
  final StatsRange current;

  /// The earliest date with an entry, or null when the ledger is empty.
  final DateTime? earliest;

  final ValueChanged<StatsRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previous = range.step(-1);
    final earliestDay = earliest == null
        ? null
        : DateTime(earliest!.year, earliest!.month, earliest!.day);
    // A previous period is worth offering only while it still contains something:
    // its exclusive end must be after the first entry's date.
    final canGoBack = earliestDay != null && previous.to.isAfter(earliestDay);
    final canGoForward = !range.sameDatesAs(current);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: 'Previous ${periodLabel(range.period).toLowerCase()}',
          onPressed: canGoBack ? () => onChanged(previous) : null,
        ),
        Flexible(
          child: Text(
            rangeLabel(range),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: 'Next ${periodLabel(range.period).toLowerCase()}',
          onPressed: canGoForward ? () => onChanged(range.step(1)) : null,
        ),
        if (!range.sameDatesAs(current))
          TextButton(
            onPressed: () => onChanged(current),
            child: const Text('Now'),
          ),
      ],
    );
  }
}

/// How a period length is named in the selector: "Week", "Month", …
String periodLabel(StatsPeriod period) => switch (period) {
  StatsPeriod.day => 'Day',
  StatsPeriod.week => 'Week',
  StatsPeriod.month => 'Month',
  StatsPeriod.quarter => 'Quarter',
  StatsPeriod.year => 'Year',
  StatsPeriod.custom => 'Range',
};

/// How a period is named inside a sentence: "Spent this week", "vs last month".
String periodWord(StatsPeriod period) => switch (period) {
  StatsPeriod.day => 'day',
  StatsPeriod.week => 'week',
  StatsPeriod.month => 'month',
  StatsPeriod.quarter => 'quarter',
  StatsPeriod.year => 'year',
  StatsPeriod.custom => 'range',
};

/// The dates a period covers, in as few words as they fit in.
///
/// A day says itself, a week says which days it is — "7–13 Sep 2026" — because
/// "Week 37" answers a question nobody asked. A quarter says which months, and a
/// year says itself. A custom range names both ends, repeating the year only when
/// the span crosses one, because the second year is the only case where leaving it
/// out would be ambiguous.
String rangeLabel(StatsRange range) {
  final lastDay = range.to.subtract(const Duration(days: 1));
  switch (range.period) {
    case StatsPeriod.day:
      return '${range.from.day} ${DateLabels.shortMonth(range.from)} '
          '${range.from.year}';
    case StatsPeriod.week:
      if (lastDay.month == range.from.month) {
        return '${range.from.day}–${lastDay.day} '
            '${DateLabels.shortMonth(lastDay)} ${lastDay.year}';
      }
      return '${range.from.day} ${DateLabels.shortMonth(range.from)} – '
          '${lastDay.day} ${DateLabels.shortMonth(lastDay)} ${lastDay.year}';
    case StatsPeriod.month:
      return DateLabels.monthYear(range.from);
    case StatsPeriod.quarter:
      return '${DateLabels.shortMonth(range.from)}–'
          '${DateLabels.shortMonth(lastDay)} ${lastDay.year}';
    case StatsPeriod.year:
      return '${range.from.year}';
    case StatsPeriod.custom:
      final start = '${DateLabels.dayMonth(range.from)} ${range.from.year}';
      final end = range.from.year == lastDay.year
          ? DateLabels.dayMonth(lastDay)
          : '${DateLabels.dayMonth(lastDay)} ${lastDay.year}';
      return '$start – $end';
  }
}
