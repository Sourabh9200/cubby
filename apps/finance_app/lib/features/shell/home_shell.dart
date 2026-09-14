import 'package:flutter/material.dart';

import '../../data/month_scope.dart';
import '../../data/repository_scope.dart';
import '../assistant/assistant_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../settings/settings_screen.dart';
import '../transactions/transactions_screen.dart';
import '../transactions/widgets/transaction_sheet.dart';
import '../trends/trends_screen.dart';

/// Bottom-navigation shell.
///
/// Uses an [IndexedStack] rather than rebuilding on each tab change, so scroll
/// positions and the ledger's search term survive navigation. Losing a filter
/// because you glanced at another tab is the kind of small friction that makes
/// an app feel cheap.
///
/// It also holds the month the aggregate screens are showing, for the same
/// reason: a month that reset on every tab change would be worse than no month
/// selector at all.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// The month being shown, or null while the user has not moved off the month
  /// in progress.
  DateTime? _month;

  static const List<Widget> _screens = <Widget>[
    DashboardScreen(),
    TransactionsScreen(),
    TrendsScreen(),
    AssistantScreen(),
    SettingsScreen(),
  ];

  static const List<NavigationDestination> _destinations =
      <NavigationDestination>[
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard_rounded),
          label: 'Overview',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long_rounded),
          label: 'Ledger',
        ),
        NavigationDestination(
          icon: Icon(Icons.insights_outlined),
          selectedIcon: Icon(Icons.insights_rounded),
          label: 'Trends',
        ),
        NavigationDestination(
          icon: Icon(Icons.auto_awesome_outlined),
          selectedIcon: Icon(Icons.auto_awesome_rounded),
          label: 'Ask',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: 'Settings',
        ),
      ];

  void _quickAdd() {
    showTransactionSheet(context);
  }

  /// The month to show, clamped to the range that actually has data.
  ///
  /// Clamped during build rather than in `setState` so that erasing the last
  /// entry of a month cannot leave the screens pointed at a month that has since
  /// emptied — the data range shrinks under the selection, and every figure
  /// would read ₹0 with nothing on screen to explain why.
  DateTime _resolveMonth({
    required DateTime? earliest,
    required DateTime latest,
  }) {
    final selected = _month ?? latest;
    if (selected.isAfter(latest)) {
      return latest;
    }
    if (earliest != null && selected.isBefore(earliest)) {
      return earliest;
    }
    return selected;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = RepositoryScope.of(context);
    final now = snapshot.now;
    // The range the selector may move within: the month in progress is the
    // newest thing that can have data, and the oldest is whichever month has
    // some. `monthlySummaries` is ordered oldest first.
    final latest = DateTime(now.year, now.month);
    final earliest = snapshot.monthlySummaries.isEmpty
        ? null
        : snapshot.monthlySummaries.first.month;

    return Scaffold(
      body: MonthScope(
        month: _resolveMonth(earliest: earliest, latest: latest),
        earliest: earliest,
        latest: latest,
        onChanged: (value) => setState(() => _month = value),
        child: IndexedStack(index: _index, children: _screens),
      ),
      floatingActionButton: _index <= 1
          ? FloatingActionButton(
              onPressed: _quickAdd,
              tooltip: 'Add a transaction',
              child: const Icon(Icons.add_rounded),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: _destinations,
      ),
    );
  }
}
