import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/widgets/indicators.dart';
import '../../../core/widgets/section_card.dart';
import '../../../data/payee_totals.dart';
import '../../../data/stats_period.dart';

/// The places a period's money actually went, largest first.
///
/// A category says *what* was bought ("Groceries"); a payee says *where*
/// ("BigBasket"), and nothing in the app read that column before this card.
/// Tapping a row opens that payee's own history.
class TopPayeesCard extends StatelessWidget {
  const TopPayeesCard({
    required this.payees,
    required this.range,
    required this.onTap,
    super.key,
  });

  /// Payees with spending in [range], largest first.
  final List<PayeeTotal> payees;

  /// The range the totals cover, so the pill can name its year.
  final StatsRange range;

  final ValueChanged<PayeeTotal> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (payees.isEmpty) {
      return SectionCard(
        title: 'Top places',
        child: EmptyState(
          dense: true,
          icon: Icons.storefront_rounded,
          title: 'Nothing recorded in ${range.from.year}',
          message:
              'Entries with a payee recorded are grouped here, biggest first.',
        ),
      );
    }

    return SectionCard(
      title: 'Top places',
      trailing: Pill(
        text: '${range.from.year}',
        color: theme.colorScheme.primary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final payee in payees)
            InkWell(
              onTap: () => onTap(payee),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 4,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            payee.payee,
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            payee.count == 1
                                ? '1 entry · ${Money.format(payee.averageMinor)}'
                                : '${payee.count} entries · '
                                      '${Money.format(payee.averageMinor)} '
                                      'average',
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
                      Money.format(payee.totalMinor, decimals: false),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 2),
          Text(
            'Names are shown exactly as they were typed. The app never merges '
            'two spellings of the same shop, because doing so would invent a '
            'merchant your ledger never recorded.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
