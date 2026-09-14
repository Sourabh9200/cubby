/// Shared parsing helpers for raw SQL result rows.
///
/// SQLite stores drift's `textEnum` columns as the enum's `name`, so reading
/// them back needs an explicit, total mapping. A `firstWhere` with an
/// `orElse` is used rather than `byName`, because a row written by a newer
/// version of the app must not crash an older one.
library;

import '../tables.dart';

/// Parses an [EntryDirection] from its stored name.
EntryDirection parseDirection(String raw) => EntryDirection.values.firstWhere(
  (value) => value.name == raw,
  orElse: () => EntryDirection.expense,
);

/// Parses a [CategoryKind] from its stored name.
CategoryKind parseCategoryKind(String raw) => CategoryKind.values.firstWhere(
  (value) => value.name == raw,
  orElse: () => CategoryKind.expense,
);

/// Parses an [AccountType] from its stored name.
AccountType parseAccountType(String raw) => AccountType.values.firstWhere(
  (value) => value.name == raw,
  orElse: () => AccountType.bank,
);

/// Parses a [RecurrenceFrequency] from its stored name.
RecurrenceFrequency parseRecurrenceFrequency(String raw) =>
    RecurrenceFrequency.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => RecurrenceFrequency.monthly,
    );

/// Formats a [DateTime] as the local ISO date used by `occurredOn`.
String isoDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-$month-$day';
}

/// Formats a [DateTime] as the `YYYY-MM` prefix used for month grouping.
String isoMonth(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}';

/// The stored direction name corresponding to a category [kind].
///
/// A category's kind and its entries' direction hold the same string, but the
/// mapping is written out rather than relying on `kind.name`. The two enums are
/// separate types that happen to agree today; spelling out the correspondence
/// means renaming one of them cannot silently turn every aggregate query into a
/// filter that matches nothing and reports a total of zero.
String directionNameFor(CategoryKind kind) => switch (kind) {
  CategoryKind.expense => 'expense',
  CategoryKind.income => 'income',
  CategoryKind.investment => 'investment',
};

/// First day of [date]'s month, as an ISO date string.
String monthStartIso(DateTime date) => isoDate(DateTime(date.year, date.month));

/// First day of the month *after* [date], as an ISO date string.
///
/// Used as the exclusive upper bound. Passing `DateTime(year, month + 1)`
/// rather than adding 30 days is what makes February and leap years correct.
String monthEndIso(DateTime date) =>
    isoDate(DateTime(date.year, date.month + 1));
