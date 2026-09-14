import 'package:finance_db/finance_db.dart' show SeedIds;

import 'account_balance.dart';
import 'finance_snapshot.dart';
import 'models.dart';
import 'period_views.dart';
import 'stats_period.dart';

/// Derived views over a snapshot.
///
/// These keep the method names the screens already used against the demo
/// repository, so swapping the data source for a real database did not require
/// rewriting a single widget.
extension SnapshotViews on FinanceSnapshot {
  /// Formats a month as the `YYYY-MM` key used by the aggregates.
  static String monthKeyOf(DateTime month) =>
      '${month.year.toString().padLeft(4, '0')}-'
      '${month.month.toString().padLeft(2, '0')}';

  /// Spend per category for [month], largest first.
  ///
  /// An adapter onto [PeriodViews.spendIn]: one implementation over different
  /// bounds, so a monthly figure and a weekly one cannot be computed two
  /// different ways.
  List<CategorySpend> spendByCategory(DateTime month) =>
      spendIn(StatsRange.containing(StatsPeriod.month, month));

  /// Spending limits for [month], most at risk first.
  ///
  /// An adapter onto [PeriodViews.budgetStatusesIn], which owns the ordering and
  /// the scaling. Investing targets are deliberately excluded and returned by
  /// [investmentTargets] instead: a single "most used" ordering would put a fully
  /// funded SIP at the top beside a nearly blown grocery budget, and those two
  /// rows call for opposite reactions.
  List<BudgetStatus> budgetStatuses({
    DateTime? month,
    bool includeUnlimited = false,
  }) => budgetStatusesIn(
    StatsRange.containing(StatsPeriod.month, month ?? currentMonth.month),
    includeUnlimited: includeUnlimited,
  );

  /// Investing targets for [month], closest to being met first.
  ///
  /// An adapter onto [PeriodViews.investmentTargetsIn]. The target is monthly, so
  /// a longer period scales it exactly as a spending limit is scaled — a quarterly
  /// target being three months of contributions, not one.
  List<BudgetStatus> investmentTargets({DateTime? month}) =>
      investmentTargetsIn(
        StatsRange.containing(StatsPeriod.month, month ?? currentMonth.month),
      );

  /// Amount invested per category for [month], largest first.
  ///
  /// The investing counterpart of [spendByCategory], and an adapter onto
  /// [PeriodViews.investedIn] for the same reason.
  List<CategorySpend> investedByCategory(DateTime month) =>
      investedIn(StatsRange.containing(StatsPeriod.month, month));

  /// Total invested in [month], from the month aggregate.
  int investmentTotal(DateTime month) => summaryFor(month).investmentMinor;

  /// True when [category] is the seeded umbrella rather than a bucket of its own.
  ///
  /// The seed ships "Investments" beside "Mutual Funds", "Stocks" and "Fixed
  /// Deposit", and the first of those is the *name of the total*, not a fourth
  /// place to file money. Keyed on the seed id because that id is a stable slug
  /// by design and survives the user renaming the row — a name check would break
  /// the moment they did.
  bool isInvestmentRollup(Category category) =>
      category.id == SeedIds.categoryInvestments;

  /// What [category]'s own row should show for [month].
  ///
  /// Every investing category reports its entries — except the umbrella, which
  /// reports the month's whole investing total. Without that, funding ₹60,000 of
  /// mutual funds leaves "Mutual Funds ₹60,000" sitting beside "Investments ₹0",
  /// which reads as the app having lost the money.
  ///
  /// This is a *display* rule only: nothing sums these rows into a headline, so
  /// the umbrella reporting the total cannot double-count it. The breakdown that
  /// [investedByCategory] feeds — where each row is a share of the total — still
  /// contains only the categories money was actually filed against.
  int investedForCategory(Category category, DateTime month) {
    if (isInvestmentRollup(category)) {
      return investmentTotal(month);
    }
    for (final entry in investedByCategory(month)) {
      if (entry.category == category.name) {
        return entry.totalMinor;
      }
    }
    return 0;
  }

  /// Income received per source in [month], largest first.
  ///
  /// An income category *is* a cash flow — salary, freelance work, interest, rent
  /// received — so this answers "which streams carried this month", which a single
  /// income total cannot. An adapter onto [PeriodViews.incomeIn].
  List<CategorySpend> incomeBySource(DateTime month) =>
      incomeIn(StatsRange.containing(StatsPeriod.month, month));

  /// Total income received in [month], from the month aggregate.
  int incomeTotal(DateTime month) => summaryFor(month).incomeMinor;

  /// Cumulative spend by day of [month], in rupees.
  ///
  /// An adapter onto [PeriodViews.cumulativeSpendIn]: index 0 is the origin and
  /// index N is the total through day N. A month still in progress stops at today
  /// rather than drawing a flat line to the end of a month that has not happened.
  List<double> cumulativeDailySpend(DateTime month) =>
      cumulativeSpendIn(StatsRange.containing(StatsPeriod.month, month));

  /// Largest individual expenses in [month].
  ///
  /// An adapter onto [PeriodViews.topExpensesIn].
  List<Transaction> topExpenses({int limit = 5, DateTime? month}) =>
      topExpensesIn(
        StatsRange.containing(StatsPeriod.month, month ?? currentMonth.month),
        limit: limit,
      );

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
