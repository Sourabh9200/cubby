import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/indicators.dart';
import '../../../core/widgets/section_card.dart';
import '../../../data/finance_snapshot.dart';
import '../../../data/models.dart';
import '../../../data/snapshot_views.dart';
import '../net_worth_screen.dart';

/// What went into investments this month, and how much of income that was.
///
/// Kept separate from the savings-rate card on purpose. The savings rate measures
/// what was kept; this measures how much of it was put to work. A month can keep
/// 60% of its income and invest none of it, and these two cards side by side say
/// exactly that.
class InvestingCard extends StatelessWidget {
  const InvestingCard({required this.snapshot, required this.month, super.key});

  final FinanceSnapshot snapshot;

  /// The month being shown, which follows the month selector.
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final summary = snapshot.summaryFor(month);
    final total = summary.investmentMinor;
    final rate = summary.investmentRate;
    final byCategory = snapshot.investedByCategory(month);

    if (total == 0) {
      return SectionCard(
        title: 'Investing',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const EmptyState(
              dense: true,
              icon: Icons.savings_outlined,
              title: 'Nothing invested this month',
              message:
                  'Record a contribution against an investing category and it '
                  'appears here, kept apart from your spending.',
            ),
            const _NetWorthLink(),
          ],
        ),
      );
    }

    final saved = summary.netMinor;
    final shareOfSaved = saved <= 0 ? null : (total / saved) * 100;

    return SectionCard(
      title: 'Investing',
      trailing: Pill(
        text: rate == null
            ? 'No income yet'
            : '${rate.toStringAsFixed(0)}% of income',
        color: money.investment,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          StatTile(
            label: 'Invested this month',
            value: Money.format(total, decimals: false),
            icon: Icons.trending_up_rounded,
            deltaText: shareOfSaved == null
                ? null
                : '${shareOfSaved.toStringAsFixed(0)}% of the '
                      '${Money.compact(saved)} you kept',
            deltaColor: money.investment,
          ),
          const SizedBox(height: 18),
          for (final spend in byCategory.take(4))
            _InvestedRow(spend: spend, total: total),
          const SizedBox(height: 2),
          Text(
            'Investments are not spending. They leave your account but stay '
            'yours, so they are counted separately from the red bars above — '
            'which is why a month of heavy investing is not a month of heavy '
            'spending.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const _NetWorthLink(),
        ],
      ),
    );
  }
}

/// The one link to the net-worth screen.
///
/// A link rather than a card: net worth is a deep view the user opens when they
/// want it, and the trends screen is already long. It lives here because this
/// card is about money moved into assets, which is half of what net worth is.
class _NetWorthLink extends StatelessWidget {
  const _NetWorthLink();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const NetWorthScreen())),
        icon: const Icon(Icons.show_chart_rounded, size: 18),
        label: const Text('Net worth, at cost'),
      ),
    );
  }
}

/// One investing category with its amount and share of the month's total.
class _InvestedRow extends StatelessWidget {
  const _InvestedRow({required this.spend, required this.total});

  final CategorySpend spend;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final share = total == 0 ? 0.0 : spend.totalMinor / total;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  spend.category,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${Money.format(spend.totalMinor, decimals: false)} · '
                '${(share * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // A bare bar rather than a progress track: there is no target here,
          // only a share of the month's total, and a track would imply a limit.
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            // Floored at 2% so a small holding is still visible rather than
            // rendering as an empty line.
            widthFactor: share.clamp(0.02, 1.0),
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: money.investment,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
