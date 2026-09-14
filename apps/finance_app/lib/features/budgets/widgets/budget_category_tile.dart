import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/indicators.dart';
import '../../../data/models.dart';

/// One category's budget row, tappable to edit.
class BudgetCategoryTile extends StatelessWidget {
  const BudgetCategoryTile({
    required this.category,
    required this.spentMinor,
    required this.onTap,
    super.key,
  });

  final Category category;
  final int spentMinor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final budget = category.budgetMinor;
    final hasBudget = budget > 0;
    // An investing category is funded toward a target, not limited against a
    // ceiling, so every label reads the other way round.
    final isTarget = category.isInvestment;
    final over = hasBudget && spentMinor > budget;

    final unit = isTarget ? 'target' : 'budget';
    final verb = isTarget ? 'invested' : 'spent';

    final subtitle = hasBudget
        ? '${Money.format(spentMinor, decimals: false)} of '
              '${Money.format(budget, decimals: false)}'
        : spentMinor > 0
        ? '${Money.format(spentMinor, decimals: false)} $verb · no $unit set'
        : 'No $unit set';

    final footer = isTarget
        ? (over
              ? 'Target met · '
                    '${Money.format(spentMinor - budget, decimals: false)} over'
              : '${Money.format(budget - spentMinor, decimals: false)} to go '
                    'this month')
        : (over
              ? 'Over by ${Money.format(spentMinor - budget, decimals: false)}'
              : '${Money.format(budget - spentMinor, decimals: false)} left '
                    'this month');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                CategoryAvatar(category: category.name, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        category.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            if (hasBudget) ...<Widget>[
              const SizedBox(height: 10),
              BudgetBar(
                fraction: spentMinor / budget,
                // Beating a target is not an overrun.
                overBudget: over && !isTarget,
                color: isTarget && over ? money.income : null,
              ),
              const SizedBox(height: 6),
              Text(
                footer,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isTarget && over
                      ? money.income
                      : over
                      ? money.expense
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: over ? FontWeight.w700 : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
