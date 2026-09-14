import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/indicators.dart';
import '../../data/models.dart';
import '../../data/repository_scope.dart';
import 'widgets/day_section.dart';
import 'widgets/ledger_filter_bar.dart';

/// The full ledger, grouped by day.
///
/// Grouping by day with a subtotal is how bank statements read, and it is what
/// makes a long list scannable. Search matches payee, category, account, and
/// note, because a user hunting a transaction may remember any of those.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final TextEditingController _search = TextEditingController();
  LedgerFilter _filter = LedgerFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Transaction txn) {
    final inFilter = switch (_filter) {
      LedgerFilter.all => true,
      LedgerFilter.expenses => txn.direction == TxDirection.expense,
      LedgerFilter.investments => txn.isInvestment,
      LedgerFilter.income => txn.direction == TxDirection.income,
    };
    if (!inFilter) {
      return false;
    }
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    return txn.payee.toLowerCase().contains(query) ||
        txn.category.toLowerCase().contains(query) ||
        txn.account.toLowerCase().contains(query) ||
        txn.note.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final repository = RepositoryScope.of(context);
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);

    final filtered = repository.transactions.where(_matches).toList();
    final grouped = <DateTime, List<Transaction>>{};
    for (final txn in filtered) {
      final day = DateTime(txn.date.year, txn.date.month, txn.date.day);
      grouped.putIfAbsent(day, () => <Transaction>[]).add(txn);
    }
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    // Outflow means cash that actually left, so it includes money moved into
    // investments. Excluding them would report ₹0 for a month in which the user
    // invested their whole surplus, which reads as a bug.
    final totalOut = filtered
        .where((txn) => txn.isExpense || txn.isInvestment)
        .fold(0, (sum, txn) => sum + txn.amountMinor);

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          title: const Text('Transactions'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(110),
            child: LedgerFilterBar(
              controller: _search,
              filter: _filter,
              matchedCount: filtered.length,
              onFilterChanged: (value) => setState(() => _filter = value),
              onQueryChanged: () => setState(() {}),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Row(
              children: <Widget>[
                Text(
                  'Outflow in view',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  Money.format(totalOut, decimals: false),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: money.expense,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (days.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Nothing matches',
              message: 'Try a different search term, or clear the filter.',
            ),
          )
        else
          SliverList.builder(
            itemCount: days.length,
            itemBuilder: (context, index) {
              final day = days[index];
              final items = grouped[day]!;
              final dayTotal = items
                  .where((txn) => txn.isExpense || txn.isInvestment)
                  .fold(0, (sum, txn) => sum + txn.amountMinor);
              return DaySection(
                date: day,
                items: items,
                dayTotalMinor: dayTotal,
                referenceNow: repository.now,
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}
