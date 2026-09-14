import 'package:flutter/material.dart';

import '../../../core/format/amount_entry.dart';
import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/chip_selector.dart';
import '../../../data/account_balance.dart';
import '../../../data/models.dart';
import '../../../data/repository_scope.dart';
import '../../../data/snapshot_views.dart';
import 'amount_field.dart';
import 'numeric_keypad.dart';

/// Sheet for recording a new entry or changing an existing one.
///
/// One sheet serves both flows. The alternative — a near-identical "edit" sheet
/// beside this one — would mean every future change to the amount pad, the
/// category picker, or the date bounds had to be made twice, and the two would
/// eventually disagree about how a transaction is captured.
class TransactionSheet extends StatefulWidget {
  const TransactionSheet({this.existing, super.key});

  /// The entry being edited, or null when recording a new one.
  final Transaction? existing;

  bool get isEditing => existing != null;

  @override
  State<TransactionSheet> createState() => _TransactionSheetState();
}

class _TransactionSheetState extends State<TransactionSheet> {
  /// Amount entry, shared with the budget editor so both pads behave
  /// identically and the parsing lives in one tested place.
  late final AmountEntry _entry = AmountEntry(
    initial: AmountEntry.toEditableText(widget.existing?.amountMinor ?? 0),
  );

  /// Free text, so a payee can be the merchant rather than the category.
  ///
  /// Left empty it falls back to the category name, which keeps one-tap entry
  /// fast while letting a user who cares name the shop.
  late final TextEditingController _payee = TextEditingController(
    text: widget.existing?.payee ?? '',
  );

  String? _categoryId;
  String? _accountId;

  /// Which group of categories is showing.
  ///
  /// Null until the first build, so an edit can open on the existing entry's
  /// kind instead of always starting on spending. Assigned once during build and
  /// owned by the kind chips afterwards.
  CategoryKind? _kind;

  bool _saving = false;

  /// The date to record against: today for a new entry, its own date when
  /// editing.
  ///
  /// Back-dating is the common case — you remember yesterday's cash purchase
  /// today — so the date is a first-class control rather than an afterthought.
  late DateTime _date = widget.existing?.date ?? DateTime.now();

  int get _amountMinor => _entry.minor;

