import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Category icon inside a tinted circle.
///
/// The tint is derived from the category name via [CategoryPalette], so a
/// category keeps the same colour on the dashboard, in the ledger, and in the
/// donut chart without any central registration step.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({required this.category, this.size = 42, super.key});

  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = CategoryPalette.forLabel(context, category);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(iconFor(category), size: size * 0.5, color: color),
    );
  }

  /// Maps a category name to an icon.
  static IconData iconFor(String category) => switch (category) {
    'Income' => Icons.south_west_rounded,
    'Rent' => Icons.home_rounded,
    'Groceries' => Icons.shopping_basket_rounded,
    'Dining Out' => Icons.restaurant_rounded,
    'Shopping' => Icons.shopping_bag_rounded,
    'Transport' => Icons.local_taxi_rounded,
    'Utilities' => Icons.bolt_rounded,
    'Health' => Icons.favorite_rounded,
    'Entertainment' => Icons.movie_rounded,
    'Education' => Icons.school_rounded,
    'Investments' => Icons.trending_up_rounded,
    'Mutual Funds' => Icons.savings_rounded,
    'Stocks' => Icons.show_chart_rounded,
    'Fixed Deposit' => Icons.account_balance_rounded,
    'Other' => Icons.category_rounded,
    _ => Icons.more_horiz_rounded,
  };
}

/// A thin labelled progress bar, used for budgets and investing targets.
class BudgetBar extends StatelessWidget {
  const BudgetBar({
    required this.fraction,
    this.overBudget = false,
    this.color,
    super.key,
  });

  final double fraction;
  final bool overBudget;

  /// Overrides the derived colour.
  ///
  /// Needed because exceeding a figure is not always bad: a met investing target
  /// should read as an achievement in the income colour, not as the red the
  /// spending-limit logic would pick.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final money = MoneyColors.of(context);
    final theme = Theme.of(context);
    final resolved =
        color ??
        (overBudget
            ? money.expense
            : (fraction > 0.85 ? money.warning : theme.colorScheme.primary));
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: fraction.clamp(0.0, 1.0),
        minHeight: 7,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(resolved),
      ),
    );
  }
}

/// Small pill used for deltas and status tags.
class Pill extends StatelessWidget {
  const Pill({required this.text, required this.color, this.icon, super.key});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// A colour swatch with a label, for chart legends.
///
/// Shared rather than re-declared per chart so every legend in the app reads the
/// same: the swatch size, radius and gap are decided once.
class LegendDot extends StatelessWidget {
  const LegendDot({required this.color, required this.label, super.key});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

/// Empty-state placeholder so no screen ever renders as a blank void.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.dense = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  /// Compact layout for use inside a fixed-height box, such as a chart slot.
  /// Without it the full-size block overflows a 180px chart area.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(dense ? 12 : 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: dense ? 28 : 48, color: theme.colorScheme.outline),
            SizedBox(height: dense ? 8 : 16),
            Text(
              title,
              style: dense
                  ? theme.textTheme.labelLarge
                  : theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: dense ? 4 : 8),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: dense ? 2 : null,
              overflow: dense ? TextOverflow.ellipsis : null,
              style:
                  (dense
                          ? theme.textTheme.bodySmall
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
