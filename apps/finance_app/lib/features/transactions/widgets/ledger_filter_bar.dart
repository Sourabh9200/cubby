import 'package:flutter/material.dart';

import '../../../core/widgets/indicators.dart';

/// Which rows the ledger shows.
enum LedgerFilter {
  all('All'),
  expenses('Expenses'),
  investments('Investments'),
  income('Income');

  const LedgerFilter(this.label);

  final String label;
}

/// Search field plus filter chips for the ledger.
///
/// Extracted so the screen file stays about layout and the filter bar can be
/// reused by the trends screen, which needs the same controls over a different
/// aggregation.
class LedgerFilterBar extends StatelessWidget {
  const LedgerFilterBar({
    required this.controller,
    required this.filter,
    required this.onFilterChanged,
    required this.onQueryChanged,
    required this.matchedCount,
    super.key,
  });

  final TextEditingController controller;
  final LedgerFilter filter;
  final ValueChanged<LedgerFilter> onFilterChanged;
  final VoidCallback onQueryChanged;
  final int matchedCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: <Widget>[
          TextField(
            controller: controller,
            onChanged: (_) => onQueryChanged(),
            decoration: InputDecoration(
              hintText: 'Search payee, category, note…',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        controller.clear();
                        onQueryChanged();
                      },
                    ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final option in LedgerFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(option.label),
                      selected: filter == option,
                      onSelected: (_) => onFilterChanged(option),
                    ),
                  ),
                const SizedBox(width: 4),
                Pill(
                  text: '$matchedCount shown',
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
