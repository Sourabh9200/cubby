import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/indicators.dart';
import '../../../core/widgets/section_card.dart';
import '../../../data/monthly_extremes.dart';

/// The highest and lowest month on record for spending, income, and investing.
///
/// A trend chart answers "what is happening"; this answers "what has happened",
/// which is the other half of the question. "This month was expensive" is far
/// less useful than "this is your worst month on record" — or "expensive, but
/// still well short of February".
class MonthlyRecordsCard extends StatelessWidget {
  const MonthlyRecordsCard({required this.extremes, super.key});

  final List<MetricExtremes> extremes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recorded = extremes.where((record) => record.hasData).toList();

    return SectionCard(
      title: 'Records',
      child: recorded.isEmpty
          ? const EmptyState(
              dense: true,
              icon: Icons.emoji_events_outlined,
              title: 'No records yet',
              message:
                  'Once entries exist in two months, the highest and lowest '
                  'of each measure appear here.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final record in recorded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: _MeasureRecord(record: record),
                  ),
                Text(
                  'Months with nothing recorded are left out rather than '
                  'counted as zero: a month with no investing in it is not the '
                  'month you invested least.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Highest, lowest, and average for one measure.
class _MeasureRecord extends StatelessWidget {
  const _MeasureRecord({required this.record});

  final MetricExtremes record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final (label, icon, color) = switch (record.measure) {
      MetricMeasure.expense => (
        'Spent',
        Icons.trending_down_rounded,
        money.expense,
      ),
      MetricMeasure.income => (
        'Received',
        Icons.south_west_rounded,
        money.income,
      ),
      MetricMeasure.investment => (
        'Invested',
        Icons.trending_up_rounded,
        money.investment,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              // A fixed salary makes every month identical, and an average that
              // equals every value is noise. Saying so is more honest than
              // printing the same number three times.
              record.isFlat
                  ? 'same every month'
                  : '${Money.compact(record.averageMinor)} a month',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _PeakRow(label: 'Highest', peak: record.highest!, valueColor: color),
        const SizedBox(height: 4),
        _PeakRow(
          label: 'Lowest',
          peak: record.lowest!,
          valueColor: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

/// One extreme: which month it was, and how much.
class _PeakRow extends StatelessWidget {
  const _PeakRow({
    required this.label,
    required this.peak,
    required this.valueColor,
  });

  final String label;
  final MonthPeak peak;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        SizedBox(
          width: 62,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            DateLabels.monthYear(peak.month),
            style: theme.textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          Money.format(peak.totalMinor, decimals: false),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
