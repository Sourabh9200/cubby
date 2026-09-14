/// The type-level chokepoint for everything that may leave the device.
///
/// This file is the load-bearing privacy control. The HTTP client lives in a
/// package that never imports the database layer, and the only payload type it
/// accepts is [SanitizedContext]. Raw transactions, payees, notes, and account
/// identifiers therefore have no type-level path to the network: there is no
/// API that would accept them. That is materially stronger than a convention to
/// "remember to sanitize", because it cannot be forgotten under deadline
/// pressure.
library;

/// Time granularity of the aggregates we disclose.
///
/// Month is the default. Day-level reporting would let an observer reconstruct
/// a daily behavioural trace, which is far more identifying than a monthly
/// total.
enum Granularity { month, quarter, year }

/// One category's spend, already generalized and safe to disclose.
final class CategoryTotal {
  const CategoryTotal({
    required this.label,
    required this.bucketMinor,
    required this.txnCount,
  });

  /// Category name, after passing through the redactor.
  final String label;

  /// Total in minor units, snapped to the configured bucket size.
  final int bucketMinor;

  final int txnCount;
}

/// The narrow input DTO that the data layer may hand to the builder.
///
/// Deliberately aggregate-only: it has no field for a payee, a note, an account
/// id, or a transaction id, so a caller cannot smuggle raw rows through even by
/// mistake.
final class RawCategoryAggregate {
  const RawCategoryAggregate({
    required this.categoryName,
    required this.totalMinor,
    required this.txnCount,
  });

  final String categoryName;
  final int totalMinor;
  final int txnCount;
}

/// An immutable, strictly-shaped payload safe for transmission.
final class SanitizedContext {
  const SanitizedContext({
    required this.categoryTotals,
    required this.period,
    required this.granularity,
    required this.currency,
    required this.amountBucketMinor,
    required this.mergedGroupCount,
    required this.minGroupSize,
  });

  /// Key names permitted anywhere in the serialized payload.
  ///
  /// `PayloadGuard` enforces this, so a future refactor that adds a field —
  /// say, a `note` — fails a test instead of silently widening the blast
  /// radius.
  static const Set<String> jsonKeys = <String>{
    'categoryTotals',
    'label',
    'bucketMinor',
    'txnCount',
    'period',
    'granularity',
    'currency',
    'amountBucketMinor',
    'mergedGroupCount',
    'minGroupSize',
  };

  final List<CategoryTotal> categoryTotals;

  /// Generalized period label, for example `2026-08`.
  final String period;

  final Granularity granularity;
  final String currency;

  /// Precision that amounts were rounded to, so the model does not imply false
  /// accuracy.
  final int amountBucketMinor;

  /// How many small groups were folded into `Other`.
  final int mergedGroupCount;

  final int minGroupSize;

  /// True when no category data is being disclosed at all.
  bool get isEmpty => categoryTotals.isEmpty;

  /// Serializes to exactly the keys declared in [jsonKeys].
  Map<String, Object?> toJson() => <String, Object?>{
    'categoryTotals': categoryTotals
        .map(
          (total) => <String, Object?>{
            'label': total.label,
            'bucketMinor': total.bucketMinor,
            'txnCount': total.txnCount,
          },
        )
        .toList(growable: false),
    'period': period,
    'granularity': granularity.name,
    'currency': currency,
    'amountBucketMinor': amountBucketMinor,
    'mergedGroupCount': mergedGroupCount,
    'minGroupSize': minGroupSize,
  };
}
