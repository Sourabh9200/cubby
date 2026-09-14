import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/indicators.dart';
import '../../../core/widgets/section_card.dart';
import '../../../data/models.dart';

/// Where the month's income came from, split by source.
///
/// The dashboard answers "how much came in"; this answers "from where", which
/// one figure cannot. A salary, a freelance invoice, interest, and rent received
/// are different cash flows with very different reliability, and a month carried
/// by a one-off bonus looks identical to a month carried by a salary until they
/// are pulled apart.
///
/// Every total here comes from the same snapshot map as the headline income
/// figure, so the rows cannot add up to anything other than what the summary
/// says.
class IncomeSourcesCard extends StatelessWidget {
  const IncomeSourcesCard({
    required this.sources,
    required this.totalMinor,
    required this.month,
    super.key,
  });

  /// Income per source, largest first.
  final List<CategorySpend> sources;

  /// Total income for [month], from the month aggregate.
  final int totalMinor;

  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);

    if (sources.isEmpty) {
      return const SectionCard(
        title: 'Income sources',
        child: EmptyState(
          dense: true,
          icon: Icons.south_west_rounded,
          title: 'No income this month',
          message:
              'Record money received against an income category and every '
              'source is listed here.',
        ),
      );
    }

    return SectionCard(
      title: 'Income sources',
      trailing: Pill(
        text: sources.length == 1 ? '1 source' : '${sources.length} sources',
        color: money.income,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Received in ${DateLabels.monthYear(month)}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            Money.format(totalMinor, decimals: false),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 18),
          for (final source in sources)
            _SourceRow(source: source, total: totalMinor),
          const SizedBox(height: 2),
          Text(
            'Each income category is one cash flow. Add more under Settings → '
            'Categories & budgets → Add a category, choosing Income, to tell '
            'salary apart from freelance work, interest, or rent received.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One income source with its amount and share of the month.
class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source, required this.total});

  final CategorySpend source;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final share = total == 0 ? 0.0 : source.totalMinor / total;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  source.category,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${Money.format(source.totalMinor, decimals: false)} · '
                '${(share * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // A bare bar, like the investing card's: this is a share of a total,
          // not progress toward a figure, and a track would imply a target.
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            // Floored so a small source is still visible rather than rendering
            // as an empty line.
            widthFactor: share.clamp(0.02, 1.0),
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: money.income,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
