import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/widgets/indicators.dart';
import '../../../data/models.dart';

/// The largest individual expenses of the month.
///
/// Aggregate charts hide outliers by design — a ₹40,000 one-off disappears into
/// a category total. Surfacing raw outliers beside the aggregates is how a user
/// spots the thing they actually want to question.
class BiggestHitsCard extends StatelessWidget {
  const BiggestHitsCard({required this.transactions, super.key});

  final List<Transaction> transactions;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_rounded,
        title: 'Nothing yet',
        message: 'No expenses recorded this month.',
      );
    }
    final theme = Theme.of(context);

    return Column(
      children: <Widget>[
        for (final txn in transactions)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: <Widget>[
                CategoryAvatar(category: txn.category),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        txn.payee,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${txn.category} · ${DateLabels.dayMonth(txn.date)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  Money.format(txn.amountMinor, decimals: false),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
