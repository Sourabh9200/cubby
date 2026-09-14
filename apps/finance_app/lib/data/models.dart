import 'package:flutter/material.dart';

/// Whether money came in, went out, or was set aside.
///
/// A transfer is neither, which is why the ledger pairs both legs with a
/// `transferId` rather than treating them as income and expense. Otherwise
/// every credit-card payment inflates both sides of the summary.
///
/// An investment is cash out but not consumption: it leaves the account and
/// stays in the user's ownership. It is a separate direction rather than an
/// expense category so the spending totals stay a measure of what was actually
/// spent.
enum TxDirection { expense, income, transfer, investment }

/// A spending category.
@immutable
class Category {
  const Category({
    required this.name,
    required this.icon,
    required this.budgetMinor,
    this.id = '',
    this.kind = CategoryKind.expense,
    this.isSystem = false,
  });

  final String name;
  final IconData icon;

  /// Monthly budget in minor units. Zero means "not budgeted".
  final int budgetMinor;

  /// Primary key, empty for a not-yet-saved draft.
  final String id;

  final CategoryKind kind;

  /// System categories ship with the app and cannot be deleted.
  final bool isSystem;

  bool get isIncome => kind == CategoryKind.income;

  /// True for a category that represents money moved into an asset.
  bool get isInvestment => kind == CategoryKind.investment;

  /// True for a category that consumes money. Everything that is not spending.
  bool get isSpending => kind == CategoryKind.expense;
}

/// Whether a category represents money going out, coming in, or being invested.
///
/// Mirrors the database enum so the UI never has to import the storage layer.
enum CategoryKind { expense, income, investment }

/// A single ledger entry.
@immutable
class Transaction {
  const Transaction({
    required this.id,
    required this.payee,
    required this.category,
    required this.amountMinor,
    required this.date,
    required this.account,
    required this.direction,
    this.note = '',
    this.categoryId = '',
    this.accountId = '',
    this.transferId,
    this.isSample = false,
  });

  final String id;
  final String payee;
  final String category;

  /// Always positive. Direction carries the sign, so a bug cannot silently
  /// flip a spend into income.
  final int amountMinor;

  final DateTime date;
  final String account;
  final TxDirection direction;
  final String note;

  /// Foreign keys, needed to edit an entry. Empty for an unsaved draft.
  final String categoryId;
  final String accountId;

  /// Links the two legs of a transfer so neither counts as spend.
  final String? transferId;

  /// True when this row was created by "Load sample data".
  ///
  /// Carried into the UI so the ledger can mark sample rows and so "erase sample
  /// data" can never be mistaken for "erase everything".
  final bool isSample;

  bool get isExpense => direction == TxDirection.expense;

  /// True for money moved into an asset rather than spent.
  bool get isInvestment => direction == TxDirection.investment;

  /// Signed amount for arithmetic.
  int get signedMinor =>
      direction == TxDirection.income ? amountMinor : -amountMinor;

  /// A copy with selected fields replaced, for edit flows.
  ///
  /// [isSample] and [transferId] are carried over rather than taken as
  /// parameters: neither is editable from the UI, and a copy that quietly
  /// dropped `isSample` would make an edited sample row look like the user's own
  /// data — and therefore unremovable by "remove sample data".
  Transaction copyWith({
    String? payee,
    String? category,
    String? categoryId,
    int? amountMinor,
    DateTime? date,
    String? account,
    String? accountId,
    TxDirection? direction,
    String? note,
  }) => Transaction(
    id: id,
    payee: payee ?? this.payee,
    category: category ?? this.category,
    amountMinor: amountMinor ?? this.amountMinor,
    date: date ?? this.date,
    account: account ?? this.account,
    direction: direction ?? this.direction,
    note: note ?? this.note,
    categoryId: categoryId ?? this.categoryId,
    accountId: accountId ?? this.accountId,
    transferId: transferId,
    isSample: isSample,
  );
}

/// Spend for one category, used by every chart.
@immutable
class CategorySpend {
  const CategorySpend({
    required this.category,
    required this.totalMinor,
    required this.txnCount,
  });

  final String category;
  final int totalMinor;
  final int txnCount;

  double shareOf(int grandTotal) =>
      grandTotal == 0 ? 0 : totalMinor / grandTotal * 100;
}

