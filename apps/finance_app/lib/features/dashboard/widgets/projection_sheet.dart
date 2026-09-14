import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/projection.dart';

/// Opens the working-out behind the pace card's projection line.
Future<void> showProjectionSheet(
  BuildContext context, {
  required PeriodProjection projection,
  required int budgetLimitMinor,
  required String word,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ProjectionSheet(
      projection: projection,
      budgetLimitMinor: budgetLimitMinor,
      word: word,
    ),
  );
}

/// What the projection is made of, and what it means for the rest of the period.
///
/// The doc's rule is that a projection must show its basis (C5), so this sheet
/// exists rather than the figure carrying any authority of its own: it names how
/// many months and recorded days the rate came from, how many rules are still to
/// post, and what each remaining day may spend.
class ProjectionSheet extends StatelessWidget {
  const ProjectionSheet({
    required this.projection,
    required this.budgetLimitMinor,
    required this.word,
    super.key,
  });

  final PeriodProjection projection;
  final int budgetLimitMinor;
  final String word;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final safePerDay = projection.safePerDayMinor(budgetLimitMinor);
    final overshoots = projection.overshoots(budgetLimitMinor);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Where this $word is heading',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Text(
              Money.format(projection.projectedTotalMinor, decimals: false),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'if the rest of the $word looks like the months behind it',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            _DetailRow(
              label: 'Spent so far',
              value: Money.format(projection.spentMinor, decimals: false),
            ),
            _DetailRow(
              label: projection.ruleCount == 1
                  ? 'Still to post · 1 rule'
                  : 'Still to post · ${projection.ruleCount} rules',
              value: Money.format(projection.committedMinor, decimals: false),
            ),
            _DetailRow(
              label:
                  'Expected · ${Money.format(projection.dailyRateMinor)} a day '
                  '× ${projection.daysRemaining} days',
              value: Money.format(
                projection.projectedVariableMinor,
                decimals: false,
              ),
            ),
            const SizedBox(height: 16),
            if (budgetLimitMinor > 0) ...<Widget>[
              Text(
                overshoots
                    ? 'This pace lands '
                          '${Money.format(projection.projectedTotalMinor - budgetLimitMinor, decimals: false)} '
                          'past your '
                          '${Money.format(budgetLimitMinor, decimals: false)} '
                          'of limits.'
                    : '${Money.format(safePerDay)} a day for the remaining '
                          '${projection.daysRemaining} days keeps you inside '
                          'your '
                          '${Money.format(budgetLimitMinor, decimals: false)} '
                          'of limits.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: overshoots ? money.warning : money.income,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              _basis(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A projection of what you have recorded, never a promise. It '
              'cannot see a bill nobody has recorded yet, and cash does not pass '
              'through this app between deposits — so a run of quiet days here '
              'can mean unrecorded spending rather than a frugal one.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// How many months, days and rules the figure is built from.
  String _basis() {
    final months = projection.monthsOfHistory;
    if (months == 0) {
      return 'No complete month of history yet, so this counts only what is '
          'already recorded and what is still to post.';
    }
    final monthWord = months == 1 ? 'month' : 'months';
    final dayWord = projection.recordedDays == 1 ? 'day' : 'days';
    return 'From $months $monthWord of history, '
        '${projection.recordedDays} $dayWord with entries, and a typical '
        'recorded day of ${Money.format(projection.activeDayMedianMinor)}.';
  }
}

/// One line of the working-out: what it is, and how much.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
