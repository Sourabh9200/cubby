/// Plain result types for the aggregation queries.
///
/// Deliberately not drift-generated row classes: these are projections over
/// joins and aggregates, and naming them explicitly keeps the contract between
/// the database and the UI obvious.
library;

import 'tables.dart';

/// Spend for one category over a period, joined to its display metadata.
class CategorySpendRow {
  const CategorySpendRow({
    required this.categoryId,
    required this.categoryName,
    required this.kind,
    required this.iconKey,
    required this.colorKey,
    required this.totalMinor,
    required this.txnCount,
    required this.budgetMinor,
  });

  final String categoryId;
  final String categoryName;

  /// Carried so a caller can tell a spending total from an investing total
  /// without a second lookup.
  final CategoryKind kind;

  final String iconKey;
  final String colorKey;
  final int totalMinor;
  final int txnCount;
  final int budgetMinor;

  /// Share of [grandTotal] as a percentage, or 0 when there is no spend.
  double shareOf(int grandTotal) =>
      grandTotal == 0 ? 0 : totalMinor / grandTotal * 100;
}

/// One ledger entry with its category and account resolved to display names.
class LedgerRow {
  const LedgerRow({
    required this.id,
    required this.accountId,
    required this.accountName,
    required this.categoryId,
    required this.categoryName,
    required this.iconKey,
    required this.colorKey,
    required this.amountMinor,
    required this.currency,
    required this.direction,
    required this.occurredOn,
    required this.payee,
    required this.note,
    required this.isSample,
  });

  final String id;
  final String accountId;
  final String accountName;
  final String categoryId;
  final String categoryName;
  final String iconKey;
  final String colorKey;
  final int amountMinor;
  final String currency;
  final EntryDirection direction;

  /// Local ISO date, `YYYY-MM-DD`. Carried as a string so no UTC conversion can
  /// shift the day the user actually entered.
  final String occurredOn;

  final String payee;
  final String note;

  /// True when this row came from "Load sample data" and can be erased as a
  /// set without touching anything the user entered.
  final bool isSample;

  bool get isExpense => direction == EntryDirection.expense;
  bool get isIncome => direction == EntryDirection.income;

  /// True for money moved into an asset rather than spent.
  ///
  /// The ledger shows these without a minus prefix, because writing "-₹20,000"
  /// against a mutual fund reads as a loss when it is the opposite.
  bool get isInvestment => direction == EntryDirection.investment;

  /// The date as a local [DateTime] at midnight, for grouping and sorting.
  DateTime get date => DateTime.parse(occurredOn);
}

/// Income, expense, and investment totals for one calendar month.
class MonthTotalRow {
  const MonthTotalRow({
    required this.year,
    required this.month,
    required this.expenseMinor,
    required this.incomeMinor,
    required this.investmentMinor,
    required this.txnCount,
  });

  final int year;
  final int month;
  final int expenseMinor;
  final int incomeMinor;

  /// Money moved into investments. Tracked apart from [expenseMinor] because it
  /// is not consumption: it does not reduce what the user owns.
  final int investmentMinor;

  final int txnCount;

  DateTime get monthStart => DateTime(year, month);

  /// What was kept: income less consumption. Money invested is part of this,
  /// not subtracted from it, which is why the savings rate stays honest.
  int get netMinor => incomeMinor - expenseMinor;

  /// The actual change in cash across all accounts.
  int get cashLeftMinor => incomeMinor - expenseMinor - investmentMinor;
}

/// Spend for a single day, used by the cumulative-pace chart.
class DailyTotalRow {
  const DailyTotalRow({
    required this.monthKey,
    required this.day,
    required this.totalMinor,
  });

  /// `YYYY-MM` in local time.
  ///
  /// Carried so one read can serve every month: the pace chart follows whichever
  /// month the user is looking at, and fetching each month separately would
  /// issue a query per step of the month selector.
  final String monthKey;

  final int day;
  final int totalMinor;
}

/// One category's total within one month, for the trend chart.
class CategoryTrendPoint {
  const CategoryTrendPoint({
    required this.monthKey,
    required this.categoryId,
    required this.categoryName,
    required this.direction,
    required this.colorKey,
    required this.totalMinor,
  });

  /// `YYYY-MM`, in local time.
  final String monthKey;
  final String categoryId;
  final String categoryName;

  /// Which series this total belongs to. Carried so one query can feed both the
  /// spending trend and the investing trend, keeping the two guaranteed to come
  /// from the same read.
  final EntryDirection direction;

  final String colorKey;
  final int totalMinor;
}

/// A category with its own metadata, for pickers and management screens.
class CategoryRow {
  const CategoryRow({
    required this.id,
    required this.name,
    required this.kind,
    required this.iconKey,
    required this.colorKey,
    required this.budgetMinor,
    required this.isSystem,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final CategoryKind kind;
  final String iconKey;
  final String colorKey;
  final int budgetMinor;
  final bool isSystem;
  final int sortOrder;
}

/// A recurring rule with its category and account resolved to display names.
class RecurringRuleRow {
  const RecurringRuleRow({
    required this.id,
    required this.accountId,
    required this.accountName,
    required this.categoryId,
    required this.categoryName,
    required this.amountMinor,
    required this.direction,
    required this.payee,
    required this.note,
    required this.frequency,
    required this.dayOfMonth,
    required this.nextDueOn,
    required this.startedOn,
  });

  final String id;
  final String accountId;
  final String accountName;
  final String categoryId;
  final String categoryName;
  final int amountMinor;
  final EntryDirection direction;
  final String payee;
  final String note;
  final RecurrenceFrequency frequency;
  final int dayOfMonth;

  /// Local ISO date of the next occurrence still to post.
  final String nextDueOn;

  /// Local ISO date the rule started from.
  final String startedOn;

  /// The next occurrence, as a local [DateTime] at midnight.
  DateTime get nextDue => DateTime.parse(nextDueOn);

  bool get isExpense => direction == EntryDirection.expense;
  bool get isInvestment => direction == EntryDirection.investment;
}

/// An account with its computed balance.
class AccountRow {
  const AccountRow({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    required this.openingBalanceMinor,
    required this.netMovementMinor,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final AccountType type;
  final String currency;
  final int openingBalanceMinor;
  final int netMovementMinor;
  final int sortOrder;

  /// Opening balance plus every recorded movement.
  int get balanceMinor => openingBalanceMinor + netMovementMinor;
}
