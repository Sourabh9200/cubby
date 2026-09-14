import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/snapshot_views.dart';
import 'package:finance_app/features/dashboard/widgets/category_donut.dart';
import 'package:finance_db/finance_db.dart' hide CategoryKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// Every category the user has spent from must be reachable from the overview.
///
/// Two caps could still hide one: the budget card showed five rows and ranked
/// categories with no limit last, and the donut merged everything past seven
/// slices into "Other" *and* only listed the merged set — so a small category
/// was absent from the screen entirely.
void main() {
  test('the budget card ranks risk, then unwatched spend, then untouched limits', () async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);

    await fixture.repository.addCategory(
      name: 'Gifting',
      kind: CategoryKind.expense,
      budgetMinor: 0,
    );
    final gifting = (await fixture.snapshot()).categoryNamed('Gifting')!;
    await fixture.repository.addTransaction(
      accountId: SeedIds.accountHdfc,
      categoryId: gifting.id,
      amountMinor: 400000,
      date: DateTime(2026, 9, 4),
      direction: TxDirection.expense,
      payee: 'Gift',
    );
    // Groceries carries the seeded ₹9,000 limit; this takes it to 94%.
    await fixture.repository.addTransaction(
      accountId: SeedIds.accountHdfc,
      categoryId: SeedIds.categoryGroceries,
      amountMinor: 850000,
      date: DateTime(2026, 9, 5),
      direction: TxDirection.expense,
      payee: 'BigBasket',
    );

    final rows = (await fixture.snapshot()).budgetStatuses(
      includeUnlimited: true,
    );

    // A limit being spent against is what the card exists for.
    expect(rows.first.category, 'Groceries');
    // Then money leaving that no bar is watching — above the untouched limits,
    // so a long list of them cannot push it off the end of the card.
    expect(rows[1].category, 'Gifting');
    expect(rows[1].hasLimit, isFalse);
    // Everything after that is a seeded limit with nothing against it.
    expect(
      rows.skip(2).every((row) => row.hasLimit && row.spentMinor == 0),
      isTrue,
    );
  });

  testWidgets('the donut legend lists every category, past the ring cap', (
    tester,
  ) async {
    final spends = <CategorySpend>[
      for (var index = 0; index < 9; index++)
        CategorySpend(
          category: 'Category $index',
          totalMinor: (9 - index) * 10000,
          txnCount: 1,
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: CategoryDonut(spends: spends)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final spend in spends) {
      expect(
        find.text(spend.category),
        findsOneWidget,
        reason: '${spend.category} is missing from the legend',
      );
    }
    // The ring still merges the tail, and the card says so rather than leaving
    // the reader to wonder why an arc is unaccounted for.
    expect(find.textContaining('as one "Other" slice'), findsOneWidget);
    // No bare "Other" row any more: every category is named individually.
    expect(find.text('Other'), findsNothing);
  });
}
