import 'package:finance_db/finance_db.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  group('seeding on create', () {
    test('creates the starting accounts in display order', () async {
      final accounts = await db.watchAccounts().first;
      expect(accounts.map((a) => a.name), <String>[
        'Cash',
        'HDFC Savings',
        'ICICI Credit Card',
      ]);
      expect(accounts.first.type, AccountType.cash);
      expect(accounts.last.type, AccountType.creditCard);
    });

    test('creates the expense, investment, and income categories', () async {
      final categories = await db.watchCategories().first;
      expect(categories.length, 15);
      expect(categories.where((c) => c.kind == CategoryKind.income).length, 1);
      expect(
        categories.where((c) => c.kind == CategoryKind.expense).length,
        10,
      );
      expect(
        categories.where((c) => c.kind == CategoryKind.investment).length,
        4,
      );
    });

    test(
      'seeds investment categories so a SIP is never filed as spend',
      () async {
        // Without a seeded investment category, the only way to record a mutual
        // fund contribution would be an expense category — which would silently
        // inflate every spending total in the app.
        final categories = await db.watchCategories().first;
        final investments = categories
            .where((c) => c.kind == CategoryKind.investment)
            .toList();

        expect(investments.map((c) => c.name), contains('Mutual Funds'));
        for (final category in investments) {
          expect(category.isSystem, isTrue, reason: category.name);
          expect(category.iconKey, isNotEmpty, reason: category.name);
        }

        // One seeded target, so the investing card has something to measure
        // against on a fresh install. The rest start unbudgeted.
        expect(
          investments.firstWhere((c) => c.name == 'Mutual Funds').budgetMinor,
          2000000,
        );
        expect(
          investments.where((c) => c.budgetMinor == 0),
          hasLength(3),
          reason: 'only Mutual Funds ships with a target',
        );
      },
    );

    test('gives every expense category a budget and a system flag', () async {
      final categories = await db.watchCategories().first;
      for (final category in categories.where(
        (c) => c.kind == CategoryKind.expense,
      )) {
        expect(category.budgetMinor, greaterThan(0), reason: category.name);
        expect(category.isSystem, isTrue, reason: category.name);
        expect(category.iconKey, isNotEmpty, reason: category.name);
      }
    });

    test('the income category carries no budget', () async {
      final categories = await db.watchCategories().first;
      final income = categories.firstWhere(
        (c) => c.kind == CategoryKind.income,
      );
      expect(income.name, 'Income');
      expect(income.budgetMinor, 0);
    });

    test('writes the currency and month-start settings', () async {
      expect(await db.readSetting(SettingKeys.currency), 'INR');
      expect(await db.readSetting(SettingKeys.monthStartDay), '1');
      expect(
        await db.readSetting(SettingKeys.seedVersion),
        '$currentSeedVersion',
      );
    });

    test('seeds a fresh account with a zero net movement', () async {
      // An account with no entries must report zero rather than null, or the
      // balance line would show nothing instead of ₹0.
      final accounts = await db.watchAccounts().first;
      expect(accounts.every((a) => a.netMovementMinor == 0), isTrue);
    });
  });

  group('settings round-trip', () {
    test('writes and overwrites a value', () async {
      await db.writeSetting('test_key', 'first');
      expect(await db.readSetting('test_key'), 'first');
      await db.writeSetting('test_key', 'second');
      expect(await db.readSetting('test_key'), 'second');
    });

    test('returns null for an absent key', () async {
      expect(await db.readSetting('never_written'), isNull);
    });
  });
}
