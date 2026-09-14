import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/indicators.dart';
import '../../../core/widgets/section_card.dart';
import '../../../data/models.dart';

/// Savings rate over the months on record.
///
/// Shown as a per-month bar strip rather than a single number, because the
/// spread is the information: a steady 30% and an alternation between 60% and
/// 0% average out the same and mean very different things.
class SavingsRateCard extends StatelessWidget {
  const SavingsRateCard({required this.summaries, super.key});

  final List<MonthlySummary> summaries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final rates = <double>[];
    for (final summary in summaries) {
      final rate = summary.savingsRate;
      if (rate != null) {
        rates.add(rate);
      }
    }
    if (rates.isEmpty) {
      return const SizedBox.shrink();
    }
    final latest = rates.last;
    final average = rates.reduce((a, b) => a + b) / rates.length;
    final difference = latest - average;

    return SectionCard(
      title: 'Savings rate',
      trailing: Pill(
        text: '${rates.length} months',
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
                  label: 'This month',
                  value: '${latest.toStringAsFixed(1)}%',
                  icon: Icons.savings_rounded,
                  deltaText:
                      '${difference >= 0 ? '+' : ''}'
                      '${difference.toStringAsFixed(1)} pts vs average',
                  deltaColor: difference >= 0 ? money.income : money.expense,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StatTile(
                  label: 'Average',
                  value: '${average.toStringAsFixed(1)}%',
                  icon: Icons.insights_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (final rate in rates)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Container(
                        // Clamped so a single outlier month cannot squash every
                        // other bar into invisibility.
                        height: rate.abs().clamp(2, 60) * 1.15,
                        decoration: BoxDecoration(
                          color: (rate >= 0 ? money.income : money.expense)
                              .withValues(alpha: 0.8),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Share of income kept each month, oldest on the left. Green is a '
            'surplus; a red bar means that month spent more than it earned.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
