import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/indicators.dart';
import '../../../core/widgets/section_card.dart';
import '../../../data/upcoming_due.dart';

/// What recurring rules already account for, and what falls due next.
///
/// The figure a recurring feature exists for: not "you have four rules" but
/// "₹62,000 of this month is already spoken for". Wording throughout says
/// *scheduled*, never *owed*, because a rule describes a habit rather than an
/// obligation (C14), and investing by rule is listed apart from spending because
/// it is not consumption (C1).
///
/// Always about the month in progress, whichever period is on screen: rules are
/// monthly, and stretching a monthly figure over a quarter would be arithmetic
/// that looks precise and is simply wrong.
class CommittedSpendCard extends StatelessWidget {
  const CommittedSpendCard({
    required this.committedExpenseMinor,
    required this.committedInvestmentMinor,
    required this.dues,
    required this.incomeMinor,
    super.key,
  });

  /// The sum of live expense rules: what a typical month repeats.
  final int committedExpenseMinor;

  /// The sum of live investing rules, shown apart from spending (C1).
  final int committedInvestmentMinor;

  /// Rules due within the next thirty days, soonest first.
  final List<UpcomingDue> dues;

  /// Income recorded in the month in progress, for the share line.
  final int incomeMinor;

  bool get _hasAnything =>
      committedExpenseMinor > 0 ||
      committedInvestmentMinor > 0 ||
      dues.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);

    if (!_hasAnything) {
      return const SectionCard(
        title: 'Already spoken for',
        child: EmptyState(
          dense: true,
          icon: Icons.event_repeat_rounded,
          title: 'Nothing repeats yet',
          message:
              'Switch on Repeat when you record rent, a subscription or a SIP '
              'and the months it covers are counted here.',
        ),
      );
    }

    final share = incomeMinor == 0
        ? null
        : (committedExpenseMinor / incomeMinor) * 100;

    return SectionCard(
      title: 'Already spoken for',
      trailing: Pill(text: 'this month', color: theme.colorScheme.primary),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          StatTile(
            label: 'Scheduled spending',
            value: Money.format(committedExpenseMinor, decimals: false),
            icon: Icons.event_repeat_rounded,
            deltaText: share == null
                ? 'No income recorded this month'
                : '${share.toStringAsFixed(0)}% of this month\'s income',
            deltaColor: share == null
                ? null
                : (share > 100 ? money.expense : theme.colorScheme.primary),
          ),
          if (committedInvestmentMinor > 0) ...<Widget>[
            const SizedBox(height: 14),
            _ScheduledRow(
              label: 'Into investments by rule',
              amountMinor: committedInvestmentMinor,
              color: money.investment,
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'Next 30 days',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          if (dues.isEmpty)
            Text(
              'Nothing else is due in the next 30 days.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final due in dues) _DueRow(due: due),
          const SizedBox(height: 2),
          Text(
            'A rule repeats what has happened before; it is not a commitment. '
            'Stopping one takes it out of this figure straight away, and the '
            'entries it already recorded stay.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled amount with a swatch, for the investing-by-rule line.
class _ScheduledRow extends StatelessWidget {
  const _ScheduledRow({
    required this.label,
    required this.amountMinor,
    required this.color,
  });

  final String label;
  final int amountMinor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
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
          Money.format(amountMinor, decimals: false),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// One rule's next occurrence, dated rather than described as "monthly".
class _DueRow extends StatelessWidget {
  const _DueRow({required this.due});

  final UpcomingDue due;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final title = due.payee.isEmpty ? due.category : due.payee;
    final detail = due.payee.isEmpty
        ? 'Scheduled ${DateLabels.dayMonth(due.dueOn)}'
        : '${due.category} · scheduled ${DateLabels.dayMonth(due.dueOn)}';
    final amountColor = due.isIncome
        ? money.income
        : (due.isInvestment ? money.investment : theme.colorScheme.onSurface);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            Money.format(due.amountMinor, decimals: false),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: amountColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
