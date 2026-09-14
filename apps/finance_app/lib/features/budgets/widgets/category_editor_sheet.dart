import 'package:flutter/material.dart';

import '../../../core/format/amount_entry.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models.dart';
import '../../../data/repository_scope.dart';
import '../../transactions/widgets/amount_field.dart';
import '../../transactions/widgets/numeric_keypad.dart';

/// Creates a new category of the chosen kind.
///
/// The kind is asked for explicitly rather than inferred, because it decides how
/// every future entry against the category is treated: spent, received, or
/// invested. A category filed under the wrong kind makes the totals wrong for
/// every entry recorded against it afterwards, and a user would have no reason
/// to suspect it.
class CategoryEditorSheet extends StatefulWidget {
  const CategoryEditorSheet({
    this.initialKind = CategoryKind.expense,
    super.key,
  });

  final CategoryKind initialKind;

  @override
  State<CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends State<CategoryEditorSheet> {
  late final TextEditingController _name = TextEditingController();
  final AmountEntry _budget = AmountEntry();
  late CategoryKind _kind = widget.initialKind;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      return;
    }
    setState(() => _saving = true);
    // Captured before the await: touching a BuildContext afterwards is the
    // classic source of "use of a deactivated widget" crashes.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final repository = RepositoryScope.actions(context);

    try {
      await repository.addCategory(
        name: name,
        kind: _kind,
        // Income takes no budget. A limit on money that has not arrived would be
        // a bar on the dashboard that can never mean anything.
        budgetMinor: _kind == CategoryKind.income ? 0 : _budget.minor,
      );
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('Added $name')));
    } on Object catch (error) {
      if (mounted) {
        setState(() => _saving = false);
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not add the category: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = RepositoryScope.of(context);
    final typedName = _name.text.trim();

    // Two categories sharing a name would split one category's spend across two
    // donut slices and two budget bars, with nothing on screen to explain why
    // the totals looked halved. Cheaper to refuse it here.
    final duplicate =
        typedName.isNotEmpty &&
        snapshot.categories.any(
          (category) => category.name.toLowerCase() == typedName.toLowerCase(),
        );

    final canSave = typedName.isNotEmpty && !duplicate && !_saving;

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
            Text('New category', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Choose what kind of money movement this category records.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('Spending'),
                  selected: _kind == CategoryKind.expense,
                  onSelected: (_) =>
                      setState(() => _kind = CategoryKind.expense),
                ),
                ChoiceChip(
                  label: const Text('Investing'),
                  selected: _kind == CategoryKind.investment,
                  onSelected: (_) =>
                      setState(() => _kind = CategoryKind.investment),
                ),
                ChoiceChip(
                  label: const Text('Income'),
                  selected: _kind == CategoryKind.income,
                  onSelected: (_) =>
                      setState(() => _kind = CategoryKind.income),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'Category name',
                prefixIcon: const Icon(Icons.label_outline_rounded, size: 20),
                isDense: true,
                errorText: duplicate ? 'That name is already in use' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_kind != CategoryKind.income) ...<Widget>[
              const SizedBox(height: 14),
              Text(
                _kind == CategoryKind.investment
                    ? 'Monthly target (optional)'
                    : 'Monthly budget (optional)',
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              AmountField(typed: _budget.text),
              const SizedBox(height: 12),
              NumericKeypad(onKey: (key) => setState(() => _budget.press(key))),
            ],
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: canSave ? _save : null,
                    child: Text(_saving ? 'Adding…' : 'Add category'),
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

/// Opens the category editor.
Future<void> showCategoryEditor(
  BuildContext context, {
  CategoryKind initialKind = CategoryKind.expense,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => CategoryEditorSheet(initialKind: initialKind),
);
