import 'package:drift/drift.dart';

import '../database.dart';
import '../query_rows.dart';
import 'row_parsing.dart';

/// Account reads.
extension AccountQueries on AppDatabase {
  /// All live accounts, each with the net movement recorded against it.
  ///
  /// Investments count as outflow here, because they genuinely leave the
  /// account. This is the one place where an investment behaves like an
  /// expense, and the reason the direction lives in the data rather than being
  /// inferred from the category at each call site.
  ///
  /// Transfer legs are excluded: transfers are schema-ready but not yet exposed
  /// in the UI, so no such rows can exist. The filter keeps the number honest
  /// until they are, because an always-positive amount with a `transfer`
  /// direction carries no sign to add.
  Stream<List<AccountRow>> watchAccounts() {
    return customSelect(
      '''
      SELECT a.id                    AS id,
             a.name                  AS name,
             a.type                  AS type,
             a.currency              AS currency,
             a.opening_balance_minor AS openingBalanceMinor,
             a.sort_order            AS sortOrder,
             COALESCE(SUM(CASE WHEN t.direction = 'income'
                               THEN t.amount_minor
                               ELSE -t.amount_minor END), 0) AS netMovementMinor
        FROM accounts a
        LEFT JOIN transactions t
               ON t.account_id = a.id
              AND t.deleted_at IS NULL
              AND t.direction IN ('expense', 'income', 'investment')
       WHERE a.deleted_at IS NULL
       GROUP BY a.id
       ORDER BY a.sort_order, a.name
      ''',
      readsFrom: <ResultSetImplementation<Object, Object>>{
        accounts,
        transactions,
      },
    ).watch().map(
      (rows) => rows
          .map(
            (row) => AccountRow(
              id: row.read<String>('id'),
              name: row.read<String>('name'),
              type: parseAccountType(row.read<String>('type')),
              currency: row.read<String>('currency'),
              openingBalanceMinor: row.read<int>('openingBalanceMinor'),
              netMovementMinor: row.read<int>('netMovementMinor'),
              sortOrder: row.read<int>('sortOrder'),
            ),
          )
          .toList(growable: false),
    );
  }
}
