import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/period_views.dart';
import 'package:finance_app/data/stats_period.dart';
import 'package:finance_db/finance_db.dart' hide CategoryKind;
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// Tier 0.4: top payees, and one payee's own history.
///
/// A category says *what* was bought; a payee says *where*. The column is free
/// text, so nothing here merges two spellings (C8), and an entry with no payee
/// recorded is left out rather than collected under a blank row.
void main() {
  /// BigBasket twice, Amazon once, one entry with no payee, and a salary credit.
  Future<Fixture> payeeFixture() async {
    final fixture = makeFixture();
    for (final (date, amount, payee, categoryId, direction)
        in <(DateTime, int, String, String, TxDirection)>[
          (
            DateTime(2026, 8, 20),
            25000,
            'BigBasket',
            SeedIds.categoryGroceries,
            TxDirection.expense,
          ),
          (
            DateTime(2026, 9, 1),
            8000000,
            'Salary credit',
            SeedIds.categoryIncome,
            TxDirection.income,
          ),
          (
            DateTime(2026, 9, 5),
            45000,
            'BigBasket',
            SeedIds.categoryGroceries,
            TxDirection.expense,
          ),
          (
            DateTime(2026, 9, 6),
            80000,
            'Amazon',
            SeedIds.categoryShopping,
            TxDirection.expense,
          ),
          (
            DateTime(2026, 9, 7),
            30000,
            '',
            SeedIds.categoryMisc,
            TxDirection.expense,
          ),
        ]) {
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: categoryId,
        amountMinor: amount,
        date: date,
        direction: direction,
        payee: payee,
      );
    }
    return fixture;
  }

  group('topPayeesIn', () {
    test('ranks payees by spend, with count and average', () async {
      final fixture = await payeeFixture();
      addTearDown(fixture.dispose);

      final payees = (await fixture.snapshot()).topPayeesIn(
        StatsRange.containing(StatsPeriod.year, testNow),
      );

      expect(payees.map((payee) => payee.payee), <String>[
        'Amazon',
        'BigBasket',
      ]);
      expect(payees.first.totalMinor, 80000);
      expect(payees.first.count, 1);
      expect(payees.first.averageMinor, 80000);
      expect(payees.last.totalMinor, 70000);
      expect(payees.last.count, 2);
      expect(payees.last.averageMinor, 35000);
    });

    test('leaves out income and entries with no payee', () async {
      final fixture = await payeeFixture();
      addTearDown(fixture.dispose);

      final payees = (await fixture.snapshot()).topPayeesIn(
        StatsRange.containing(StatsPeriod.year, testNow),
      );

      // A salary credit's payee is not a place, and ₹30,000 filed with no payee
      // cannot be attributed by the app.
      expect(
        payees.map((payee) => payee.payee),
        isNot(contains('Salary credit')),
      );
      expect(payees.map((payee) => payee.payee), isNot(contains('')));
    });

    test('keeps two spellings of the same shop apart', () async {
      final fixture = await payeeFixture();
      addTearDown(fixture.dispose);
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryShopping,
        amountMinor: 10000,
        date: DateTime(2026, 9, 9),
        direction: TxDirection.expense,
        payee: 'AMAZON INDIA',
      );

      final payees = (await fixture.snapshot()).topPayeesIn(
        StatsRange.containing(StatsPeriod.year, testNow),
      );

      // Merging them would invent a merchant identity the ledger never had (C8).
      expect(payees.map((payee) => payee.payee), contains('Amazon'));
      expect(payees.map((payee) => payee.payee), contains('AMAZON INDIA'));
    });

    test('honours the limit and breaks ties by name', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      for (final (payee, amount) in <(String, int)>[
        ('Zomato', 10000),
        ('Amazon', 10000),
        ('BigBasket', 5000),
      ]) {
        await fixture.repository.addTransaction(
          accountId: SeedIds.accountHdfc,
          categoryId: SeedIds.categoryGroceries,
          amountMinor: amount,
          date: DateTime(2026, 9, 6),
          direction: TxDirection.expense,
          payee: payee,
        );
      }

      final snapshot = await fixture.snapshot();
      final range = StatsRange.containing(StatsPeriod.month, testNow);

      expect(
        snapshot.topPayeesIn(range, limit: 2).map((p) => p.payee),
        <String>['Amazon', 'Zomato'],
      );
      expect(snapshot.topPayeesIn(range).map((p) => p.payee), <String>[
        'Amazon',
        'Zomato',
        'BigBasket',
      ]);
    });

    test('is scoped to the period it is given', () async {
      final fixture = await payeeFixture();
      addTearDown(fixture.dispose);

      final august = (await fixture.snapshot()).topPayeesIn(
        StatsRange.containing(StatsPeriod.month, DateTime(2026, 8, 10)),
      );

      expect(august, hasLength(1));
      expect(august.single.payee, 'BigBasket');
      expect(august.single.totalMinor, 25000);
    });
  });

  group('one payee', () {
    test('entries are that payee\'s expenses, newest first', () async {
      final fixture = await payeeFixture();
      addTearDown(fixture.dispose);

      final entries = (await fixture.snapshot()).payeeEntries('BigBasket');

      expect(entries, hasLength(2));
      expect(entries.first.date, DateTime(2026, 9, 5));
      expect(entries.last.date, DateTime(2026, 8, 20));
      // "Salary credit" and the blank payee belong to nobody here.
      expect(entries.every((txn) => txn.isExpense), isTrue);
    });

    test(
      'the series is the payee\'s spend month by month, oldest first',
      () async {
        final fixture = await payeeFixture();
        addTearDown(fixture.dispose);

        final series = (await fixture.snapshot()).payeeSeries('BigBasket');

        expect(series, hasLength(2));
        expect(series.first.month, DateTime(2026, 8));
        expect(series.first.totalMinor, 25000);
        expect(series.last.month, DateTime(2026, 9));
        expect(series.last.totalMinor, 45000);
        expect(series.last.count, 1);
      },
    );

    test('the total is the whole recorded history, matched exactly', () async {
      final fixture = await payeeFixture();
      addTearDown(fixture.dispose);

      final snapshot = await fixture.snapshot();
      final total = snapshot.payeeTotalFor('BigBasket');

      expect(total.totalMinor, 70000);
      expect(total.count, 2);
      expect(total.averageMinor, 35000);
      // Case matters, because the name is the user's own string: there is no
      // fuzzy matching to hide a typo behind (C8).
      expect(snapshot.payeeTotalFor('bigbasket').count, 0);
    });

    test('an unknown payee is empty rather than an error', () async {
      final fixture = await payeeFixture();
      addTearDown(fixture.dispose);
      final snapshot = await fixture.snapshot();

      expect(snapshot.payeeEntries('Nobody'), isEmpty);
      expect(snapshot.payeeSeries('Nobody'), isEmpty);
      expect(snapshot.payeeTotalFor('Nobody').averageMinor, 0);
    });
  });
}
