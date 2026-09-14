import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/indicators.dart';
import '../../core/widgets/section_card.dart';
import '../../data/models.dart';
import '../../data/repository_scope.dart';
import '../../data/snapshot_views.dart';
import 'widgets/budget_category_tile.dart';
import 'widgets/budget_editor_sheet.dart';
import 'widgets/category_editor_sheet.dart';

/// Every category with its monthly figure, editable in place.
///
/// Lists *all* categories rather than only the ones with activity, because the
/// whole point is to set a budget on a category that does not have one yet. The
/// dashboard's card only shows categories that already have a figure, so without
/// this screen a category could never acquire one.
///
/// Split by kind, because the three kinds answer different questions: a spending
/// limit is a ceiling, an investing target is a floor, and income has no figure
/// at all. One undifferentiated list would invite the user to read a ceiling and
/// a floor as the same kind of number.
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final snapshot = RepositoryScope.of(context);
    final spending = snapshot.expenseCategories;
    final investing = snapshot.investmentCategories;
    final income = snapshot.incomeCategories;
    final spend = <String, int>{
      for (final entry in snapshot.spendByCategory(snapshot.now))
        entry.category: entry.totalMinor,
    };
    final invested = <String, int>{
      for (final entry in snapshot.investedByCategory(snapshot.now))
        entry.category: entry.totalMinor,
    };

    final budgeted = spending.fold(0, (sum, c) => sum + c.budgetMinor);
    final spentAgainstBudgets = spending
        .where((category) => category.budgetMinor > 0)
        .fold(0, (sum, category) => sum + (spend[category.name] ?? 0));
    final remaining = budgeted - spentAgainstBudgets;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories & budgets'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add a category',
            onPressed: () => showCategoryEditor(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: <Widget>[
          SectionCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: StatTile(
                    label: 'Budgeted',
                    value: Money.format(budgeted, decimals: false),
                    icon: Icons.savings_outlined,
                  ),
                ),
                Container(
                  width: 1,
                  height: 54,
                  color: theme.colorScheme.outlineVariant,
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 2,
                  child: StatTile(
                    label: remaining >= 0 ? 'Left' : 'Over',
                    value: Money.format(remaining.abs(), decimals: false),
                    icon: remaining >= 0
                        ? Icons.check_circle_outline_rounded
                        : Icons.warning_amber_rounded,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Spending limits',
            trailing: Text(
              '${spending.length} categories',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            child: Column(
              children: <Widget>[
                for (final category in spending)
                  BudgetCategoryTile(
                    category: category,
                    spentMinor: spend[category.name] ?? 0,
                    onTap: () => editBudget(
                      context,
                      category: category,
                      spentMinor: spend[category.name] ?? 0,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Investing targets',
            trailing: Text(
              '${investing.length} categories',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            child: Column(
              children: <Widget>[
                for (final category in investing)
                  BudgetCategoryTile(
                    category: category,
                    spentMinor: invested[category.name] ?? 0,
                    onTap: () => editBudget(
                      context,
                      category: category,
                      spentMinor: invested[category.name] ?? 0,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Income',
            trailing: Text(
              '${income.length} category',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            child: Column(
              children: <Widget>[
                for (final category in income)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CategoryAvatar(category: category.name, size: 38),
                    title: Text(category.name),
                    subtitle: const Text('No budget is set on income'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Spending limits repeat every month. An investing target is the '
            'opposite of a limit — you set it to reach it. Tap any category to '
            'change or clear its figure.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (spentAgainstBudgets > budgeted)
            Row(
              children: <Widget>[
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: money.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You are over your combined budget this month.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: money.warning,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Opens the budget editor for [category].
///
/// A plain function so both this screen and the dashboard's budget card can call
/// it without duplicating the sheet wiring.
Future<void> editBudget(
  BuildContext context, {
  required Category category,
  required int spentMinor,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BudgetEditorSheet(
      categoryId: category.id,
      categoryName: category.name,
      currentBudgetMinor: category.budgetMinor,
      spentMinor: spentMinor,
    ),
  );
}
