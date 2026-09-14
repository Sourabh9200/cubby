import 'package:finance_app/data/drift_finance_repository.dart';
import 'package:finance_app/data/finance_snapshot.dart';
import 'package:finance_app/data/models.dart';
import 'package:finance_db/finance_db.dart';

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
