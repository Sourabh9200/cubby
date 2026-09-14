import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/snapshot_views.dart';
import 'package:finance_db/finance_db.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

void main() {
  group('sample data isolation', () {
    test('removing sample data never touches entries I typed', () async {
      // The bug this guards: "erase sample data" used to soft-delete every row,
      // silently destroying the user's own records along with the demo set.
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      final loaded = await fixture.repository.loadSampleData();
      expect(loaded, greaterThan(50));

      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryGroceries,
        amountMinor: 12345,
        date: DateTime(2026, 9, 8),
        direction: TxDirection.expense,
        payee: 'My own coffee',
      );

      final before = await fixture.snapshot();
      expect(before.sampleTransactionCount, loaded);
      expect(before.ownTransactionCount, 1);

      await fixture.repository.eraseSampleData();

      final after = await fixture.snapshot();
      expect(after.sampleTransactionCount, 0, reason: 'sample rows should go');
      expect(
        after.ownTransactionCount,
        1,
        reason: 'the entry the user typed must survive',
      );
      expect(after.transactions.single.payee, 'My own coffee');
      expect(after.transactions.single.amountMinor, 12345);
    });

    test('erasing everything removes both kinds', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      await fixture.repository.loadSampleData();
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryGroceries,
        amountMinor: 12345,
        date: DateTime(2026, 9, 8),
        direction: TxDirection.expense,
        payee: 'My own coffee',
      );

      await fixture.repository.eraseTransactions();

      final after = await fixture.snapshot();
      expect(after.transactions, isEmpty);
      expect(after.currentMonth.expenseMinor, 0);
    });

    test('user-entered rows are never flagged as sample', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryGroceries,
        amountMinor: 500,
        date: DateTime(2026, 9, 8),
        direction: TxDirection.expense,
        payee: 'Corner shop',
        // Deliberately the same text the demo set uses. The flag is a column,
        // not a note match, so text alone cannot make a real entry deletable by
        // "remove sample data".
        note: 'Sample data',
      );

      final snapshot = await fixture.snapshot();
      expect(snapshot.sampleTransactionCount, 0);
      expect(snapshot.ownTransactionCount, 1);
    });
  });
}
