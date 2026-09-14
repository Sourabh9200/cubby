import 'package:finance_assistant/finance_assistant.dart';
import 'package:test/test.dart';

import 'fixtures.dart' show validAadhaar, validGoogleKey;

/// A minimal payload that should pass, used as the baseline for mutations.
Map<String, Object?> cleanPayload() => <String, Object?>{
  'categoryTotals': <Object?>[
    <String, Object?>{'label': 'Food', 'bucketMinor': 120000, 'txnCount': 5},
  ],
  'period': '2026-08',
  'granularity': 'month',
  'currency': 'INR',
  'amountBucketMinor': 10000,
  'mergedGroupCount': 0,
  'minGroupSize': 1,
};

PayloadGuard newGuard() =>
    PayloadGuard(redactor: Redactor(), allowedKeys: SanitizedContext.jsonKeys);

void main() {
  group('PayloadGuard', () {
    test('passes a well-formed context', () {
      final guard = newGuard();
      final report = guard.inspect(cleanPayload());
      expect(report.isClean, isTrue, reason: report.toString());
    });

    test('passes a real SanitizedContext round-trip', () {
      final context =
          SanitizedContextBuilder(redactor: Redactor(), minGroupSize: 1).build(
            aggregates: <RawCategoryAggregate>[
              const RawCategoryAggregate(
                categoryName: 'Groceries',
                totalMinor: 123456,
                txnCount: 9,
              ),
            ],
            currency: 'INR',
            period: DateTime(2026, 8),
          );
      expect(newGuard().inspect(context.toJson()).isClean, isTrue);
    });

    test('rejects a field that is not in the allowlist', () {
      final payload = cleanPayload()..['note'] = 'lunch with a colleague';
      final report = newGuard().inspect(payload);
      expect(report.isClean, isFalse);
      expect(report.violations.single.kind, ViolationKind.unknownKey);
      expect(report.violations.single.path, r'$.note');
    });

    test('detects PII that slipped through upstream', () {
      // Simulates a future bug where a redaction step is bypassed.
      final payload = cleanPayload()
        ..['period'] = 'leaked aadhaar $validAadhaar';
      final report = newGuard().inspect(payload);
      expect(report.isClean, isFalse);
      expect(
        report.violations.map((violation) => violation.kind),
        contains(ViolationKind.piiDetected),
      );
    });

    test('detects a leaked API key', () {
      final payload = cleanPayload()..['granularity'] = 'key $validGoogleKey';
      expect(newGuard().inspect(payload).isClean, isFalse);
    });

    test('rejects doubles, because money must be integer minor units', () {
      final payload = cleanPayload()..['amountBucketMinor'] = 100.5;
      final report = newGuard().inspect(payload);
      expect(report.violations.single.kind, ViolationKind.disallowedType);
    });

    test('rejects a DateTime, which would carry extra precision', () {
      final payload = cleanPayload()..['period'] = DateTime(2026, 8, 13);
      final report = newGuard().inspect(payload);
      expect(report.violations.single.kind, ViolationKind.disallowedType);
    });

    test('flags a bare number long enough to be an identifier', () {
      final payload = cleanPayload()..['amountBucketMinor'] = 1234567890123;
      final report = newGuard().inspect(payload);
      expect(report.violations.single.kind, ViolationKind.suspiciousNumber);
    });

    test('does not mistake a placeholder token index for a long number', () {
      final payload = cleanPayload()
        ..['categoryTotals'] = <Object?>[
          <String, Object?>{
            'label': '[REDACTED_1]',
            'bucketMinor': 120000,
            'txnCount': 5,
          },
        ];
      expect(newGuard().inspect(payload).isClean, isTrue);
    });

    test('reports the path of a nested violation', () {
      final payload = cleanPayload()
        ..['categoryTotals'] = <Object?>[
          <String, Object?>{
            'label': 'ok',
            'bucketMinor': 120000,
            'txnCount': 5,
            'payee': 'Dr Sharma Clinic',
          },
        ];
      final report = newGuard().inspect(payload);
      expect(report.violations.single.path, r'$.categoryTotals[0].payee');
    });

    test('assertClean throws with the full report attached', () {
      expect(
        () => newGuard().assertClean(cleanPayload()..['note'] = 'x'),
        throwsA(
          isA<PiiLeakException>().having(
            (exception) => exception.report.violations.length,
            'violation count',
            1,
          ),
        ),
      );
    });

    test('accepts a payload with no category totals at all', () {
      final payload = cleanPayload()..['categoryTotals'] = <Object?>[];
      expect(newGuard().inspect(payload).isClean, isTrue);
    });
  });
}
