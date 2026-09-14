import 'package:flutter/material.dart';

import '../../../core/format/amount_entry.dart';
import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/budget_pace.dart';
import '../../../data/repository_scope.dart';
import '../../../data/suggested_limit.dart';
import '../../transactions/widgets/amount_field.dart';
import '../../transactions/widgets/numeric_keypad.dart';

/// Sets or clears a category's recurring monthly budget.
///
/// Shares the amount field and numeric pad with the quick-add sheet, so entering
/// a budget feels identical to entering a transaction — and it is where the
/// deeper Tier 1 figures belong, because a limit is the decision they are about:
/// where this category's pace lands, and what the user's own history suggests.
class BudgetEditorSheet extends StatefulWidget {
  const BudgetEditorSheet({
    required this.categoryId,
    required this.categoryName,
    required this.currentBudgetMinor,
    this.spentMinor = 0,
    this.pace,
    this.suggestion,
    super.key,
  });

  final String categoryId;
  final String categoryName;
  final int currentBudgetMinor;

  /// Spend so far this month, shown so the user sets a budget with the actual
  /// number in front of them rather than from memory.
  final int spentMinor;

  /// Where this category lands at the pace it has been spent, when that takes it
  /// past its limit.
  final BudgetPace? pace;

  /// A limit derived from the user's own months, offered but never applied.
  final SuggestedLimit? suggestion;

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
            if (widget.pace case final BudgetPace pace
                when pace.isProjectedOver) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'At this pace you land at '
                '${Money.format(pace.projectedMinor, decimals: false)} · '
                '${Money.format(pace.overshootMinor, decimals: false)} over',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: MoneyColors.of(context).warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
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
            if (widget.suggestion
                case final SuggestedLimit suggestion) ...<Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  ActionChip(
                    label: Text(
                      'Use ${Money.format(suggestion.suggestedMinor, decimals: false)}'
                      ' · your median',
                    ),
                    onPressed: () => setState(
                      () => _entry.setMinor(suggestion.suggestedMinor),
                    ),
                  ),
                  if (suggestion.hasSpread)
                    ActionChip(
                      label: Text(
                        'Use ${Money.format(suggestion.p90Minor, decimals: false)}'
                        ' · your busiest',
                      ),
                      onPressed: () =>
                          setState(() => _entry.setMinor(suggestion.p90Minor)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'From the ${suggestion.monthsRecorded} months you recorded '
                '${widget.categoryName}. A figure read off your own spending is '
                'a suggestion, not a budget you agreed to — setting it is your '
                'decision.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
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
