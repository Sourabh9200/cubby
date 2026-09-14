import 'package:drift/drift.dart';
import 'package:finance_db/finance_db.dart';

/// Builds an entry with sensible defaults, so each test states only what it
/// actually cares about.
TransactionsCompanion entry({
  required String id,
  required String categoryId,
  required int amountMinor,
  required String occurredOn,
  EntryDirection direction = EntryDirection.expense,
  String accountId = SeedIds.accountHdfc,
  String payee = 'Test merchant',
}) {
  final parsed = DateTime.parse(occurredOn);
  return TransactionsCompanion.insert(
    id: id,
    accountId: accountId,
    categoryId: categoryId,
    amountMinor: Value<int>(amountMinor),
    currency: 'INR',
    direction: direction,
    occurredOn: occurredOn,
    occurredAt: parsed,
    payee: Value<String>(payee),
    createdAt: parsed,
    updatedAt: parsed,
  );
}

/// The window used by most aggregation tests: September 2026.
const String septemberStart = '2026-09-01';
const String octoberStart = '2026-10-01';

/// A month with two grocery entries, one dining entry, income, and one entry
/// deliberately placed outside the September window.
///
/// Totals this fixture implies for September 2026:
/// expense 180000, income 900000, groceries 150000 over two transactions.
Future<void> seedSeptember(AppDatabase db) => db.batch(
  (Batch batch) => batch
    ..insert(
      db.transactions,
      entry(
        id: 'g1',
        categoryId: SeedIds.categoryGroceries,
        amountMinor: 100000,
        occurredOn: '2026-09-02',
      ),
    )
    ..insert(
      db.transactions,
      entry(
        id: 'g2',
        categoryId: SeedIds.categoryGroceries,
        amountMinor: 50000,
        occurredOn: '2026-09-20',
      ),
    )
    ..insert(
      db.transactions,
      entry(
        id: 'd1',
        categoryId: SeedIds.categoryDining,
        amountMinor: 30000,
        occurredOn: '2026-09-11',
      ),
    )
    ..insert(
      db.transactions,
      entry(
        id: 'i1',
        categoryId: SeedIds.categoryIncome,
        amountMinor: 900000,
        occurredOn: '2026-09-01',
        direction: EntryDirection.income,
      ),
    )
    ..insert(
      db.transactions,
      entry(
        id: 'aug',
        categoryId: SeedIds.categoryGroceries,
        amountMinor: 700000,
        occurredOn: '2026-08-30',
      ),
    ),
);
