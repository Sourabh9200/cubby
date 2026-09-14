import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/indicators.dart';
import '../../../core/widgets/section_card.dart';
import '../../../data/period_comparison.dart';

/// One month against the same days of the same month a year earlier.
///
/// A year is the only comparison that strips out season — a festival month, a
/// school fee, a quarterly premium — so it answers "is this normal for me"
/// rather than "was last month busier". The three measures stay apart, because a
/// single combined delta would move for a reason the user cannot act on.
class YearOverYearCard extends StatelessWidget {
  const YearOverYearCard({
    required this.comparison,
    required this.month,
    super.key,
  });

  /// The comparison, or null when the ledger does not hold a year of history
  /// before [month] (C7).
  final PeriodComparison? comparison;

  /// The month being compared, at its first instant.
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final previousMonth = DateTime(month.year - 1, month.month);

    final result = comparison;
    if (result == null) {
      return const SectionCard(
        title: 'Against last year',
        child: EmptyState(
          dense: true,
          icon: Icons.history_rounded,
          title: 'Not enough history',
          message:
              'Comparing months needs the whole of the same month a year '
              'earlier. This ledger does not reach back that far yet — the '
              'comparison appears when it does.',
        ),
      );
    }

    return SectionCard(
      title: 'Against last year',
      trailing: Pill(
        text: '${DateLabels.shortMonth(month)} ${month.year}',
        color: theme.colorScheme.primary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Against the same days of ${DateLabels.monthYear(previousMonth)}.',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _CompareRow(
            label: 'Spent',
            currentMinor: result.current.expenseMinor,
            previousMinor: result.comparableExpenseMinor,
            changePercent: result.expenseChangePercent,
            upIsGood: false,
            money: money,
          ),
          _CompareRow(
            label: 'Received',
            currentMinor: result.current.incomeMinor,
            previousMinor: result.comparableIncomeMinor,
            changePercent: result.incomeChangePercent,
            upIsGood: true,
            money: money,
          ),
          _CompareRow(
            label: 'Invested',
            currentMinor: result.current.investmentMinor,
            previousMinor: result.comparableInvestmentMinor,
            changePercent: result.investmentChangePercent,
            upIsGood: true,
            money: money,
          ),
          const SizedBox(height: 2),
          Text(
            'Last year is scaled to the same point in the month '
            '(${(result.previousScale * 100).toStringAsFixed(0)}%), because a '
            'part-month against a whole one would read as a saving every time.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Invested is compared on its own: a month can spend less and '
            'invest more, and one combined line would hide exactly that.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One measure: this month, the same part of last year, and the change.
class _CompareRow extends StatelessWidget {
  const _CompareRow({
    required this.label,
    required this.currentMinor,
    required this.previousMinor,
    required this.changePercent,
    required this.upIsGood,
    required this.money,
  });

  final String label;
  final int currentMinor;
  final int previousMinor;
  final double? changePercent;

  /// True for measures where more is better, so the delta's colour can say so.
  final bool upIsGood;

  final MoneyColors money;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = changePercent;
    final Color color;
    if (change == null || change == 0) {
      color = money.neutral;
    } else if ((change > 0) == upIsGood) {
      color = money.income;
    } else {
      color = money.expense;
    }
    // "new" only when something was recorded this month and nothing was a year
    // earlier; two zeros are simply not a comparison.
    final badge = change == null
        ? (currentMinor == 0 ? '—' : 'new')
        : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(0)}%';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text(
                Money.format(currentMinor, decimals: false),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 68,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Pill(text: badge, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'a year earlier: ${Money.format(previousMinor, decimals: false)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
