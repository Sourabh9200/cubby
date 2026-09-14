import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/indicators.dart';
import '../../core/widgets/period_selector_bar.dart';
import '../../core/widgets/section_card.dart';
import '../../data/period_views.dart';
import '../../data/repository_scope.dart';
import '../../data/stats_period.dart';
import '../dashboard/widgets/budget_row.dart';
import '../dashboard/widgets/composition_card.dart';
import '../trends/payee_detail_screen.dart';
import 'widgets/figure_row.dart';
import 'year_in_review_screen.dart';

/// Any period from a single day to a year — including one the user picks —
/// summarised in one place.
///
/// The third tier's first screen, and the one the export work will hang off. It
/// is a screen of its own rather than a card on the overview because it is the
/// *whole* of a period: totals by all three measures, composition, where the
/// money went, who was paid, budgets, and the difference from the period before.
/// Nothing here is a new sum — every figure comes from the same methods the
/// overview and trends use, over these dates instead of their own, which is what
/// stops a report from disagreeing with the screen beside it.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  /// A calendar period, or [StatsPeriod.custom] when [_custom] is set.
  StatsPeriod _period = StatsPeriod.month;

  /// The user's own bounds, set by the date-range picker and cleared by a chip.
  StatsRange? _custom;

  /// The chips this screen offers: day through year.
  ///
  /// More than the overview shows, and deliberately: a single day is a real
  /// report — "what did I actually spend on the 14th" — and the overview has no
  /// room for a chip that most glances do not want.
  static const List<StatsPeriod> _chips = <StatsPeriod>[
    StatsPeriod.day,
    StatsPeriod.week,
    StatsPeriod.month,
    StatsPeriod.quarter,
    StatsPeriod.year,
  ];

  /// Room for the chips plus the custom-range button beneath them.
  static const double _selectorHeight = PeriodChips.height + 44;

  void _select(StatsPeriod period) {
    setState(() {
      _period = period;
      _custom = null;
    });
  }

  /// Opens the date picker, bounded by the ledger and the clock.
  ///
  /// The picker opens on the period already on screen, clamped to what the ledger
  /// holds and to today, so it starts where the user is looking rather than at the
  /// first day the app has ever seen.
  Future<void> _pickRange(
    StatsRange shown,
    DateTime first,
    DateTime last,
  ) async {
    final existing = _custom ?? shown;
    final start = existing.from.isBefore(first) ? first : existing.from;
    var end = existing.to.subtract(const Duration(days: 1));
    if (end.isAfter(last)) {
      end = last;
    }
    if (end.isBefore(start)) {
      // A period that has not begun cannot be preselected; today is the honest
      // answer, and the user can move it.
      end = start;
    }

    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: DateTimeRange(start: start, end: end),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      // The picker's end date is inclusive and a range's end is exclusive, so the
      // day the user tapped last is inside the report.
      _custom = StatsRange.custom(
        from: picked.start,
        to: picked.end.add(const Duration(days: 1)),
      );
      _period = StatsPeriod.custom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final snapshot = RepositoryScope.of(context);
    final range = _custom ?? StatsRange.containing(_period, snapshot.now);
    final word = periodWord(range.period);

    final totals = snapshot.totalsFor(range);
    final previous = snapshot.previousPeriodComparison(range);
    final spends = snapshot.spendIn(range);
    final payees = snapshot.topPayeesIn(range, limit: 6);
    final budgets = snapshot.budgetStatusesIn(range);
    final entries = snapshot.transactionsIn(range).length;

    final today = DateTime(
      snapshot.now.year,
      snapshot.now.month,
      snapshot.now.day,
    );

    // The same-length window ending today: stepping forward from a custom range
    // stops where a calendar period's does, at now.
    final currentCustom = StatsRange.custom(
      from: today.subtract(Duration(days: range.days - 1)),
      to: today.add(const Duration(days: 1)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(_selectorHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              PeriodChips(
                period: range.period,
                periods: _chips,
                onChanged: _select,
              ),
              TextButton.icon(
                onPressed: () => _pickRange(
                  range,
                  snapshot.firstRecordedDay ?? today,
                  today,
                ),
                icon: const Icon(Icons.date_range_rounded, size: 18),
                label: Text(
                  range.period == StatsPeriod.custom
                      ? 'Change range'
                      : 'Custom range',
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          Center(
            child: PeriodStepper(
              range: range,
              current: _custom == null
                  ? StatsRange.containing(_period, snapshot.now)
                  : currentCustom,
              earliest: snapshot.firstRecordedDay,
              onChanged: (next) => setState(() {
                _custom = next.period == StatsPeriod.custom ? next : null;
                _period = next.period;
              }),
            ),
          ),
          const SizedBox(height: 8),
          if (range.period == StatsPeriod.year) ...<Widget>[
            Center(
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => YearInReviewScreen(year: range.from.year),
                  ),
                ),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Year in review'),
              ),
            ),
          ],
          SectionCard(
            title: 'Totals',
            trailing: Pill(
              text: entries == 1 ? '1 entry' : '$entries entries',
              color: theme.colorScheme.primary,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                FigureRow(
                  label: 'Received',
                  value: Money.format(totals.incomeMinor, decimals: false),
                  color: money.income,
                  detail: _changeText(previous?.incomeChangePercent, word),
                ),
                FigureRow(
                  label: 'Spent',
                  value: Money.format(totals.expenseMinor, decimals: false),
                  color: money.expense,
                  detail: _changeText(previous?.expenseChangePercent, word),
                ),
                FigureRow(
                  label: 'Invested',
                  value: Money.format(totals.investmentMinor, decimals: false),
                  color: money.investment,
                  detail: _changeText(previous?.investmentChangePercent, word),
                ),
                FigureRow(
                  label: 'Kept',
                  value: Money.format(totals.netMinor, decimals: false),
                  color: totals.netMinor < 0 ? money.expense : null,
                  detail: 'Income less what was spent',
                ),
                FigureRow(
                  label: 'Left in cash',
                  value: Money.format(totals.cashLeftMinor, decimals: false),
                  detail: 'After investing as well',
                ),
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
            child: spends.isEmpty
                ? const EmptyState(
                    dense: true,
                    icon: Icons.pie_chart_outline_rounded,
                    title: 'Nothing spent',
                    message: 'No expenses fall inside this period.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final spend in spends.take(6))
                        FigureRow(
                          label: spend.category,
                          value: Money.format(
                            spend.totalMinor,
                            decimals: false,
                          ),
                          detail:
                              '${spend.shareOf(totals.expenseMinor).toStringAsFixed(0)}% '
                              'of spending · ${_entryCount(spend.txnCount)}',
                        ),
                      if (spends.length > 6)
                        FigureRow(
                          label: 'Everything else',
                          value: Money.format(
                            spends
                                .skip(6)
                                .fold(
                                  0,
                                  (sum, spend) => sum + spend.totalMinor,
                                ),
                            decimals: false,
                          ),
                          detail:
                              '${spends.length - 6} more categories, each one '
                              'listed in the ledger',
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Who was paid',
            child: payees.isEmpty
                ? const EmptyState(
                    dense: true,
                    icon: Icons.storefront_outlined,
                    title: 'Nothing paid',
                    message: 'No payee has an expense in this period.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final payee in payees)
                        FigureRow(
                          label: payee.payee,
                          value: Money.format(
                            payee.totalMinor,
                            decimals: false,
                          ),
                          // Payees are matched exactly as recorded and never
                          // merged (C8), so the count and the average belong to
                          // the name as it was typed — not to a merchant.
                          detail:
                              '${_entryCount(payee.count)} · avg '
                              '${Money.format(payee.averageMinor, decimals: false)}',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  PayeeDetailScreen(payee: payee.payee),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Budgets',
            child: budgets.isEmpty
                ? EmptyState(
                    dense: true,
                    icon: Icons.savings_outlined,
                    title: 'Budgets are monthly',
                    message: range.period == StatsPeriod.custom
                        ? 'A range you chose is not a whole number of months, so '
                              'a monthly limit cannot be scaled to it. Pick a '
                              'month, quarter or year for budget outcomes.'
                        : 'A day or a week holds no whole month. Switch to Month, '
                              'Quarter or Year to see spending against their '
                              'limits.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final budget in budgets)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: BudgetRow(budget: budget),
                        ),
                      Text(
                        range.period == StatsPeriod.year
                            ? 'Limits are monthly, scaled by the twelve months '
                                  'this year covers.'
                            : range.period == StatsPeriod.quarter
                            ? 'Limits are monthly, scaled by the three months '
                                  'this quarter covers.'
                            : 'Limits are monthly, and this period is one of '
                                  'them.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            'Every figure here comes from the same sums the overview and the '
            'trends use, over these dates rather than their own — which is why a '
            'report cannot disagree with the screen beside it. Export is on the '
            'roadmap, and this is the screen it will hang off.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// "12% more than the previous month", or why there is nothing to compare.
  String _changeText(double? percent, String word) {
    if (percent == null) {
      return 'Nothing comparable in the previous $word';
    }
    final magnitude = percent.abs();
    final rounded = magnitude < 10
        ? magnitude.toStringAsFixed(1)
        : magnitude.toStringAsFixed(0);
    return '$rounded% ${percent >= 0 ? 'more' : 'less'} than the previous $word';
  }

  /// "1 entry" / "4 entries", so no line ever reads "1 entries".
  String _entryCount(int count) => count == 1 ? '1 entry' : '$count entries';
}
