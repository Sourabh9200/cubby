import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/charts/chart_bar.dart';
import '../../core/widgets/indicators.dart';
import '../../core/widgets/section_card.dart';
import '../../data/models.dart';
import '../../data/payee_totals.dart';
import '../../data/period_views.dart';
import '../../data/repository_scope.dart';

/// One payee's whole history: the total, the months, and the entries.
///
/// No other screen can answer "what have I spent at this shop" — a category
/// answers what was bought, not where — and this is the drill-down the top
/// payees card opens. Names are matched exactly as recorded (C8).
class PayeeDetailScreen extends StatelessWidget {
  const PayeeDetailScreen({required this.payee, super.key});

  final String payee;

  /// How many months the series shows.
  static const int monthLimit = 12;

  /// How many entries the list shows before it says it has stopped.
  static const int entryLimit = 100;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final snapshot = RepositoryScope.of(context);
    final total = snapshot.payeeTotalFor(payee);
    final series = snapshot.payeeSeries(payee);
    final entries = snapshot.payeeEntries(payee);
    final months = series.length > monthLimit
        ? series.sublist(series.length - monthLimit)
        : series;
    final shown = entries.take(entryLimit).toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(payee)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: <Widget>[
          SectionCard(
            title: 'Spent here',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: StatTile(
                    label: 'Total',
                    value: Money.format(total.totalMinor, decimals: false),
                    icon: Icons.receipt_long_rounded,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: StatTile(
                    label: 'Entries',
                    value: '${total.count}',
                    icon: Icons.tag_rounded,
                    deltaText: total.count == 0
                        ? null
                        : '${Money.format(total.averageMinor)} average',
                    deltaColor: money.neutral,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (months.isNotEmpty) ...<Widget>[
            SectionCard(
              title: 'Month by month',
              child: _MonthBars(series: months),
            ),
            const SizedBox(height: 14),
          ],
          SectionCard(
            title: 'Entries',
            trailing: Pill(
              text: '${entries.length}',
              color: theme.colorScheme.primary,
            ),
            child: shown.isEmpty
                ? const EmptyState(
                    dense: true,
                    icon: Icons.receipt_long_rounded,
                    title: 'Nothing recorded',
                    message: 'No expenses are filed against this payee.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final txn in shown) _EntryRow(txn: txn),
                      if (entries.length > shown.length) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          'Showing the latest ${shown.length} of '
                          '${entries.length} entries.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// One bar per month, oldest on the left.
class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.series});

  final List<PayeeMonthTotal> series;

  /// Height of the bars themselves, not of the whole chart.
  ///
  /// A payee's month labels are three letters wide on a column that may be
  /// twenty dp across, so the labels get their own height and are scaled down to
  /// fit rather than allowed to wrap into the bars' reserve.
  static const double barHeight = 62;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);

    var maxTotal = 0;
    for (final month in series) {
      if (month.totalMinor > maxTotal) {
        maxTotal = month.totalMinor;
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (final month in series)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    height: barHeight,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: ChartBar(
                        height: maxTotal == 0
                            ? 2
                            : (month.totalMinor / maxTotal * barHeight).clamp(
                                2,
                                barHeight,
                              ),
                        color: money.expense.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      DateLabels.shortMonth(month.month),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One recorded expense at this payee.
class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.txn});

  final Transaction txn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  txn.category,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  DateLabels.dayMonth(txn.date),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            Money.format(txn.amountMinor, decimals: false),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
