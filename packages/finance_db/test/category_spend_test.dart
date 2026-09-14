import 'package:finance_db/finance_db.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  group('category spend', () {
    setUp(() => seedSeptember(db));

    test('sums only expenses inside the window', () async {
      final spend = await db
          .watchCategorySpend(fromIso: septemberStart, toIso: octoberStart)
          .first;

      expect(spend.map((s) => s.categoryName), <String>[
        'Groceries',
        'Dining Out',
      ]);
      expect(spend.first.totalMinor, 150000);
      expect(spend.first.txnCount, 2);
      expect(spend.last.totalMinor, 30000);
    });

    test('never counts income as spend', () async {
      final spend = await db
          .watchCategorySpend(fromIso: septemberStart, toIso: octoberStart)
          .first;
      expect(spend.any((s) => s.categoryName == 'Income'), isFalse);
    });

    test('excludes untouched categories rather than zero-filling', () async {
      final spend = await db
          .watchCategorySpend(fromIso: septemberStart, toIso: octoberStart)
          .first;
      expect(spend.every((s) => s.totalMinor > 0), isTrue);
      expect(spend.any((s) => s.categoryName == 'Rent'), isFalse);
    });

    test('shares sum to one hundred percent', () async {
      final spend = await db
          .watchCategorySpend(fromIso: septemberStart, toIso: octoberStart)
          .first;
      final total = spend.fold(0, (sum, s) => sum + s.totalMinor);
      final shares = spend.fold<double>(0, (sum, s) => sum + s.shareOf(total));
      expect(shares, closeTo(100, 0.001));
    });

    test('carries the category budget through the join', () async {
      final spend = await db
          .watchCategorySpend(fromIso: septemberStart, toIso: octoberStart)
          .first;
      expect(spend.first.budgetMinor, 900000); // The seeded ₹9,000 budget.
    });

    test('is ordered by spend, largest first', () async {
      final spend = await db
          .watchCategorySpend(fromIso: septemberStart, toIso: octoberStart)
          .first;
      for (var i = 1; i < spend.length; i++) {
        expect(
          spend[i - 1].totalMinor,
          greaterThanOrEqualTo(spend[i].totalMinor),
        );
      }
    });

    test('an empty window returns an empty list, not an error', () async {
      final spend = await db
          .watchCategorySpend(fromIso: '2020-01-01', toIso: '2020-02-01')
          .first;
      expect(spend, isEmpty);
    });
  });

  group('category trend', () {
    test('returns one point per category per month', () async {
      await seedSeptember(db);
      await db
          .into(db.transactions)
          .insert(
            entry(
              id: 'oct',
              categoryId: SeedIds.categoryGroceries,
              amountMinor: 120000,
              occurredOn: '2026-10-05',
            ),
          );

      final groceries = (await db.watchCategoryTrend().first)
          .where((p) => p.categoryName == 'Groceries')
          .toList();
      expect(groceries.map((p) => p.monthKey), <String>[
        '2026-08',
        '2026-09',
        '2026-10',
      ]);
      expect(groceries.last.totalMinor, 120000);
    });

    test(
      'carries id and colour key for consistent chart legend colours',
      () async {
        await seedSeptember(db);
        final point = (await db.watchCategoryTrend().first).firstWhere(
          (p) => p.categoryName == 'Groceries',
        );
        expect(point.categoryId, SeedIds.categoryGroceries);
        expect(point.colorKey, isNotEmpty);
      },
    );
  });
}
