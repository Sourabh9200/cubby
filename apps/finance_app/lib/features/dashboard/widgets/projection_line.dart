import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/projection.dart';
import 'projection_sheet.dart';

/// One line under the pace chart: where the period lands if nothing changes.
///
/// Deliberately one line, with the working-out a tap away in a sheet. The
/// overview is period-scoped and already long, and a projection nobody reads is
/// worth less than one the user chose to open — so the figure is here and the
/// basis, the split and the daily allowance are one tap behind it.
class ProjectionLine extends StatelessWidget {
  const ProjectionLine({
    required this.projection,
    required this.budgetLimitMinor,
    required this.word,
    super.key,
  });

  final PeriodProjection projection;

  /// The limits that apply to this period: zero when none are set, or when the
  /// period covers no whole month (a week).
  final int budgetLimitMinor;

  /// How the period is named in a sentence: `month`, `quarter`, `year`.
  final String word;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final overshoots = projection.overshoots(budgetLimitMinor);

    return Row(
      children: <Widget>[
        Icon(
          overshoots ? Icons.trending_up_rounded : Icons.timeline_rounded,
          size: 16,
          color: overshoots
              ? money.warning
              : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'At this rate, '
            '${Money.format(projection.projectedTotalMinor, decimals: false)} '
            'this $word',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextButton(
          onPressed: () => showProjectionSheet(
            context,
            projection: projection,
            budgetLimitMinor: budgetLimitMinor,
            word: word,
          ),
          child: const Text('How'),
        ),
      ],
    );
  }
}
