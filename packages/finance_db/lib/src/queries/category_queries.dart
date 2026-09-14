import 'package:drift/drift.dart';

import '../database.dart';
import '../query_rows.dart';
import '../tables.dart';
import 'row_parsing.dart';

/// Category-level aggregates.
///
/// Summing happens in SQL, against an index. Pulling a growing ledger into Dart
/// to total it is what makes a finance app feel slow after a couple of years of
/// real use.
///
/// Each method returns a `Stream` and declares `readsFrom`, so drift
/// invalidates it automatically when the underlying tables change. That is what
/// lets the UI refresh after a write with no manual plumbing.
extension CategoryQueries on AppDatabase {
  /// Totals per category of [kind] over the half-open window `[fromIso, toIso)`.
  ///
  /// Categories with no activity are excluded rather than returned as zeroes,
  /// so callers never have to filter them out.
  ///
  /// [kind] is a parameter rather than being fixed to expenses, because the same
  /// shape of answer is wanted for investing — "how much went into each fund
  /// this month" — and having two near-identical queries would let the two
  /// drift apart in their handling of soft deletes and date bounds.
  Stream<List<CategorySpendRow>> watchCategorySpend({
    required String fromIso,
    required String toIso,
    CategoryKind kind = CategoryKind.expense,
  }) {
    return customSelect(
      '''
      SELECT c.id                   AS categoryId,
             c.name                 AS categoryName,
             c.kind                 AS kind,
             c.icon_key             AS iconKey,
             c.color_key            AS colorKey,
             c.monthly_budget_minor AS budgetMinor,
             COALESCE(SUM(t.amount_minor), 0) AS totalMinor,
             COUNT(t.id)            AS txnCount
        FROM categories c
        LEFT JOIN transactions t
               ON t.category_id = c.id
              AND t.deleted_at  IS NULL
              AND t.direction   = ?
              AND t.occurred_on >= ?
              AND t.occurred_on <  ?
       WHERE c.deleted_at IS NULL
         AND c.kind = ?
       GROUP BY c.id
      HAVING COUNT(t.id) > 0
       ORDER BY totalMinor DESC
      ''',
      variables: <Variable<Object>>[
        Variable<String>(directionNameFor(kind)),
        Variable<String>(fromIso),
        Variable<String>(toIso),
        Variable<String>(kind.name),
      ],
      readsFrom: <ResultSetImplementation<Object, Object>>{
        categories,
        transactions,
      },
    ).watch().map(
      (rows) => rows
          .map(
            (row) => CategorySpendRow(
              categoryId: row.read<String>('categoryId'),
              categoryName: row.read<String>('categoryName'),
              kind: parseCategoryKind(row.read<String>('kind')),
              iconKey: row.read<String>('iconKey'),
              colorKey: row.read<String>('colorKey'),
              budgetMinor: row.read<int>('budgetMinor'),
              totalMinor: row.read<int>('totalMinor'),
              txnCount: row.read<int>('txnCount'),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Totals per category per month, for the multi-month trend charts.
  ///
  /// Grouping on `substr(occurredOn, 1, 7)` keeps months in local time, which a
  /// `strftime` over UTC epoch seconds would not.
  ///
  /// Returns spending, income, *and* investing points in one pass, distinguished
  /// by `direction`. One query rather than three so the series cannot disagree:
  /// if spending and income were read separately, a write landing between the
  /// two reads would leave one chart describing a revision of the ledger the
  /// other had not seen yet.
  ///
  /// Income is included because "which sources did this month's money come
  /// from" is a per-category question like spend is. It is the *direction* on
  /// each point that keeps the three apart, which is why this query is safe to
  /// use for all of them and why no caller has to join categories again.
  Stream<List<CategoryTrendPoint>> watchCategoryTrend() {
    return customSelect(
      '''
      SELECT substr(t.occurred_on, 1, 7) AS monthKey,
             c.id            AS categoryId,
             c.name          AS categoryName,
             c.color_key     AS colorKey,
             t.direction     AS direction,
             COALESCE(SUM(t.amount_minor), 0) AS totalMinor
        FROM transactions t
        JOIN categories c ON c.id = t.category_id
       WHERE t.deleted_at IS NULL
         AND t.direction IN ('expense', 'income', 'investment')
       GROUP BY monthKey, c.id, t.direction
       ORDER BY monthKey, totalMinor DESC
      ''',
      readsFrom: <ResultSetImplementation<Object, Object>>{
        transactions,
        categories,
      },
    ).watch().map(
      (rows) => rows
          .map(
            (row) => CategoryTrendPoint(
              monthKey: row.read<String>('monthKey'),
              categoryId: row.read<String>('categoryId'),
              categoryName: row.read<String>('categoryName'),
              direction: parseDirection(row.read<String>('direction')),
              colorKey: row.read<String>('colorKey'),
              totalMinor: row.read<int>('totalMinor'),
            ),
          )
          .toList(growable: false),
    );
  }

  /// All live categories, ordered for pickers and management screens.
  Stream<List<CategoryRow>> watchCategories() {
    return customSelect(
      '''
      SELECT id, name, kind, icon_key, color_key,
             monthly_budget_minor, is_system, sort_order
        FROM categories
       WHERE deleted_at IS NULL
       ORDER BY sort_order, name
      ''',
      readsFrom: <ResultSetImplementation<Object, Object>>{categories},
    ).watch().map(
      (rows) => rows
          .map(
            (row) => CategoryRow(
              id: row.read<String>('id'),
              name: row.read<String>('name'),
              kind: parseCategoryKind(row.read<String>('kind')),
              iconKey: row.read<String>('icon_key'),
              colorKey: row.read<String>('color_key'),
              budgetMinor: row.read<int>('monthly_budget_minor'),
              isSystem: row.read<bool>('is_system'),
              sortOrder: row.read<int>('sort_order'),
            ),
          )
          .toList(growable: false),
    );
  }
}
