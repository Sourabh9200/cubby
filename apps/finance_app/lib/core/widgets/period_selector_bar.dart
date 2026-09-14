import 'package:flutter/material.dart';

import '../../data/stats_period.dart';
import '../format/money.dart';

/// The four period lengths the overview can show, as a single-select row.
class PeriodChips extends StatelessWidget {
  const PeriodChips({required this.period, required this.onChanged, super.key});

  final StatsPeriod period;
  final ValueChanged<StatsPeriod> onChanged;

  /// Height the app bar reserves for this row.
  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: StatsPeriod.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = StatsPeriod.values[index];
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
  StatsPeriod.week => 'Week',
  StatsPeriod.month => 'Month',
  StatsPeriod.quarter => 'Quarter',
  StatsPeriod.year => 'Year',
};

/// The dates a period covers, in as few words as they fit in.
///
/// A week says which days it is — "7–13 Sep 2026" — because "Week 37" answers a
/// question nobody asked. A quarter says which months, and a year says itself.
String rangeLabel(StatsRange range) {
  final lastDay = range.to.subtract(const Duration(days: 1));
  switch (range.period) {
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
  }
}
