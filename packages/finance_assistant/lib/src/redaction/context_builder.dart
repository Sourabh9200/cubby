/// Builds a [SanitizedContext] from raw aggregates.
///
/// Applies three transformations in order: label redaction, amount bucketing,
/// and small-group merging. The order matters — redaction runs before bucketing
/// so that a redaction failure can never be masked by rounding.
library;

import '../pii_vault.dart';
import '../redactor.dart';
import '../sanitized_context.dart';

/// Turns raw aggregates into a transmissible payload.
class SanitizedContextBuilder {
  /// Creates a builder.
  ///
  /// [amountBucketMinor] defaults to 10,000 minor units (₹100 in INR), which
  /// hides exact balances while preserving ordering and proportion.
  /// [minGroupSize] is the k in k-anonymity.
  SanitizedContextBuilder({
    required this.redactor,
    this.granularity = Granularity.month,
    this.amountBucketMinor = 10000,
    this.minGroupSize = 2,
  }) : assert(amountBucketMinor > 0, 'Bucket size must be positive.'),
       assert(minGroupSize >= 1, 'k must be at least 1.');

  final Redactor redactor;
  final Granularity granularity;

  /// Amount precision, in minor units.
  final int amountBucketMinor;

  /// Minimum transactions for a group to be disclosed on its own.
  final int minGroupSize;

  /// Builds the payload. Never throws on odd input: a finance app must still
  /// produce a safe answer when the data is messy.
  ///
  /// Pass [vault] to keep category tokens stable across a conversation.
  SanitizedContext build({
    required List<RawCategoryAggregate> aggregates,
    required String currency,
    required DateTime period,
    PiiVault? vault,
  }) {
    final disclosed = <CategoryTotal>[];
    var mergedAmount = 0;
    var mergedCount = 0;
    var mergedGroups = 0;

    for (final aggregate in aggregates) {
      if (aggregate.txnCount < minGroupSize) {
        // Merge rather than drop, so the disclosed total still reconciles with
        // what the user sees locally. Dropping would make the model's
        // arithmetic disagree with the app's, which reads as a bug.
        mergedAmount += aggregate.totalMinor;
        mergedCount += aggregate.txnCount;
        mergedGroups++;
        continue;
      }
      disclosed.add(
        CategoryTotal(
          label: safeLabel(aggregate.categoryName, vault: vault),
          bucketMinor: bucketAmount(aggregate.totalMinor),
          txnCount: aggregate.txnCount,
        ),
      );
    }

    if (mergedGroups > 0) {
      disclosed.add(
        CategoryTotal(
          label: 'Other',
          bucketMinor: bucketAmount(mergedAmount),
          txnCount: mergedCount,
        ),
      );
    }

    disclosed.sort((a, b) => b.bucketMinor.compareTo(a.bucketMinor));
    return SanitizedContext(
      categoryTotals: disclosed,
      period: periodLabel(period),
      granularity: granularity,
      currency: currency,
      amountBucketMinor: amountBucketMinor,
      mergedGroupCount: mergedGroups,
      minGroupSize: minGroupSize,
    );
  }

  /// Rounds [minor] to the nearest bucket.
  ///
  /// Nearest rather than floor, so repeated rounding does not introduce a
  /// systematic downward bias into long-run trends.
  int bucketAmount(int minor) {
    final half = amountBucketMinor ~/ 2;
    if (minor >= 0) {
      return ((minor + half) ~/ amountBucketMinor) * amountBucketMinor;
    }
    return -((((-minor) + half) ~/ amountBucketMinor) * amountBucketMinor);
  }

  /// Redacts a category name and bounds its length.
  ///
  /// Category names are user-authored free text, so they can carry personal
  /// detail ("Divorce lawyer", "Dr Sharma clinic"). They are the only label
  /// that reaches the model, which makes them the highest-risk field in the
  /// payload.
  String safeLabel(String categoryName, {PiiVault? vault}) {
    final scrubbed = redactor.redact(categoryName, vault: vault).text.trim();
    if (scrubbed.isEmpty) {
      return 'Uncategorised';
    }
    // Cap length so a pasted receipt note cannot ride along as a "label".
    return scrubbed.length <= 40 ? scrubbed : '${scrubbed.substring(0, 40)}…';
  }

  /// Formats the period at the configured granularity.
  String periodLabel(DateTime period) {
    final year = period.year.toString().padLeft(4, '0');
    return switch (granularity) {
      Granularity.month => '$year-${period.month.toString().padLeft(2, '0')}',
      Granularity.quarter => '$year-Q${((period.month - 1) ~/ 3) + 1}',
      Granularity.year => year,
    };
  }
}
