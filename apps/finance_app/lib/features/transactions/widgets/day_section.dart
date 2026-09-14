import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../data/models.dart';
import 'ledger_tile.dart';

/// One day's worth of ledger rows, with a header and a daily subtotal.
class DaySection extends StatelessWidget {
  const DaySection({
    required this.date,
    required this.items,
    required this.dayTotalMinor,
    required this.referenceNow,
    super.key,
  });

  final DateTime date;
  final List<Transaction> items;
  final int dayTotalMinor;
  final DateTime referenceNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Row(
            children: <Widget>[
              Text(
                DateLabels.ledgerHeader(date, referenceNow),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (dayTotalMinor > 0)
                Text(
                  Money.format(dayTotalMinor, decimals: false),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        for (final txn in items)
          LedgerTile(
            transaction: txn,
            onTap: () => showTransactionDetail(context, transaction: txn),
          ),
      ],
    );
  }
}
