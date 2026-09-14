import '../../data/finance_snapshot.dart';
import '../../data/snapshot_views.dart';

/// Builds the exact payload that a cloud model would receive.
///
/// This mirrors the real `SanitizedContext` from `packages/finance_assistant`,
/// and it exists so the "review before sending" screen can show the user the
/// literal bytes rather than asking them to trust a description.
///
/// What is deliberately absent, and why it matters:
///
/// * **No payee or merchant names.** A merchant string is the most identifying
///   field in a statement ("Dr Sharma Clinic", "Divorce lawyer").
/// * **No transaction ids or account identifiers.** They are stable join keys to
///   a real person's records.
/// * **No exact amounts.** Each total is floored to a bucket, because an exact
///   salary or EMI figure is close to a fingerprint on its own.
/// * **No dates beyond the month.** Day-level data reconstructs a behaviour
///   trace; a monthly total does not.
///
/// Category labels do appear. They are user-authored free text, so they are the
/// one field that still needs redaction before transmission — which is exactly
/// what the real package does via its redactor.
Map<String, Object?> buildSanitizedPreview(
  FinanceSnapshot snapshot, {
  int bucketRupees = 100,
}) {
  final month = snapshot.currentMonth;
  final spends = snapshot.spendByCategory(month.month);
  final bucketPaise = bucketRupees * 100;

  return <String, Object?>{
    'categoryTotals': spends
        .map(
          (spend) => <String, Object?>{
            'bucketMinor': (spend.totalMinor ~/ bucketPaise) * bucketPaise,
            'txnCount': spend.txnCount,
          },
        )
        .toList(growable: false),
    'period':
        '${month.month.year}-'
        '${month.month.month.toString().padLeft(2, '0')}',
    'granularity': 'month',
    'currency': 'INR',
    'amountBucketMinor': bucketPaise,
  };
}