  @override
  void dispose() {
    _payee.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    // An entry that is already future-dated — imported, or entered under a wrong
    // clock — must stay editable, or the upper bound would trap it out of reach.
    final lastDate = _date.isAfter(now) ? _date : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      // Ten years back covers any realistic back-fill. The upper bound is today,
      // because a future-dated expense silently distorts every month total it
      // lands in and reads as a bug in the charts.
      firstDate: DateTime(now.year - 10, now.month, now.day),
      lastDate: DateTime(lastDate.year, lastDate.month, lastDate.day),
      helpText: 'Date of the transaction',
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  /// Human label for the chosen date, so a back-dated entry is obvious at a
  /// glance rather than only visible by opening the picker.
  String _dateLabel() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final chosen = DateTime(_date.year, _date.month, _date.day);
    final difference = today.difference(chosen).inDays;
    return switch (difference) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => DateLabels.dayMonth(_date),
    };
  }

  Future<void> _save(Category category) async {
    final amount = _amountMinor;
    final accountId = _accountId;
    if (amount == 0 || accountId == null) {
      return;
    }
    setState(() => _saving = true);

    // Captured before the await: touching a BuildContext afterwards is the
    // classic source of "use of a deactivated widget" crashes.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final repository = RepositoryScope.actions(context);
    final typedPayee = _payee.text.trim();
    final editing = widget.existing;

    // The category decides the direction, so the user never has to state
    // something the app already knows. It is also what guarantees an investment
    // category writes an investment rather than an expense — the distinction
    // every spending total in the app depends on.
    final direction = switch (category.kind) {
      CategoryKind.income => TxDirection.income,
      CategoryKind.investment => TxDirection.investment,
      CategoryKind.expense => TxDirection.expense,
    };
    final payee = typedPayee.isEmpty ? category.name : typedPayee;

    try {
      if (editing == null) {
        await repository.addTransaction(
          accountId: accountId,
          categoryId: category.id,
          amountMinor: amount,
          date: _date,
          direction: direction,
          payee: payee,
        );
      } else {
        await repository.updateTransaction(
          id: editing.id,
          accountId: accountId,
          categoryId: category.id,
          amountMinor: amount,
          date: _date,
          direction: direction,
          payee: payee,
        );
      }
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            editing == null
                ? 'Recorded ${Money.format(amount)} under ${category.name}'
                : 'Updated ${Money.format(amount)} under ${category.name}',
          ),
        ),
      );
    } on Object catch (error) {
      // Surfaced rather than swallowed: a silent failure to save a financial
      // record is the worst possible outcome.
      if (mounted) {
        setState(() => _saving = false);
      }
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $error')));
    }
  }

  /// The chosen category, which decides the direction written on save.
  static Category? _findCategory(List<Category> options, String? id) {
    for (final category in options) {
      if (category.id == id) {
        return category;
      }
    }
    return null;
  }

  /// The kind whose group contains [id], or null when it is not present.
  static CategoryKind? _kindOf(
    Map<CategoryKind, List<Category>> groups,
    String? id,
  ) {
    if (id == null) {
      return null;
    }
    for (final entry in groups.entries) {
      if (_findCategory(entry.value, id) != null) {
        return entry.key;
      }
    }
    return null;
  }

  /// Wording for a kind chip.
  static String _kindLabel(CategoryKind kind) => switch (kind) {
    CategoryKind.expense => 'Spending',
    CategoryKind.investment => 'Investing',
    CategoryKind.income => 'Income',
  };

  /// The order kinds are offered in: money out, money set aside, money in.
  ///
  /// Spelled out rather than using `CategoryKind.values`, whose order comes from
  /// the enum declaration. That order is `expense, income, investment`, which put
  /// income between the two outflow kinds and read as though investing were a
  /// kind of income — visible on the device the moment the sheet was opened.
  static const List<CategoryKind> _kindOrder = <CategoryKind>[
    CategoryKind.expense,
    CategoryKind.investment,
    CategoryKind.income,
  ];

  /// Label for the primary action.
  ///
  /// States what is missing rather than leaving a dead button, so the reason a
  /// save is refused is visible without having to guess at it.
  String _saveLabel(bool canSave) {
    if (_saving) {
      return widget.isEditing ? 'Updating…' : 'Saving…';
    }
    if (_amountMinor == 0) {
      return 'Enter an amount';
    }
    if (!canSave) {
      return 'Pick a category';
    }
    return widget.isEditing
        ? 'Update ${Money.format(_amountMinor)}'
        : 'Save ${Money.format(_amountMinor)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = RepositoryScope.of(context);
    final accounts = snapshot.accounts;

    // Grouped in the order money actually moves: out, aside, in.
    final groups = <CategoryKind, List<Category>>{
      CategoryKind.expense: snapshot.expenseCategories,
      CategoryKind.investment: snapshot.investmentCategories,
      CategoryKind.income: snapshot.incomeCategories,
    };

    _accountId ??=
        widget.existing?.accountId ??
        (accounts.isEmpty ? null : accounts.first.id);
    _categoryId ??= widget.existing?.categoryId;

    final kind = _kind ?? _kindOf(groups, _categoryId) ?? CategoryKind.expense;
    _kind = kind;
    final showing = groups[kind]!;
    // Keep the selection inside the visible group, so switching kind cannot
    // leave a category selected that the user can no longer see — which would
    // look like the app silently ignoring their choice.
    if (_findCategory(showing, _categoryId) == null) {
      _categoryId = showing.isEmpty ? null : showing.first.id;
    }

    final selected = _findCategory(showing, _categoryId);
    final canSave =
        _amountMinor > 0 && selected != null && _accountId != null && !_saving;

    // Scrollable so the sheet cannot overflow on a short screen or with the
    // keyboard open. An overflow here would hide the Save button, which is the
    // one control the user needs.
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
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.isEditing ? 'Edit transaction' : 'Add a transaction',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.event_rounded, size: 16),
                  label: Text(_dateLabel()),
                  onPressed: _pickDate,
                  tooltip: 'Change the date',
                ),
              ],
            ),
            const SizedBox(height: 14),
            AmountField(typed: _entry.text),
            const SizedBox(height: 12),
            TextField(
              controller: _payee,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Paid to, or received from (optional)',
                prefixIcon: Icon(Icons.storefront_rounded, size: 20),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            // The kind is an explicit choice rather than a label above a long
            // chip row. Three labelled category rows pushed the keypad below the
            // fold on a short screen; one row of kind chips plus one row of
            // categories keeps the amount, the category, the pad, and the save
            // button visible at once — which is the entire point of a fast-entry
            // sheet.
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final option in _kindOrder)
                  ChoiceChip(
                    label: Text(_kindLabel(option)),
                    selected: kind == option,
                    onSelected: (_) => setState(() => _kind = option),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ChipSelector<Category>(
              options: showing,
              selected: _categoryId,
              labelOf: (category) => category.name,
              valueOf: (category) => category.id,
              onSelected: (category) =>
                  setState(() => _categoryId = category.id),
            ),
            if (accounts.length > 1) ...<Widget>[
              const SizedBox(height: 4),
              ChipSelector<AccountBalance>(
                options: accounts,
                selected: _accountId,
                height: 40,
                labelOf: (account) => account.name,
                valueOf: (account) => account.id,
                onSelected: (account) =>
                    setState(() => _accountId = account.id),
              ),
            ],
            const SizedBox(height: 12),
            NumericKeypad(onKey: (key) => setState(() => _entry.press(key))),
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
                    onPressed: canSave ? () => _save(selected) : null,
                    child: Text(_saveLabel(canSave)),
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

/// Opens the entry sheet, for a new entry or an existing one.
///
/// A single entry point for both flows, so every caller — the floating action
/// button, the ledger's detail sheet — gets the same sheet with the same date
/// bounds and the same category groups.
Future<void> showTransactionSheet(
  BuildContext context, {
  Transaction? existing,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => TransactionSheet(existing: existing),
);
