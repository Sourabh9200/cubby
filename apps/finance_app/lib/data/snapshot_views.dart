import 'account_balance.dart';
import 'finance_snapshot.dart';
import 'models.dart';

/// Derived views over a snapshot.
///
/// These keep the method names the screens already used against the demo
/// repository, so swapping the data source for a real database did not require
/// rewriting a single widget.
extension SnapshotViews on FinanceSnapshot {
  /// `YYYY-MM` key for the month in progress.
  String get currentMonthKey => monthKeyOf(now);

  /// Formats a month as the `YYYY-MM` key used by the aggregates.
  static String monthKeyOf(DateTime month) =>
      '${month.year.toString().padLeft(4, '0')}-'
      '${month.month.toString().padLeft(2, '0')}';

  /// Spend per category for [month], largest first.
  ///
  /// Derived from the single month-to-category map rather than a fresh query,
  /// which is what makes it impossible for the donut and the headline total to
  /// disagree.
  List<CategorySpend> spendByCategory(DateTime month) {
    final byCategory = categorySpendByMonth[monthKeyOf(month)];
    if (byCategory == null || byCategory.isEmpty) {
      return const <CategorySpend>[];
    }
    final counts = <String, int>{};
    for (final txn in transactions) {
      if (txn.isExpense &&
          txn.date.year == month.year &&
          txn.date.month == month.month) {
        counts.update(txn.category, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    final spends = byCategory.entries
        .map(
          (entry) => CategorySpend(
            category: entry.key,
            totalMinor: entry.value,
            txnCount: counts[entry.key] ?? 0,
          ),
        )
        .toList();
    spends.sort((a, b) => b.totalMinor.compareTo(a.totalMinor));
    return spends;
  }

  /// Spending limits for the current month, most at-risk first.
  ///
  /// Sorted by fraction rather than by name, because the user should see the
  /// budget about to blow before the ones that are fine.
  ///
  /// Investing targets are deliberately excluded and returned by
  /// [investmentTargets] instead. A single "most used" ordering would put a fully
  /// funded SIP at the top beside a nearly blown grocery budget, and those two
  /// rows call for opposite reactions.
  List<BudgetStatus> budgetStatuses() {
    final spend = <String, int>{
      for (final entry in spendByCategory(currentMonth.month))
        entry.category: entry.totalMinor,
    };
    final statuses = categories
        .where((category) => category.isSpending && category.budgetMinor > 0)
        .map(
          (category) => BudgetStatus(
            category: category.name,
            spentMinor: spend[category.name] ?? 0,
            budgetMinor: category.budgetMinor,
            kind: CategoryKind.expense,
          ),
        )
        .toList();
    statuses.sort((a, b) => b.fraction.compareTo(a.fraction));
    return statuses;
  }

  /// Investing targets for the current month, closest to being met first.
  ///
  /// Sorted by progress descending — the opposite of [budgetStatuses]. For a
  /// target, being near the top is good news, so the user sees what they have
  /// already achieved before what they have not.
  List<BudgetStatus> investmentTargets() {
    final invested = <String, int>{
      for (final entry in investedByCategory(currentMonth.month))
        entry.category: entry.totalMinor,
    };
    final statuses = categories
        .where((category) => category.isInvestment && category.budgetMinor > 0)
        .map(
          (category) => BudgetStatus(
            category: category.name,
            spentMinor: invested[category.name] ?? 0,
            budgetMinor: category.budgetMinor,
            kind: CategoryKind.investment,
          ),
        )
        .toList();
    statuses.sort((a, b) => b.fraction.compareTo(a.fraction));
    return statuses;
  }

  /// Amount invested per category for [month], largest first.
  ///
  /// The investing counterpart of [spendByCategory], reading its own map so a
  /// fund contribution can never appear as a spending category.
  List<CategorySpend> investedByCategory(DateTime month) {
    final byCategory = categoryInvestmentByMonth[monthKeyOf(month)];
    if (byCategory == null || byCategory.isEmpty) {
      return const <CategorySpend>[];
    }
    final counts = <String, int>{};
    for (final txn in transactions) {
      if (txn.isInvestment &&
          txn.date.year == month.year &&
          txn.date.month == month.month) {
        counts.update(txn.category, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    final spends = byCategory.entries
        .map(
          (entry) => CategorySpend(
            category: entry.key,
            totalMinor: entry.value,
            txnCount: counts[entry.key] ?? 0,
          ),
        )
        .toList();
    spends.sort((a, b) => b.totalMinor.compareTo(a.totalMinor));
    return spends;
  }

  /// Total invested in [month], from the month aggregate.
  int investmentTotal(DateTime month) => summaryFor(month).investmentMinor;

  /// Investment entries in the current month, largest first.
  List<Transaction> investmentsThisMonth() {
    final month = currentMonth.month;
    final candidates = transactions
        .where(
          (txn) =>
              txn.isInvestment &&
              txn.date.year == month.year &&
              txn.date.month == month.month,
        )
        .toList();
    candidates.sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    return candidates;
  }

  /// Cumulative spend by day of the current month, in rupees.
  ///
  /// Index 0 is 0 so the line starts at the origin; index N is the total
  /// through day N.
  List<double> cumulativeDailySpend() {
    final daily = dailySpendByMonth[currentMonthKey] ?? const <int, int>{};
    final lastDay = now.day;
    final running = List<double>.filled(lastDay + 1, 0);
    var total = 0;
    for (var day = 1; day <= lastDay; day++) {
      total += daily[day] ?? 0;
      running[day] = total / 100;
    }
    return running;
  }

  /// Largest individual expenses this month.
  List<Transaction> topExpenses({int limit = 5}) {
    final candidates = transactions
        .where(
          (txn) =>
              txn.isExpense &&
              txn.date.year == currentMonth.month.year &&
              txn.date.month == currentMonth.month.month,
        )
        .toList();
    candidates.sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    return candidates.take(limit).toList();
  }

  /// Transactions grouped by calendar day, newest day first.
  Map<DateTime, List<Transaction>> get ledgerByDay {
    final grouped = <DateTime, List<Transaction>>{};
    for (final txn in transactions) {
      final day = DateTime(txn.date.year, txn.date.month, txn.date.day);
      grouped.putIfAbsent(day, () => <Transaction>[]).add(txn);
    }
    final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return <DateTime, List<Transaction>>{
      for (final key in keys) key: grouped[key]!,
    };
  }

  /// Accounts with a live balance.
  List<AccountBalance> get liveAccounts => accounts;

  /// How many live entries came from "Load sample data".
  int get sampleTransactionCount =>
      transactions.where((txn) => txn.isSample).length;

  /// How many live entries the user entered themselves.
  int get ownTransactionCount =>
      transactions.where((txn) => !txn.isSample).length;

  /// Categories available for spending entries.
  ///
  /// Filtered on `isSpending` rather than the negation of `isIncome`. Investment
  /// categories are also not income, so the old predicate would have placed them
  /// in the spending picker — where choosing one would file a fund contribution
  /// as an expense and quietly corrupt every spending total in the app.
  List<Category> get expenseCategories =>
      categories.where((category) => category.isSpending).toList();

  /// Categories available for investment entries.
  List<Category> get investmentCategories =>
      categories.where((category) => category.isInvestment).toList();

  /// Categories available for income entries.
  List<Category> get incomeCategories =>
      categories.where((category) => category.isIncome).toList();

  /// Finds a category by its display name.
  ///
  /// The budget aggregates carry names rather than ids because every chart needs
  /// the label; this recovers the id when a screen needs to act on the row.
  Category? categoryNamed(String name) {
    for (final category in categories) {
      if (category.name == name) {
        return category;
      }
    }
    return null;
  }
}