/// Totals for a stretch of time, whatever its length.
///
/// The overview shows a week, a month, a quarter or a year, and the arithmetic
/// for "what came in, what went out, what was set aside" is the same for all of
/// them. Keeping it in one type is what makes a weekly headline and a monthly
/// headline impossible to compute two different ways.
@immutable
class PeriodTotals {
  const PeriodTotals({
    required this.expenseMinor,
    required this.incomeMinor,
    this.investmentMinor = 0,
  });

  final int expenseMinor;
  final int incomeMinor;

  /// Money moved into investments. Kept apart from [expenseMinor] because it is
  /// not consumption — it does not reduce what the user owns.
  final int investmentMinor;

  /// Income less consumption: what was kept. Money invested is included here,
  /// not subtracted, which is what keeps the savings rate a measure of saving
  /// rather than of how much was moved off the current account.
  int get netMinor => incomeMinor - expenseMinor;

  /// The actual change in cash across all accounts over the period.
  int get cashLeftMinor => incomeMinor - expenseMinor - investmentMinor;

  /// Savings rate as a percentage of income, or null when there was no income.
  double? get savingsRate =>
      incomeMinor == 0 ? null : (netMinor / incomeMinor) * 100;

  /// Share of income routed into investments, or null when there was no income.
  double? get investmentRate =>
      incomeMinor == 0 ? null : (investmentMinor / incomeMinor) * 100;
}

/// One month's income, spend, and investing, for the trend charts.
///
/// A [PeriodTotals] with the month it belongs to and the spending split attached,
/// because the charts need one point per month and the overview needs one figure
/// per selected period.
@immutable
class MonthlySummary extends PeriodTotals {
  const MonthlySummary({
    required this.month,
    required this.byCategory,
    required super.expenseMinor,
    required super.incomeMinor,
    super.investmentMinor,
  });

  final DateTime month;

  final Map<String, int> byCategory;
}

/// A rule that posts an entry into the ledger every month.
///
/// A rule rather than pre-written future rows: entries dated in the future would
/// distort the month they land in from the moment the rule was made, which is the
/// opposite of what "this repeats" means. Occurrences reach the ledger when they
/// fall due, so every aggregate keeps working on ordinary entries.
@immutable
class RecurringRule {
  const RecurringRule({
    required this.id,
    required this.amountMinor,
    required this.category,
    required this.categoryId,
    required this.account,
    required this.accountId,
    required this.direction,
    required this.payee,
    required this.dayOfMonth,
    required this.nextDueOn,
  });

  final String id;

  /// Always positive. [direction] carries the sign, as everywhere else.
  final int amountMinor;

  final String category;
  final String categoryId;
  final String account;
  final String accountId;

  /// Derived from the category's kind when the rule is created, then fixed
  /// there: re-kindling a category later must not change what a rule posts.
  final TxDirection direction;

  final String payee;

  /// Day of the month the rule falls on, 1-31. A month too short for it takes
  /// its last day instead.
  final int dayOfMonth;

  /// The next occurrence still to post.
  final DateTime nextDueOn;

  bool get isExpense => direction == TxDirection.expense;

  bool get isInvestment => direction == TxDirection.investment;

  bool get isIncome => direction == TxDirection.income;
}

/// A budget with its progress, ready for a progress bar.
@immutable
class BudgetStatus {
  const BudgetStatus({
    required this.category,
    required this.spentMinor,
    required this.budgetMinor,
    this.kind = CategoryKind.expense,
  });

  final String category;
  final int spentMinor;
  final int budgetMinor;

  /// Whether this is a spending limit or an investing target.
  ///
  /// The distinction changes what "over" means: overshooting a spending limit is
  /// a problem, while overshooting an investing target is the goal.
  final CategoryKind kind;

  /// True when a limit or target has been set. The figure is optional, and zero
  /// is how a blank one is stored.
  bool get hasLimit => budgetMinor > 0;

  bool get isInvestmentTarget => kind == CategoryKind.investment;

  /// Progress toward the figure, clamped so a large overshoot cannot make a bar
  /// overflow its track.
  double get fraction =>
      budgetMinor == 0 ? 0 : (spentMinor / budgetMinor).clamp(0, 2);

  int get remainingMinor => budgetMinor - spentMinor;

  /// True when the figure has been exceeded, which for a target counts as met.
  bool get isOver => spentMinor > budgetMinor;

  bool get isMet => spentMinor >= budgetMinor;
}
