import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/month_selector_bar.dart';
import '../../core/widgets/section_card.dart';
import '../../data/month_scope.dart';
import '../../data/snapshot_analytics.dart';
import '../../data/repository_scope.dart';
import '../../data/snapshot_views.dart';
import 'widgets/category_movement_card.dart';
import 'widgets/income_sources_card.dart';
import 'widgets/investing_card.dart';
import 'widgets/monthly_bars_chart.dart';
import 'widgets/monthly_records_card.dart';
import 'widgets/savings_rate_card.dart';

/// Trends and month-over-month movement.
///
/// The cards exist because a chart alone leaves the interpretation to the user.
/// Stating the finding in words — "Dining Out is up 38% against your own
/// average" — is the difference between a chart and an answer.
class TrendsScreen extends StatelessWidget {
  const TrendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final snapshot = RepositoryScope.of(context);
    final scope = MonthScope.of(context);
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          title: const Text('Trends'),
          // The month-scoped cards below follow the same selection as the
          // overview. The history cards — the bars, the savings rate, the
          // records — deliberately do not: they exist to span every month.
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(MonthSelectorBar.height),
            child: MonthSelectorBar(),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          sliver: SliverList.list(
            children: <Widget>[
              SectionCard(
                title: 'Income vs spending',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        _LegendDot(color: money.expense, label: 'Spent'),
                        const SizedBox(width: 14),
                        _LegendDot(color: money.income, label: 'Received'),
                        const SizedBox(width: 14),
                        _LegendDot(color: money.investment, label: 'Invested'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    MonthlyBarsChart(summaries: snapshot.monthlySummaries),
                    const SizedBox(height: 10),
                    Text(
                      'The gap between the green and red bars is what you kept '
                      'that month. Blue is money moved into assets — still '
                      'yours, which is why it is not counted as spending.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SavingsRateCard(summaries: snapshot.monthlySummaries),
              const SizedBox(height: 14),
              InvestingCard(snapshot: snapshot, month: scope.month),
              const SizedBox(height: 14),
              MonthlyRecordsCard(extremes: snapshot.monthlyExtremes),
              const SizedBox(height: 14),
              IncomeSourcesCard(
                sources: snapshot.incomeBySource(scope.month),
                totalMinor: snapshot.incomeTotal(scope.month),
                month: scope.month,
              ),
              const SizedBox(height: 14),
              CategoryMovementCard(
                movements: snapshot.categoryMovement(scope.month),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

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
