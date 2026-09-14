import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/indicators.dart';
import '../../../data/models.dart';
import '../../../data/repository_scope.dart';
import 'transaction_sheet.dart';

/// One row in the ledger.
class LedgerTile extends StatelessWidget {
  const LedgerTile({required this.transaction, required this.onTap, super.key});

  final Transaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);

    return ListTile(
      onTap: onTap,
      leading: CategoryAvatar(category: transaction.category),
      title: Text(
        transaction.payee,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${transaction.category} · ${transaction.account}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        switch (transaction.direction) {
          TxDirection.income => Money.signed(transaction.amountMinor),
          // Deliberately unsigned. "-₹20,000" beside a mutual fund reads as a
          // loss, when it is money the user still owns.
          TxDirection.investment => Money.format(transaction.amountMinor),
          _ => '-${Money.format(transaction.amountMinor)}',
        },
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: switch (transaction.direction) {
            TxDirection.income => money.income,
            TxDirection.investment => money.investment,
            _ => theme.colorScheme.onSurface,
          },
        ),
      ),
    );
  }
}

/// What the user asked for in [TransactionDetailSheet].
enum _DetailAction { edit, delete }

/// Bottom sheet showing one transaction, with the actions that change it.
class TransactionDetailSheet extends StatelessWidget {
  const TransactionDetailSheet({required this.transaction, super.key});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);

    // Scrollable, and opened with `isScrollControlled`. Five detail rows plus
    // two actions exceed the default half-height sheet constraint on a short
    // screen, and an overflow here clips the Edit and Delete buttons — the only
    // reason the sheet exists.
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CategoryAvatar(category: transaction.category, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        transaction.payee,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        Money.format(transaction.amountMinor),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: switch (transaction.direction) {
                            TxDirection.income => money.income,
                            TxDirection.investment => money.investment,
                            _ => null,
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            DetailRow(label: 'Category', value: transaction.category),
            DetailRow(label: 'Account', value: transaction.account),
            DetailRow(
              label: 'Date',
              value: DateLabels.dayMonth(transaction.date),
            ),
            DetailRow(
              label: 'Kind',
              value: switch (transaction.direction) {
                TxDirection.income => 'Money in',
                TxDirection.investment => 'Invested',
                TxDirection.transfer => 'Transfer',
                TxDirection.expense => 'Spent',
              },
            ),
            if (transaction.isSample)
              const DetailRow(label: 'Origin', value: 'Sample data'),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(_DetailAction.delete),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      foregroundColor: money.expense,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                      ),
                    ),
                    label: const Text('Delete'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(_DetailAction.edit),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    label: const Text('Edit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Label/value row used in detail views.
class DetailRow extends StatelessWidget {
  const DetailRow({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the detail sheet for [transaction] and carries out the chosen action.
///
/// A function rather than a widget callback, so the editing and deleting paths
/// run against the *caller's* context. Both need to outlive the sheet closing,
/// and the sheet's own context is already being torn down by the time it
/// returns — which is the classic way a delete button silently does nothing.
Future<void> showTransactionDetail(
  BuildContext context, {
  required Transaction transaction,
}) async {
  final action = await showModalBottomSheet<_DetailAction>(
    context: context,
    // The sheet is taller than the default half-height allowance, and letting it
    // size to its content keeps the Edit and Delete buttons on screen.
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => TransactionDetailSheet(transaction: transaction),
  );
  if (!context.mounted) {
    return;
  }
  switch (action) {
    case _DetailAction.edit:
      await showTransactionSheet(context, existing: transaction);
    case _DetailAction.delete:
      await _confirmAndDelete(context, transaction);
    case null:
      break;
  }
}

/// Asks before deleting, then reports what happened.
///
/// The prompt names the amount, category, and date rather than asking a bare
/// "are you sure?". Opening the wrong row in a long ledger is easy, and a dialog
/// that restates what is about to disappear is what catches the mistake.
Future<void> _confirmAndDelete(
  BuildContext context,
  Transaction transaction,
) async {
  final repository = RepositoryScope.actions(context);
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete this entry?'),
      content: Text(
        '${Money.format(transaction.amountMinor)} under '
        '${transaction.category}, dated '
        '${DateLabels.dayMonth(transaction.date)}. It will disappear from your '
        'ledger and from every total.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep it'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) {
    return;
  }
  try {
    await repository.deleteTransaction(transaction.id);
    messenger.showSnackBar(const SnackBar(content: Text('Entry deleted')));
  } on Object catch (error) {
    // Never swallowed. The user believes the record is gone, so if it is not,
    // they need to know immediately rather than by finding it still there.
    messenger.showSnackBar(
      SnackBar(content: Text('Could not delete the entry: $error')),
    );
  }
}
