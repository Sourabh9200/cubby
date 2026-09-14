import 'package:drift/drift.dart';
import 'package:finance_db/finance_db.dart' as db_layer;
import 'package:uuid/uuid.dart';

import '../models.dart';

/// Write operations on categories.
///
/// The storage package is imported with a prefix because both layers define a
/// `CategoryKind`. Keeping them as separate types is deliberate: the UI's
/// vocabulary should not change shape just because a column does.
class CategoryWriter {
  CategoryWriter(this.db);

  final db_layer.AppDatabase db;

  static const Uuid _uuid = Uuid();

  /// Sets the recurring monthly budget for a category, in minor units.
  Future<void> setBudget({
    required String categoryId,
    required int budgetMinor,
  }) async {
    await (db.update(
      db.categories,
    )..where((c) => c.id.equals(categoryId))).write(
      db_layer.CategoriesCompanion(
        monthlyBudgetMinor: Value<int>(budgetMinor),
        updatedAt: Value<DateTime>(DateTime.now()),
      ),
    );
  }

  /// Creates a user category and returns its new id.
  ///
  /// The icon and colour default rather than being asked for, so a new
  /// category renders sensibly with zero extra decisions from the user.
  Future<String> add({
    required String name,
    required CategoryKind kind,
    required int budgetMinor,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await db
        .into(db.categories)
        .insert(
          db_layer.CategoriesCompanion.insert(
            id: id,
            name: name.trim(),
            kind: _kind(kind),
            iconKey: _iconKeyFor(kind),
            colorKey: db_layer.CategoryColors.violet,
            monthlyBudgetMinor: Value<int>(budgetMinor),
            isSystem: const Value<bool>(false),
            // Seeded categories occupy 0..110, so user categories sort after them.
            sortOrder: const Value<int>(200),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  /// Maps the UI enum onto the storage enum.
  ///
  /// An exhaustive switch rather than the `kind == income ? income : expense`
  /// ternary this replaced. That ternary silently filed every investment
  /// category as an expense, so a user adding "Mutual Funds" would have got a
  /// spending category and every contribution would have counted as spend.
  static db_layer.CategoryKind _kind(CategoryKind kind) => switch (kind) {
    CategoryKind.expense => db_layer.CategoryKind.expense,
    CategoryKind.income => db_layer.CategoryKind.income,
    CategoryKind.investment => db_layer.CategoryKind.investment,
  };

  /// A sensible default icon for a new category of [kind].
  ///
  /// Defaulting rather than asking keeps category creation to a single decision
  /// — the name — and makes a new investment category look like an investment
  /// rather than like generic spending.
  static String _iconKeyFor(CategoryKind kind) => switch (kind) {
    CategoryKind.expense => db_layer.CategoryIcons.more,
    CategoryKind.income => db_layer.CategoryIcons.income,
    CategoryKind.investment => db_layer.CategoryIcons.investments,
  };

  /// Soft-deletes a category.
  ///
  /// Throws for a system category: removing "Income" or "Misc" would leave the
  /// picker without a fallback and orphan every entry that referenced it.
  Future<void> softDelete(String categoryId) async {
    final row = await (db.select(
      db.categories,
    )..where((c) => c.id.equals(categoryId))).getSingleOrNull();
    if (row == null) {
      return;
    }
    if (row.isSystem) {
      throw StateError(
        'System categories cannot be deleted. Rename it instead.',
      );
    }
    await (db.update(
      db.categories,
    )..where((c) => c.id.equals(categoryId))).write(
      db_layer.CategoriesCompanion(
        deletedAt: Value<DateTime>(DateTime.now()),
        updatedAt: Value<DateTime>(DateTime.now()),
      ),
    );
  }
}
