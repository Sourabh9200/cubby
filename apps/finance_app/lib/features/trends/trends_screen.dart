import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/indicators.dart';
import '../../core/widgets/month_selector_bar.dart';
import '../../core/widgets/section_card.dart';
import '../../data/month_scope.dart';
import '../../data/period_views.dart';
import '../../data/repository_scope.dart';
import '../../data/snapshot_analytics.dart';
import '../../data/snapshot_views.dart';
import '../../data/stats_period.dart';
import '../reports/reports_screen.dart';
import 'payee_detail_screen.dart';
import 'widgets/category_movement_card.dart';
import 'widgets/composition_over_time_card.dart';
import 'widgets/income_sources_card.dart';
import 'widgets/investing_card.dart';
import 'widgets/monthly_bars_chart.dart';
import 'widgets/monthly_records_card.dart';
import 'widgets/savings_rate_card.dart';
import 'widgets/spending_rhythm_card.dart';
import 'widgets/top_payees_card.dart';
import 'widgets/year_over_year_card.dart';

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

    // The history-shaped cards are scoped to the year rather than to the month
    // selector: "what is my pattern" needs a longer window than a month, and the
    // year in progress is the longest window that can still be compared with the
    // year before it. The month-scoped cards below still follow the shared month.
    final yearRange = StatsRange.containing(StatsPeriod.year, snapshot.now);
    final monthRange = StatsRange.containing(StatsPeriod.month, snapshot.now);

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          title: const Text('Trends'),
          // The way into a report, without a card on any screen: the two
          // questions the trends answer — what is my pattern, and what does a
          // period add up to — belong next to each other, and an icon is the
          // whole cost of saying so.
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.summarize_rounded),
              tooltip: 'Reports',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ReportsScreen()),
              ),
            ),
          ],
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
                    // A Wrap rather than a Row, as the composition card's legend
                    // is: three swatches and their labels do not fit a 347 dp
                    // phone on one line, and the honest answer is to use a second
                    // line rather than to overflow it.
                    Wrap(
                      spacing: 14,
                      runSpacing: 8,
                      children: <Widget>[
                        LegendDot(color: money.expense, label: 'Spent'),
                        LegendDot(color: money.income, label: 'Received'),
                        LegendDot(color: money.investment, label: 'Invested'),
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
              CompositionOverTimeCard(
                points: snapshot.compositionByMonthIn(yearRange),
              ),
              const SizedBox(height: 14),
              YearOverYearCard(
                comparison: snapshot.yearOverYearFor(monthRange),
                month: monthRange.from,
              ),
              const SizedBox(height: 14),
              SavingsRateCard(summaries: snapshot.monthlySummaries),
              const SizedBox(height: 14),
              InvestingCard(snapshot: snapshot, month: scope.month),
              const SizedBox(height: 14),
              MonthlyRecordsCard(extremes: snapshot.monthlyExtremes),
              const SizedBox(height: 14),
              TopPayeesCard(
                payees: snapshot.topPayeesIn(yearRange, limit: 6),
                range: yearRange,
                onTap: (payee) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PayeeDetailScreen(payee: payee.payee),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SpendingRhythmCard(rhythm: snapshot.spendingRhythmIn(yearRange)),
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
