import 'package:finance_app/data/account_balance.dart';
import 'package:finance_app/data/drift_finance_repository.dart';
import 'package:finance_app/data/finance_snapshot.dart';
import 'package:finance_app/data/models.dart';
import 'package:finance_db/finance_db.dart';
import 'package:flutter/material.dart';

/// Fixed reference time, so month boundaries and "current month" assertions do
/// not depend on when the suite runs.
final DateTime testNow = DateTime(2026, 9, 13, 12);

/// A real encrypted-database stack, in memory.
///
/// Tests run against the actual drift schema rather than a hand-built fixture
/// object. That way a schema change, a migration mistake, or a broken
/// aggregation query fails the tests instead of silently shipping.
class Fixture {
  Fixture(this.db, this.repository);

  final AppDatabase db;
  final DriftFinanceRepository repository;

  Future<FinanceSnapshot> snapshot() => repository.buildSnapshot();

  Future<void> dispose() => db.close();
}

/// Builds an in-memory, unencrypted database with seeded categories.
Fixture makeFixture() {
  final db = AppDatabase.forTesting();
  return Fixture(db, DriftFinanceRepository(db: db, clock: () => testNow));
}

/// One grocery expense and one salary credit, written through the real write
/// path so the test exercises insert, read, aggregate, and render.
Future<void> seedMinimal(Fixture fixture) async {
  await fixture.repository.addTransaction(
    accountId: SeedIds.accountHdfc,
    categoryId: SeedIds.categoryGroceries,
    amountMinor: 45000,
    date: DateTime(2026, 9, 5),
    direction: TxDirection.expense,
    payee: 'BigBasket',
  );
  await fixture.repository.addTransaction(
    accountId: SeedIds.accountHdfc,
    categoryId: SeedIds.categoryIncome,
    amountMinor: 8000000,
    date: DateTime(2026, 9, 1),
    direction: TxDirection.income,
    payee: 'Salary credit',
  );
}

/// A snapshot assembled by hand, for arithmetic that needs no database.
///
/// Scheduled spend is the reason this exists: a rule's `nextDueOn` is advanced
/// by the writer against the *real* clock, so a test asserting what is due in
/// the next thirty days would pass this week and fail the next. Building the
/// rules here keeps those figures deterministic, and keeps the test about the
/// arithmetic rather than about when it ran.
FinanceSnapshot snapshotWith({
  List<Transaction> transactions = const <Transaction>[],
  List<RecurringRule> recurringRules = const <RecurringRule>[],
  List<MonthlySummary> monthlySummaries = const <MonthlySummary>[],
  List<Category> categories = const <Category>[],
  List<AccountBalance> accounts = const <AccountBalance>[],
  Map<String, Map<String, int>> categorySpendByMonth =
      const <String, Map<String, int>>{},
  DateTime? now,
}) => FinanceSnapshot(
  transactions: transactions,
  categories: categories,
  accounts: accounts,
  monthlySummaries: monthlySummaries,
  categorySpendByMonth: categorySpendByMonth,
  categoryInvestmentByMonth: const <String, Map<String, int>>{},
  categoryIncomeByMonth: const <String, Map<String, int>>{},
  dailySpendByMonth: const <String, Map<int, int>>{},
  recurringRules: recurringRules,
  now: now ?? testNow,
);

/// A rule due on [nextDueOn], for the scheduled-spend tests.
RecurringRule ruleDue({
  required DateTime nextDueOn,
  required int amountMinor,
  TxDirection direction = TxDirection.expense,
  String category = 'Rent',
  String payee = '',
  String id = 'rule-1',
  int dayOfMonth = 1,
}) => RecurringRule(
  id: id,
  amountMinor: amountMinor,
  category: category,
  categoryId: 'cat-${category.toLowerCase()}',
  account: 'HDFC Savings',
  accountId: 'acc-hdfc',
  direction: direction,
  payee: payee,
  dayOfMonth: dayOfMonth,
  nextDueOn: nextDueOn,
);

/// A hand-written expense, for the arithmetic that needs no database.
///
/// The id is derived from the date and amount so two entries in one test cannot
/// collide on a primary key.
Transaction expenseOn(
  DateTime date,
  int amountMinor, {
  String payee = 'BigBasket',
  String category = 'Groceries',
  String account = 'HDFC Savings',
  String accountId = 'acc-hdfc',
}) => Transaction(
  id: 'txn-${date.toIso8601String()}-$amountMinor-$payee',
  payee: payee,
  category: category,
  amountMinor: amountMinor,
  date: date,
  account: account,
  accountId: accountId,
  direction: TxDirection.expense,
);

/// A hand-written entry of any direction, for the net-worth replay.
Transaction movementOn(
  DateTime date,
  int amountMinor,
  TxDirection direction, {
  String payee = 'Test',
  String category = 'Misc',
  String account = 'HDFC Savings',
  String accountId = 'acc-hdfc',
}) => Transaction(
  id: '${direction.name}-${date.toIso8601String()}-$amountMinor',
  payee: payee,
  category: category,
  amountMinor: amountMinor,
  date: date,
  account: account,
  accountId: accountId,
  direction: direction,
);

/// A spending category with a monthly limit, for the pace and suggestion tests.
Category spendingCategory(String name, {int budgetMinor = 0, String id = ''}) =>
    Category(
      id: id.isEmpty ? 'cat-${name.toLowerCase()}' : id,
      name: name,
      icon: Icons.category_rounded,
      budgetMinor: budgetMinor,
    );
