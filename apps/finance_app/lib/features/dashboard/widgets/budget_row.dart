import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/indicators.dart';
import '../../../data/models.dart';

/// One budget: spent vs limit, with a bar and a plain-language status.
class BudgetRow extends StatelessWidget {
  const BudgetRow({required this.budget, this.onTap, super.key});

  final BudgetStatus budget;

  /// Opens the budget editor. Optional so the row still renders in a read-only
  /// context.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final percent = (budget.fraction * 100).clamp(0, 999).toStringAsFixed(0);

    // A target reads the opposite way round from a limit: overshooting an
    // investing goal is the achievement, while overshooting a spending limit is
    // the problem. Rendering "Over by ₹5,000" in red beside a mutual fund the
    // user deliberately funded would be actively misleading.
    final isTarget = budget.isInvestmentTarget;
    final isOver = budget.isOver;
    final overMinor = Money.format(
      budget.remainingMinor.abs(),
      decimals: false,
    );

    final statusText = isTarget
        ? (isOver ? 'Target met · $overMinor over' : '$percent% funded')
        : (isOver ? 'Over by $overMinor' : '$percent% used');

    final remainingText = isOver
        ? null
        : isTarget
        ? '${Money.format(budget.remainingMinor, decimals: false)} to go'
        : '${Money.format(budget.remainingMinor, decimals: false)} left';

    final statusColor = isTarget
        ? (isOver ? money.income : theme.colorScheme.onSurfaceVariant)
        : (isOver ? money.expense : theme.colorScheme.onSurfaceVariant);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                budget.category,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              '${Money.compact(budget.spentMinor)} / '
              '${Money.compact(budget.budgetMinor)}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onTap != null) ...<Widget>[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
        const SizedBox(height: 7),
        BudgetBar(
          fraction: budget.fraction,
          // Exceeding a target is not an overrun, so it never takes the
          // over-budget path — it is coloured as an achievement instead.
          overBudget: isOver && !isTarget,
          color: isTarget && isOver ? money.income : null,
        ),
        const SizedBox(height: 5),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                statusText,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: statusColor,
                  fontWeight: isOver && !isTarget ? FontWeight.w700 : null,
                ),
              ),
            ),
            if (remainingText != null)
              Text(
                remainingText,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );

    if (onTap == null) {
      return content;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: content,
    );
  }
}
