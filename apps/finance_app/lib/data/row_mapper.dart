import 'package:finance_db/finance_db.dart' as db_layer;

import '../core/theme/category_lookup.dart';
import 'account_balance.dart';
import 'finance_snapshot.dart';
import 'models.dart';
import 'snapshot_views.dart';

/// Translates storage rows into the app's own models.
///
/// Kept apart from the repository so the mapping is testable on its own, and so
/// the UI never sees a drift type. If the storage layer is ever replaced, only
/// this file changes.
abstract final class RowMapper {
  /// Converts a ledger row to the app's transaction model.
  static Transaction toTransaction(db_layer.LedgerRow row) => Transaction(
    id: row.id,
    payee: row.payee,
    category: row.categoryName,
    amountMinor: row.amountMinor,
    date: row.date,
    account: row.accountName,
    direction: switch (row.direction) {
      db_layer.EntryDirection.income => TxDirection.income,
      db_layer.EntryDirection.transfer => TxDirection.transfer,
      db_layer.EntryDirection.investment => TxDirection.investment,
      db_layer.EntryDirection.expense => TxDirection.expense,
    },
    note: row.note,
    categoryId: row.categoryId,
    accountId: row.accountId,
    isSample: row.isSample,
  );

  /// Converts a category row, resolving the stored icon key to an icon.
  static Category toCategory(db_layer.CategoryRow row) => Category(
    id: row.id,
    name: row.name,
    icon: categoryIcon(iconKey: row.iconKey, name: row.name),
    budgetMinor: row.budgetMinor,
    kind: switch (row.kind) {
      db_layer.CategoryKind.income => CategoryKind.income,
      db_layer.CategoryKind.investment => CategoryKind.investment,
      db_layer.CategoryKind.expense => CategoryKind.expense,
    },
    isSystem: row.isSystem,
  );

  /// Converts a recurring rule, resolving its category and account names.
  static RecurringRule toRecurringRule(db_layer.RecurringRuleRow row) =>
      RecurringRule(
        id: row.id,
        amountMinor: row.amountMinor,
        category: row.categoryName,
        categoryId: row.categoryId,
        account: row.accountName,
        accountId: row.accountId,
        direction: switch (row.direction) {
          db_layer.EntryDirection.income => TxDirection.income,
          db_layer.EntryDirection.transfer => TxDirection.transfer,
          db_layer.EntryDirection.investment => TxDirection.investment,
          db_layer.EntryDirection.expense => TxDirection.expense,
        },
        payee: row.payee,
        dayOfMonth: row.dayOfMonth,
        nextDueOn: row.nextDue,
      );

  /// Converts an account row.
  static AccountBalance toAccountBalance(db_layer.AccountRow row) =>
      AccountBalance(
        id: row.id,
        name: row.name,
        type: row.type.name,
        balanceMinor: row.balanceMinor,
        openingBalanceMinor: row.openingBalanceMinor,
      );

  /// Groups trend points into `YYYY-MM` to category name to total, keeping only
  /// the points whose direction is [direction].
  ///
  /// One query returns both spending and investing points. Splitting them here
  /// rather than in two queries proves the two series come from the same read,
  /// so a write landing mid-refresh cannot leave the donut and the investing
  /// card describing different revisions of the ledger.
  static Map<String, Map<String, int>> _groupTrendByDirection(
    List<db_layer.CategoryTrendPoint> points,
    db_layer.EntryDirection direction,
  ) {
    final grouped = <String, Map<String, int>>{};
    for (final point in points) {
      if (point.direction != direction) {
        continue;
      }
      grouped
          .putIfAbsent(point.monthKey, () => <String, int>{})
          .update(
            point.categoryName,
            (value) => value + point.totalMinor,
            ifAbsent: () => point.totalMinor,
          );
    }
    return grouped;
  }

  /// Spending grouped by `YYYY-MM` and category name.
  static Map<String, Map<String, int>> toCategorySpendByMonth(
    List<db_layer.CategoryTrendPoint> points,
  ) => _groupTrendByDirection(points, db_layer.EntryDirection.expense);

  /// Investing grouped by `YYYY-MM` and category name.
  static Map<String, Map<String, int>> toCategoryInvestmentByMonth(
    List<db_layer.CategoryTrendPoint> points,
  ) => _groupTrendByDirection(points, db_layer.EntryDirection.investment);

  /// Income grouped by `YYYY-MM` and category name — that is, by source.
  ///
  /// From the same single read as the spending and investing maps, so a card
  /// splitting income by source cannot add up to a figure that disagrees with
  /// the headline income total for the same month.
  static Map<String, Map<String, int>> toCategoryIncomeByMonth(
    List<db_layer.CategoryTrendPoint> points,
  ) => _groupTrendByDirection(points, db_layer.EntryDirection.income);

  /// Builds one [MonthlySummary] per month, attaching the per-category split.
  static List<MonthlySummary> toMonthSummaries({
    required List<db_layer.MonthTotalRow> totals,
    required Map<String, Map<String, int>> spendByMonth,
  }) {
    final summaries = totals.map((row) {
      final key = SnapshotViews.monthKeyOf(row.monthStart);
      return MonthlySummary(
        month: row.monthStart,
        expenseMinor: row.expenseMinor,
        incomeMinor: row.incomeMinor,
        investmentMinor: row.investmentMinor,
        byCategory: spendByMonth[key] ?? const <String, int>{},
      );
    }).toList();
    summaries.sort((a, b) => a.month.compareTo(b.month));
    return summaries;
  }

  /// Shapes the daily totals into `YYYY-MM` to day-of-month to spend.
  ///
  /// Every month, from one read: the pace chart follows whichever month the user
  /// is looking at, and a map keyed by month is what lets it move between them
  /// without another query.
  static Map<String, Map<int, int>> toDailySpendByMonth(
    List<db_layer.DailyTotalRow> rows,
  ) {
    final byMonth = <String, Map<int, int>>{};
    for (final row in rows) {
      byMonth.putIfAbsent(row.monthKey, () => <int, int>{})[row.day] =
          row.totalMinor;
    }
    return byMonth;
  }

  /// An empty snapshot, used before the first emission.
  static FinanceSnapshot emptySnapshot(DateTime now) =>
      FinanceSnapshot.empty(now);
}
