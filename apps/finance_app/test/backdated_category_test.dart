import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/snapshot_analytics.dart';
import 'package:finance_app/data/snapshot_views.dart';
import 'package:finance_db/finance_db.dart' hide CategoryKind;
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// The reported case: a category created by hand, with amounts added in a month
/// that is no longer the current one.
///
/// Every aggregate on the overview and trends used to be locked to the month in
/// progress, so back-dated entries — the normal case while setting the app up —
/// showed up in the ledger and in nothing else. The category was among August's
/// largest single expenses and appeared nowhere: not in biggest hits, not in the
/// budget card, not in the movement list.
void main() {
  /// "Gifting", spending with no limit set, spent from in August and September.
  Future<Fixture> giftFixture() async {
    final fixture = makeFixture();
    await fixture.repository.addCategory(
      name: 'Gifting',
      kind: CategoryKind.expense,
      budgetMinor: 0,
    );
    final gifting = (await fixture.snapshot()).categoryNamed('Gifting')!;
    await fixture.repository.addTransaction(
      accountId: SeedIds.accountHdfc,
      categoryId: gifting.id,
      amountMinor: 500000,
      date: DateTime(2026, 8, 20),
      direction: TxDirection.expense,
      payee: 'Wedding gift',
    );
    await fixture.repository.addTransaction(
      accountId: SeedIds.accountHdfc,
      categoryId: gifting.id,
      amountMinor: 100000,
      date: DateTime(2026, 9, 2),
      direction: TxDirection.expense,
      payee: 'Birthday gift',
    );
    return fixture;
  }

  test('a past month can be asked for, and holds the back-dated entry', () async {
    final fixture = await giftFixture();
    addTearDown(fixture.dispose);
    final snapshot = await fixture.snapshot();

    final august = snapshot.topExpenses(month: DateTime(2026, 8));

    // The ₹5,000 gift is August's largest single expense, and it is bigger than
    // anything in September — which is exactly why its absence looked like a bug
    // rather than a date filter.
    expect(august.single.category, 'Gifting');
    expect(august.single.amountMinor, 500000);
    expect(snapshot.summaryFor(DateTime(2026, 8)).expenseMinor, 500000);

    // The current month is unaffected by asking about another one.
    expect(snapshot.topExpenses().single.amountMinor, 100000);
  });

  test(
    'movement follows the selected month, empty where there is none',
    () async {
      final fixture = await giftFixture();
      addTearDown(fixture.dispose);
      final snapshot = await fixture.snapshot();

      expect(
        snapshot.categoryMovement(DateTime(2026, 8)).map((m) => m.category),
        contains('Gifting'),
      );
      expect(
        snapshot.categoryMovement(DateTime(2026, 9)).map((m) => m.category),
        contains('Gifting'),
      );
      // A month with nothing in it cannot report a movement.
      expect(snapshot.categoryMovement(DateTime(2026, 7)), isEmpty);
    },
  );

  test('a category with no limit still appears once spent from', () async {
    final fixture = await giftFixture();
    addTearDown(fixture.dispose);
    final snapshot = await fixture.snapshot();

    // The limit is optional in the category editor, so a category can be spent
    // from without ever having one. Hidden entirely, "no limit set" is
    // indistinguishable from "not tracked".
    expect(
      snapshot.budgetStatuses().map((b) => b.category),
      isNot(contains('Gifting')),
    );

    final august = snapshot.budgetStatuses(
      month: DateTime(2026, 8),
      includeUnlimited: true,
    );
    final row = august.firstWhere((status) => status.category == 'Gifting');
    expect(row.hasLimit, isFalse);
    expect(row.spentMinor, 500000);

    // First of all: it is spend nothing is watching, and every seeded category
    // beside it is a limit nothing has touched.
    expect(august.first.category, 'Gifting');
  });

  test(
    'a category with neither limit nor spend stays out of the card',
    () async {
      final fixture = await giftFixture();
      addTearDown(fixture.dispose);

      await fixture.repository.addCategory(
        name: 'Never used',
        kind: CategoryKind.expense,
        budgetMinor: 0,
      );

      final statuses = (await fixture.snapshot()).budgetStatuses(
        month: DateTime(2026, 8),
        includeUnlimited: true,
      );
      // Including unbudgeted categories must not turn the card into a list of
      // every category that exists.
      expect(
        statuses.map((status) => status.category),
        isNot(contains('Never used')),
      );
    },
  );

  test('a finished month is compared whole, the month in progress scaled', () async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);

    for (final (payee, month, amount) in <(String, DateTime, int)>[
      ('july', DateTime(2026, 7, 5), 100000),
      ('august', DateTime(2026, 8, 5), 500000),
      ('september', DateTime(2026, 9, 5), 100000),
    ]) {
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryGroceries,
        amountMinor: amount,
        date: month,
        direction: TxDirection.expense,
        payee: payee,
      );
    }
    final snapshot = await fixture.snapshot();

    // August is over, so it is compared against July as it stands: +400%.
    expect(snapshot.expenseChangeFor(DateTime(2026, 8)), closeTo(400, 0.01));

    // September is 13 days old, so August is scaled to 13 of its 30 days before
    // comparing. Against a whole August, a part-month would read as a large
    // saving every single time.
    final scaled = 500000 * (13 / 30);
    expect(
      snapshot.expenseChangeFor(DateTime(2026, 9)),
      closeTo((100000 - scaled) / scaled * 100, 0.01),
    );
  });
}
