import 'package:drift/drift.dart' show Value;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:finance_db/finance_db.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v1.dart' as v1;

/// Migration tests.
///
/// These matter more than they look. A migration that silently drops a column,
/// or one that mislabels existing rows, corrupts a user's financial history
/// with no error and no way back. The schema snapshots in `drift_schemas/` are
/// committed precisely so this is verifiable on every change: bump the schema,
/// dump it, and these tests tell you whether the upgrade path still holds.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v1 to v2 leaves the schema valid', () async {
    final schema = await verifier.schemaAt(1);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 2);
    await db.close();
  });

  test('a fresh install is created directly at v2', () async {
    final db = AppDatabase.forTesting();
    expect(db.schemaVersion, 2);
    // Seeding still works at the current version: 10 expense categories, 4
    // investment categories, and Income.
    expect(await db.watchCategories().first, hasLength(15));
    await db.close();
  });

  test('an install predating investments gains them on open', () async {
    // Adding a value to an enum needs no schema change — drift stores textEnum
    // columns as plain TEXT with no CHECK constraint — so a v1 database needs no
    // migration to hold an investment. Rows are the problem: a database seeded
    // before the kind existed has no investment category, and a schema migration
    // cannot add one. The seed version is what closes that gap.
    final schema = await verifier.schemaAt(1);
    final stamp = DateTime(2026, 9, 5).millisecondsSinceEpoch ~/ 1000;

    final oldDb = v1.DatabaseAtV1(schema.newConnection());
    await oldDb
        .into(oldDb.categories)
        .insert(
          v1.CategoriesCompanion.insert(
            id: 'legacy-groceries',
            name: 'Groceries',
            kind: 'expense',
            iconKey: 'basket',
            colorKey: 'emerald',
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    await oldDb
        .into(oldDb.settingsEntries)
        .insert(
          v1.SettingsEntriesCompanion.insert(
            key: SettingKeys.seedVersion,
            value: '1',
            updatedAt: stamp,
          ),
        );
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    final after = await db.watchCategories().first;

    expect(
      after.where((c) => c.kind == CategoryKind.investment).map((c) => c.name),
      containsAll(<String>['Mutual Funds', 'Stocks']),
    );
    // The user's own category survives the top-up.
    expect(after.any((c) => c.name == 'Groceries'), isTrue);
    // And the recorded version moves forward, so the top-up stops running.
    expect(await db.readSetting(SettingKeys.seedVersion), '2');

    await db.close();
  });

  test('the seed top-up never overwrites a category the user changed', () async {
    // The top-up runs on every open. If it wrote the seeded values instead of
    // skipping rows that already exist, a renamed category and a changed budget
    // would be silently reset on every launch — a bug that only appears once
    // someone has data they care about.
    final db = AppDatabase.forTesting();
    final mutualFunds = (await db.watchCategories().first).firstWhere(
      (category) => category.name == 'Mutual Funds',
    );
    await (db.update(
      db.categories,
    )..where((c) => c.id.equals(mutualFunds.id))).write(
      const CategoriesCompanion(
        name: Value<String>('Index Funds'),
        monthlyBudgetMinor: Value<int>(500000),
      ),
    );

    await seedMissingDefaults(db);
    await seedMissingDefaults(db);

    final after = await db.watchCategories().first;
    final renamed = after.firstWhere((c) => c.id == mutualFunds.id);
    expect(renamed.name, 'Index Funds');
    expect(renamed.budgetMinor, 500000);
    // It did not duplicate anything on the way through either.
    expect(after.where((c) => c.id == mutualFunds.id), hasLength(1));
    expect(after, hasLength(15));

    await db.close();
  });

  test('migration preserves rows and defaults is_sample to false', () async {
    final schema = await verifier.schemaAt(1);
    final stampDate = DateTime(2026, 9, 5);
    // The generated v1 schema exposes drift's raw storage form, so its date
    // columns take unix seconds rather than DateTime. The app's own companion
    // takes DateTime. Both are needed in this one test.
    final stamp = stampDate.millisecondsSinceEpoch ~/ 1000;

    // Insert as version 1 saw the world, on its own independent connection.
    final oldDb = v1.DatabaseAtV1(schema.newConnection());
    await oldDb
        .into(oldDb.accounts)
        .insert(
          v1.AccountsCompanion.insert(
            id: 'legacy-account',
            name: 'HDFC Savings',
            type: 'bank',
            currency: 'INR',
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    await oldDb
        .into(oldDb.categories)
        .insert(
          v1.CategoriesCompanion.insert(
            id: 'legacy-category',
            name: 'Groceries',
            kind: 'expense',
            iconKey: 'basket',
            colorKey: 'emerald',
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    await oldDb
        .into(oldDb.transactions)
        .insert(
          v1.TransactionsCompanion.insert(
            id: 'legacy-entry',
            accountId: 'legacy-account',
            categoryId: 'legacy-category',
            currency: 'INR',
            direction: 'expense',
            occurredOn: '2026-09-05',
            occurredAt: stamp,
            amountMinor: const Value<int>(45000),
            payee: const Value<String>('BigBasket'),
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    // A row the old sample loader wrote, identifiable only by its note.
    await oldDb
        .into(oldDb.transactions)
        .insert(
          v1.TransactionsCompanion.insert(
            id: 'legacy-sample',
            accountId: 'legacy-account',
            categoryId: 'legacy-category',
            currency: 'INR',
            direction: 'expense',
            occurredOn: '2026-08-11',
            occurredAt: stamp,
            amountMinor: const Value<int>(9900),
            payee: const Value<String>('Swiggy'),
            note: const Value<String>('Sample data'),
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    await oldDb.close();

    // Run the migration on the real database class from the app.
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 2);

    final rows = await db.watchLedger().first;
    expect(rows, hasLength(2), reason: 'both entries must survive');

    final userRow = rows.firstWhere((entry) => entry.id == 'legacy-entry');
    expect(userRow.amountMinor, 45000);
    expect(userRow.payee, 'BigBasket');
    expect(userRow.occurredOn, '2026-09-05');
    expect(userRow.categoryName, 'Groceries');
    expect(userRow.accountName, 'HDFC Savings');

    // The assertion that matters most. Everything written before `is_sample`
    // existed belongs to the user, so it must not be flagged as sample —
    // otherwise "remove sample data" becomes a button that deletes real records.
    expect(userRow.isSample, isFalse);

    // And the backfill must still recognize rows the old sample loader wrote,
    // so the feature works for installs that predate the column.
    final sampleRow = rows.firstWhere((entry) => entry.id == 'legacy-sample');
    expect(sampleRow.isSample, isTrue);

    // The new column must be usable for writes afterwards.
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: 'new-sample',
            accountId: 'legacy-account',
            categoryId: 'legacy-category',
            currency: 'INR',
            direction: EntryDirection.expense,
            occurredOn: '2026-09-06',
            occurredAt: stampDate,
            amountMinor: const Value<int>(1000),
            isSample: const Value<bool>(true),
            createdAt: stampDate,
            updatedAt: stampDate,
          ),
        );

    final after = await db.watchLedger().first;
    expect(after.where((entry) => entry.isSample), hasLength(2));
    expect(after.where((entry) => !entry.isSample), hasLength(1));

    await db.close();
  });
}
