import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/indicators.dart';
import '../../../core/widgets/section_card.dart';
import '../../../data/composition.dart';
import '../../../data/stats_period.dart';

/// Where a period's income went: spent, invested, or left in the bank.
///
/// Three slices rather than the usual spent-versus-received pair, because a
/// period can be comfortably in surplus while every rupee of the surplus moved
/// into mutual funds — and the reverse. One measured total cannot say which, and
/// folding investing into spending (C1) makes the savings rate wrong by exactly
/// the amount invested.
class CompositionCard extends StatelessWidget {
  const CompositionCard({
    required this.totals,
    required this.period,
    required this.word,
    super.key,
  });

  final CompositionTotals totals;

  /// The selected period length, so the monthly caveat appears only for a
  /// month, where the caveat is true (C15).
  final StatsPeriod period;

  /// How the period is named in a sentence: `week`, `month`, `quarter`, `year`.
  final String word;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);

    if (totals.isEmpty) {
      return SectionCard(
        title: 'Composition',
        child: EmptyState(
          dense: true,
          icon: Icons.pie_chart_outline_rounded,
          title: 'Nothing recorded this $word',
          message:
              'Record income and spending and this divides the period into '
              'what was spent, what was invested, and what was left.',
        ),
      );
    }

    final savingsRate = totals.savingsRate;
    final isOverdrawn = totals.isOverdrawn;

    return SectionCard(
      title: 'Composition',
      trailing: Pill(text: 'this $word', color: theme.colorScheme.primary),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          StatTile(
            label: 'Income',
            value: Money.format(totals.incomeMinor, decimals: false),
            icon: Icons.south_west_rounded,
            deltaText: savingsRate == null
                ? 'No income recorded'
                : '${savingsRate.toStringAsFixed(0)}% kept',
            deltaColor: savingsRate == null
                ? null
                : (savingsRate >= 0 ? money.income : money.expense),
          ),
          const SizedBox(height: 16),
          _CompositionBar(totals: totals),
          const SizedBox(height: 16),
          _SliceRow(
            label: 'Spent',
            amountMinor: totals.expenseMinor,
            share: totals.shareOfIncome(totals.expenseMinor),
            color: money.expense,
          ),
          _SliceRow(
            label: 'Invested',
            amountMinor: totals.investmentMinor,
            share: totals.shareOfIncome(totals.investmentMinor),
            color: money.investment,
          ),
          _SliceRow(
            label: isOverdrawn ? 'Overspent' : 'Unallocated',
            amountMinor: totals.unallocatedMinor,
            share: totals.shareOfIncome(totals.unallocatedMinor),
            color: isOverdrawn ? money.warning : money.neutral,
            signedAmount: isOverdrawn,
          ),
          const SizedBox(height: 4),
          Text(
            'Invested money is not spending: it left the account but it is '
            'still yours, which is why it has a slice of its own.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (period == StatsPeriod.month) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'One month of income is lumpy — a single invoice or bonus can '
              'double it. The quarter or the year is the honest place to read '
              'this split.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A stacked bar of one band per slice, widths in proportion to the amounts.
///
/// The flexes carry the raw minor amounts rather than pre-computed fractions, so
/// a rounding error cannot leave a slice invisible and the bands stay exactly
/// proportional however large the figures get.
class _CompositionBar extends StatelessWidget {
  const _CompositionBar({required this.totals});

  final CompositionTotals totals;

  @override
  Widget build(BuildContext context) {
    final money = MoneyColors.of(context);
    final bands = <_Band>[
      // An overspent part gets its own band in the warning colour rather than
      // being folded into spending: it is the amount by which the period
      // consumed more than it earned, and hiding it would make the bar look
      // like a fully allocated one.
      _Band(totals.expenseMinor, money.expense),
      _Band(totals.investmentMinor, money.investment),
      if (totals.unallocatedMinor > 0)
        _Band(totals.unallocatedMinor, money.neutral),
      if (totals.unallocatedMinor < 0)
        _Band(-totals.unallocatedMinor, money.warning),
    ].where((band) => band.amountMinor > 0).toList(growable: false);

    if (bands.isEmpty) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 12,
        child: Row(
          children: <Widget>[
            for (var index = 0; index < bands.length; index++)
              Expanded(
                flex: bands[index].amountMinor,
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index == bands.length - 1 ? 0 : 2,
                  ),
                  child: ColoredBox(color: bands[index].color),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One band of the stacked bar: an amount and the colour it reads in.
class _Band {
  const _Band(this.amountMinor, this.color);

  final int amountMinor;
  final Color color;
}

/// One slice's row: swatch, label, amount, and its share of income.
class _SliceRow extends StatelessWidget {
  const _SliceRow({
    required this.label,
    required this.amountMinor,
    required this.share,
    required this.color,
    this.signedAmount = false,
  });

  final String label;
  final int amountMinor;

  /// Percentage of income, or null when the period recorded no income.
  final double? share;

  final Color color;

  /// True when [amountMinor] is negative and its sign has to be shown.
  final bool signedAmount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = share;
    final formatted = signedAmount
        ? '-${Money.format(amountMinor.abs(), decimals: false)}'
        : Money.format(amountMinor, decimals: false);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            formatted,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 58,
            child: Text(
              percent == null ? '—' : '${percent.toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
