import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/charts/cumulative_line_chart.dart';
import '../../core/widgets/indicators.dart';
import '../../core/widgets/section_card.dart';
import '../../data/snapshot_analytics.dart';
import '../../data/snapshot_views.dart';
import '../../data/repository_scope.dart';
import '../budgets/budgets_screen.dart';
import 'widgets/biggest_hits_card.dart';
import 'widgets/budget_row.dart';
import 'widgets/category_donut.dart';

/// Month-at-a-glance screen.
///
/// Ordering is deliberate: the total and its direction first, then the pace
/// (cumulative curve), then composition (donut), then what needs attention
/// (budgets), then the outliers that aggregates hide.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = RepositoryScope.of(context);
    final month = repository.currentMonth;
    final change = repository.expenseChangePercent;
    final money = MoneyColors.of(context);
    final theme = Theme.of(context);
    final budgets = repository.budgetStatuses();
    final investedTotal = month.investmentMinor;
    final investedRate = month.investmentRate;
    final investingTargets = repository.investmentTargets();

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          title: Text(DateLabels.monthYear(month.month)),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded),
              tooltip: 'Budget alerts',
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Budget alerts arrive in a later step.'),
                ),
              ),
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          sliver: SliverList.list(
            children: <Widget>[
              SectionCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: StatTile(
                        label: 'Spent this month',
                        value: Money.format(
                          month.expenseMinor,
                          decimals: false,
                        ),
                        icon: Icons.trending_down_rounded,
                        deltaText: change == null
                            ? null
                            : '${change.abs().toStringAsFixed(1)}% vs last month',
                        deltaColor: change == null
                            ? null
                            : (change > 0 ? money.expense : money.income),
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
                        label: 'Income',
                        value: Money.compact(month.incomeMinor),
                        icon: Icons.south_west_rounded,
                        deltaText: 'Net ${Money.compact(month.netMinor)}',
                        deltaColor: month.netMinor >= 0
                            ? money.income
                            : money.expense,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Spending pace',
                trailing: Pill(
                  text: 'Day ${repository.now.day}',
                  color: theme.colorScheme.primary,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    CumulativeSpendChart(
                      cumulativeRupees: repository.cumulativeDailySpend(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A steepening slope means you are spending faster than '
                      'earlier in the month.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Where it went',
                child: CategoryDonut(
                  spends: repository.spendByCategory(month.month),
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Invested this month',
                trailing: investingTargets.isEmpty
                    ? null
                    : TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const BudgetsScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        label: const Text('Targets'),
                      ),
                child: investedTotal == 0 && investingTargets.isEmpty
                    ? const EmptyState(
                        dense: true,
                        icon: Icons.savings_outlined,
                        title: 'Nothing invested yet',
                        message:
                            'Record a contribution against an investing '
                            'category and it is tracked here rather than '
                            'counted as spending.',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: StatTile(
                                  label: 'Invested',
                                  value: Money.format(
                                    investedTotal,
                                    decimals: false,
                                  ),
                                  icon: Icons.trending_up_rounded,
                                  deltaText: investedRate == null
                                      ? null
                                      : '${investedRate.toStringAsFixed(0)}% '
                                            'of income',
                                  deltaColor: money.investment,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: StatTile(
                                  // Named for what it is. Calling this
                                  // "remaining" would invite the reading that
                                  // the invested money is gone, when it has
                                  // simply moved.
                                  label: 'Cash left',
                                  value: Money.compact(month.cashLeftMinor),
                                  icon: Icons.account_balance_wallet_outlined,
                                ),
                              ),
                            ],
                          ),
                          if (investingTargets.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 18),
                            for (final target in investingTargets.take(3))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: BudgetRow(
                                  budget: target,
                                  onTap: () {
                                    final category = repository.categoryNamed(
                                      target.category,
                                    );
                                    if (category != null) {
                                      editBudget(
                                        context,
                                        category: category,
                                        spentMinor: target.spentMinor,
                                      );
                                    }
                                  },
                                ),
                              ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Budgets',
                trailing: TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BudgetsScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Manage'),
                ),
                child: budgets.isEmpty
                    ? const EmptyState(
                        dense: true,
                        icon: Icons.savings_outlined,
                        title: 'No budgets yet',
                        message:
                            'Tap Manage to set a monthly limit on a '
                            'category.',
                      )
                    : Column(
                        children: <Widget>[
                          for (final budget in budgets.take(5))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: BudgetRow(
                                budget: budget,
                                onTap: () {
                                  final category = repository.categoryNamed(
                                    budget.category,
                                  );
                                  if (category != null) {
                                    editBudget(
                                      context,
                                      category: category,
                                      spentMinor: budget.spentMinor,
                                    );
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Biggest hits',
                child: BiggestHitsCard(transactions: repository.topExpenses()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
