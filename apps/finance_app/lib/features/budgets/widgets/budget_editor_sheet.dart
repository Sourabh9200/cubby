import 'package:flutter/material.dart';

import '../../../core/format/amount_entry.dart';
import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repository_scope.dart';
import '../../transactions/widgets/amount_field.dart';
import '../../transactions/widgets/numeric_keypad.dart';

/// Sets or clears a category's recurring monthly budget.
///
/// Shares the amount field and numeric pad with the quick-add sheet, so entering
/// a budget feels identical to entering a transaction.
class BudgetEditorSheet extends StatefulWidget {
  const BudgetEditorSheet({
    required this.categoryId,
    required this.categoryName,
    required this.currentBudgetMinor,
    this.spentMinor = 0,
    super.key,
  });

  final String categoryId;
  final String categoryName;
  final int currentBudgetMinor;

  /// Spend so far this month, shown so the user sets a budget with the actual
  /// number in front of them rather than from memory.
  final int spentMinor;

  @override
  State<BudgetEditorSheet> createState() => _BudgetEditorSheetState();
}

class _BudgetEditorSheetState extends State<BudgetEditorSheet> {
  late final AmountEntry _entry = AmountEntry(
    initial: AmountEntry.toEditableText(widget.currentBudgetMinor),
  );
  bool _saving = false;

  Future<void> _save(int budgetMinor) async {
    setState(() => _saving = true);
    final repository = RepositoryScope.actions(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final label = widget.categoryName;

    try {
      await repository.setCategoryBudget(
        categoryId: widget.categoryId,
        budgetMinor: budgetMinor,
      );
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            budgetMinor == 0
                ? 'Budget cleared for $label'
                : 'Budget for $label set to '
                      '${Money.format(budgetMinor, decimals: false)}',
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() => _saving = false);
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save the budget: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spent = widget.spentMinor;
    final typedMinor = _entry.minor;
    final overBudget = typedMinor > 0 && spent > typedMinor;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Monthly budget for ${widget.categoryName}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Spent ${Money.format(spent, decimals: false)} so far this month',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            AmountField(typed: _entry.text),
            if (overBudget) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Already over by '
                '${Money.format(spent - typedMinor, decimals: false)}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: MoneyColors.of(context).expense,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 14),
            NumericKeypad(onKey: (key) => setState(() => _entry.press(key))),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _save(0),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                      ),
                    ),
                    child: const Text('No budget'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving || typedMinor == 0
                        ? null
                        : () => _save(typedMinor),
                    child: Text(_saving ? 'Saving…' : 'Set budget'),
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
