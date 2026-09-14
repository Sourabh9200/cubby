import 'account_balance.dart';
import 'models.dart';

/// An immutable view of everything the UI needs, rebuilt whenever the database
/// emits.
///
/// One aggregate rather than many independent streams: the dashboard shows a
/// total, a donut, a pace curve, and budget bars that must all agree with each
/// other. Deriving them from one consistent snapshot makes disagreement
/// structurally impossible, which is exactly the class of bug that destroys
/// trust in a finance app.
class FinanceSnapshot {
  const FinanceSnapshot({
    required this.transactions,
    required this.categories,
    required this.accounts,
    required this.monthlySummaries,
    required this.categorySpendByMonth,
    required this.categoryInvestmentByMonth,
    required this.dailySpendByMonth,
    required this.now,
  });

  /// Every live entry, newest first.
  final List<Transaction> transactions;

  /// Every live category.
  final List<Category> categories;

  /// Every live account.
  final List<AccountBalance> accounts;

  /// One entry per month that has data, oldest first.
  final List<MonthlySummary> monthlySummaries;

  /// `YYYY-MM` to category name to spend.
  ///
  /// Spending only. Investing totals live in [categoryInvestmentByMonth], so
  /// the donut, the budget bars, and the category averages cannot accidentally
  /// count a mutual fund contribution as consumption.
  final Map<String, Map<String, int>> categorySpendByMonth;

  /// `YYYY-MM` to category name to amount invested.
  ///
  /// A separate map rather than a flag inside the spending one, because every
  /// consumer of the spending map would otherwise have to remember to filter.
  final Map<String, Map<String, int>> categoryInvestmentByMonth;

  /// `YYYY-MM` to day-of-month to spend.
  final Map<String, Map<int, int>> dailySpendByMonth;

  /// Reference time. Injected rather than read from the clock, so tests and
  /// month boundaries are deterministic.
  final DateTime now;

  /// A snapshot with no data, used before the first database emission.
  static FinanceSnapshot empty(DateTime now) => FinanceSnapshot(
    transactions: const <Transaction>[],
    categories: const <Category>[],
    accounts: const <AccountBalance>[],
    monthlySummaries: const <MonthlySummary>[],
    categorySpendByMonth: const <String, Map<String, int>>{},
    categoryInvestmentByMonth: const <String, Map<String, int>>{},
    dailySpendByMonth: const <String, Map<int, int>>{},
    now: now,
  );

  /// True when there is nothing recorded at all.
  bool get isEmpty => transactions.isEmpty;

  /// The month in progress.
  ///
  /// Returns a zeroed summary rather than null when the ledger is empty, so
  /// every screen can render without a null check — and a brand-new install
  /// shows ₹0 rather than a crash or a blank panel.
  MonthlySummary get currentMonth => summaryFor(now);

  /// A summary for [month], zeroed when that month has no activity.
  MonthlySummary summaryFor(DateTime month) {
    for (final summary in monthlySummaries) {
      if (summary.month.year == month.year &&
          summary.month.month == month.month) {
        return summary;
      }
    }
    return MonthlySummary(
      month: DateTime(month.year, month.month),
      expenseMinor: 0,
      incomeMinor: 0,
      byCategory: const <String, int>{},
    );
  }

  /// The month before [currentMonth], or null when there is no history.
  MonthlySummary? get previousMonth {
    final current = currentMonth.month;
    MonthlySummary? candidate;
    for (final summary in monthlySummaries) {
      if (summary.month.isBefore(current)) {
        candidate = summary;
      }
    }
    return candidate;
  }
}
