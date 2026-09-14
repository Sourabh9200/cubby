import 'package:drift/drift.dart';

import '../database.dart';
import '../query_rows.dart';
import 'row_parsing.dart';

/// Ledger reads.
extension LedgerQueries on AppDatabase {
  /// The ledger, newest first, with category and account names resolved.
  ///
  /// Ordering falls back to `createdAt` so several entries on the same day keep
  /// a stable, insertion-ordered position instead of shuffling between reads.
  Stream<List<LedgerRow>> watchLedger({int? limit}) {
    return customSelect(
      '''
      SELECT t.id            AS id,
             t.account_id    AS accountId,
             a.name          AS accountName,
             t.category_id   AS categoryId,
             c.name          AS categoryName,
             c.icon_key      AS iconKey,
             c.color_key     AS colorKey,
             t.amount_minor  AS amountMinor,
             t.currency      AS currency,
             t.direction     AS direction,
             t.occurred_on   AS occurredOn,
             t.payee         AS payee,
             t.note          AS note,
             t.is_sample     AS isSample
        FROM transactions t
        JOIN categories c ON c.id = t.category_id
        JOIN accounts   a ON a.id = t.account_id
       WHERE t.deleted_at IS NULL
       ORDER BY t.occurred_on DESC, t.created_at DESC
       ${limit == null ? '' : 'LIMIT ?'}
      ''',
      variables: <Variable<Object>>[if (limit != null) Variable<int>(limit)],
      readsFrom: <ResultSetImplementation<Object, Object>>{
        transactions,
        categories,
        accounts,
      },
    ).watch().map(
      (rows) => rows
          .map(
            (row) => LedgerRow(
              id: row.read<String>('id'),
              accountId: row.read<String>('accountId'),
              accountName: row.read<String>('accountName'),
              categoryId: row.read<String>('categoryId'),
              categoryName: row.read<String>('categoryName'),
              iconKey: row.read<String>('iconKey'),
              colorKey: row.read<String>('colorKey'),
              amountMinor: row.read<int>('amountMinor'),
              currency: row.read<String>('currency'),
              direction: parseDirection(row.read<String>('direction')),
              occurredOn: row.read<String>('occurredOn'),
              payee: row.read<String>('payee'),
              note: row.read<String>('note'),
              isSample: row.read<bool>('isSample'),
            ),
          )
          .toList(growable: false),
    );
  }

  /// A single entry by id, or null when it is missing or soft-deleted.
  Future<LedgerRow?> findEntry(String id) async {
    final rows = await watchLedger().first;
    for (final row in rows) {
      if (row.id == id) {
        return row;
      }
    }
    return null;
  }
}
