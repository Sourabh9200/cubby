import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/charts/cumulative_line_chart.dart';
import '../../core/widgets/indicators.dart';
import '../../core/widgets/period_selector_bar.dart';
import '../../core/widgets/section_card.dart';
import '../../data/budget_pace.dart';
import '../../data/period_views.dart';
import '../../data/repository_scope.dart';
import '../../data/scheduled_views.dart';
import '../../data/snapshot_analytics.dart';
import '../../data/snapshot_views.dart';
import '../../data/stats_period.dart';
import '../../data/suggested_limit.dart';
import '../budgets/budgets_screen.dart';
import 'widgets/biggest_hits_card.dart';
import 'widgets/budget_row.dart';
import 'widgets/category_donut.dart';
import 'widgets/committed_spend_card.dart';
import 'widgets/composition_card.dart';
import 'widgets/projection_line.dart';

/// At-a-glance screen, for a week, a month, a quarter or a year.
///
/// Ordering is deliberate: the total and its direction first, then the pace
/// (cumulative curve), then composition (donut), then what needs attention
/// (budgets), then the outliers that aggregates hide.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// How much time is on screen. Monthly by default, because that is the unit a
  /// rent payment, a salary and every budget in the app are set in.
  StatsPeriod _period = StatsPeriod.month;

  /// Which instance of the period is on screen, or null while it is the one
  /// containing today.
  ///
  /// A date rather than an index: the whole app speaks in calendar dates, and an
  /// index would need re-deriving every time the period length changed.
  DateTime? _anchor;

  @override
  Widget build(BuildContext context) {
    final snapshot = RepositoryScope.of(context);
    final now = snapshot.now;
    final current = StatsRange.containing(_period, now);
    final range = StatsRange.containing(_period, _anchor ?? now);
    final totals = snapshot.totalsFor(range);
    final change = snapshot.expenseChangeForRange(range);
    final money = MoneyColors.of(context);
    final theme = Theme.of(context);
    final word = periodWord(range.period);
    final budgets = snapshot.budgetStatusesIn(range, includeUnlimited: true);
    final investedTotal = totals.investmentMinor;
    final investedRate = totals.investmentRate;
    final investingTargets = snapshot.investmentTargetsIn(range);
    // The projection is computed for every period and *shown* only where it has a
    // basis: a period that is over returns null, and a ledger with no history
    // behind it returns a figure with no basis, which is the app's way of saying
    // "not enough history" rather than inventing one (C5, C11).
    final projection = snapshot.projectionFor(range);
    final budgetLimit = snapshot.budgetLimitIn(range);
    // Where each limit is heading, by category name. Only the categories whose
    // pace is a problem say anything on screen; the rest keep the row they had.
    final paces = <String, BudgetPace>{
      for (final pace in snapshot.budgetPaceIn(range)) pace.category: pace,
    };
    final suggestions = <String, SuggestedLimit>{
      for (final suggestion in snapshot.suggestedLimits())
        suggestion.category: suggestion,
    };

    final earliest = snapshot.firstRecordedDay;

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          title: PeriodStepper(
            range: range,
            current: current,
            earliest: earliest,
            onChanged: (value) => setState(() => _anchor = value.from),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(PeriodChips.height),
            child: PeriodChips(
              period: _period,
              onChanged: (value) => setState(() {
                _period = value;
                // Changing the length lands on the period you are in, rather
                // than keeping an anchor that may not line up with the new kind.
                _anchor = null;
              }),
            ),
          ),
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
                        label: 'Spent this $word',
                        value: Money.format(
                          totals.expenseMinor,
                          decimals: false,
                        ),
                        icon: Icons.trending_down_rounded,
                        deltaText: change == null
                            ? null
                            : '${change.abs().toStringAsFixed(1)}% vs last '
                                  '$word',
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
                        value: Money.compact(totals.incomeMinor),
                        icon: Icons.south_west_rounded,
                        deltaText: 'Net ${Money.compact(totals.netMinor)}',
                        deltaColor: totals.netMinor >= 0
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
                  text: range.contains(now)
                      ? 'Day ${now.difference(range.from).inDays + 1}'
                      : 'Complete',
                  color: theme.colorScheme.primary,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    CumulativeSpendChart(
                      cumulativeRupees: snapshot.cumulativeSpendIn(range),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A steepening slope means you are spending faster than '
                      'earlier in the $word.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (projection != null && projection.hasBasis) ...<Widget>[
                      const SizedBox(height: 6),
                      const Divider(height: 1),
                      ProjectionLine(
                        projection: projection,
                        budgetLimitMinor: budgetLimit,
                        word: word,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              CompositionCard(
                totals: snapshot.compositionFor(range),
                period: range.period,
                word: word,
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Where it went',
                child: CategoryDonut(spends: snapshot.spendIn(range)),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Invested this $word',
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
                                  value: Money.compact(totals.cashLeftMinor),
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
                                    final category = snapshot.categoryNamed(
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
                child: budgets.isEmpty && range.period.monthsCovered == 0
                    // A week holds no whole month, so a monthly limit cannot be
                    // scaled to it. Saying so is better than drawing a bar against
                    // a figure nobody agreed to.
                    ? const EmptyState(
                        dense: true,
                        icon: Icons.savings_outlined,
                        title: 'Budgets are monthly',
                        message:
                            'Switch to Month, Quarter or Year to see spending '
                            'against their limits.',
                      )
                    : budgets.isEmpty
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
                          // Eight rather than five: with the card also carrying
                          // categories that have no limit, five was cutting rows
                          // the user could not see anywhere else on this screen.
                          for (final budget in budgets.take(8))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: BudgetRow(
                                budget: budget,
                                pace: paces[budget.category],
                                onTap: () {
                                  final category = snapshot.categoryNamed(
                                    budget.category,
                                  );
                                  if (category != null) {
                                    editBudget(
                                      context,
                                      category: category,
                                      spentMinor: budget.spentMinor,
                                      pace: paces[budget.category],
                                      suggestion: suggestions[budget.category],
                                    );
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              CommittedSpendCard(
                committedExpenseMinor: snapshot.committedMonthlyMinor,
                committedInvestmentMinor: snapshot.committedInvestmentMinor,
                dues: snapshot.upcomingDues(),
                incomeMinor: snapshot.currentMonth.incomeMinor,
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Biggest hits',
                child: BiggestHitsCard(
                  transactions: snapshot.topExpensesIn(range),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
