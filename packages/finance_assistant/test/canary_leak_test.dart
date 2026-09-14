/// The tests that keep this library honest.
///
/// Instead of asserting on individual detectors or individual fields, these
/// take the whole pipeline end to end and prove that no known-sensitive value
/// survives to the wire from any entry point. If someone later adds a field,
/// widens an allowlist, or reorders the pipeline, these fail.
library;

import 'dart:convert';

import 'package:finance_assistant/finance_assistant.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// One canary per sensitive category. Each is a real, detector-valid value.
final List<String> canaries = <String>[
  validAadhaar,
  validCard,
  validGoogleKey,
  validHuggingFaceToken,
  validIbanGb,
  validPan,
  validIfsc,
  validGstin,
  'jane.doe@acme.com',
  '9876543210',
  'ramesh@okhdfcbank',
];

SanitizedContext contextFor(String label) =>
    SanitizedContextBuilder(redactor: Redactor(), minGroupSize: 1).build(
      aggregates: <RawCategoryAggregate>[
        RawCategoryAggregate(
          categoryName: label,
          totalMinor: 500000,
          txnCount: 4,
        ),
      ],
      currency: 'INR',
      period: DateTime(2026, 8),
    );

PayloadGuard guardFor(Redactor redactor) =>
    PayloadGuard(redactor: redactor, allowedKeys: SanitizedContext.jsonKeys);

void main() {
  group('canary leak tests', () {
    test('no canary survives into the serialized payload', () {
      for (final canary in canaries) {
        final serialized = jsonEncode(contextFor('Spend at $canary').toJson());
        expect(
          serialized.contains(canary),
          isFalse,
          reason: 'canary leaked into the payload: $canary\n$serialized',
        );
      }
    });

    test('no canary survives in a user prompt', () {
      final redactor = Redactor();
      for (final canary in canaries) {
        final result = redactor.redact('how much did I spend at $canary');
        expect(
          result.text.contains(canary),
          isFalse,
          reason: 'canary leaked into the prompt: $canary',
        );
      }
    });

    test('the egress guard independently catches an injected leak', () {
      // Proves the safety net works even when upstream redaction is bypassed.
      for (final canary in canaries) {
        final report = guardFor(Redactor()).inspect(<String, Object?>{
          'categoryTotals': <Object?>[],
          'period': '2026-08',
          'granularity': 'month',
          'currency': 'INR',
          'amountBucketMinor': 10000,
          'mergedGroupCount': 0,
          'minGroupSize': 1,
          'label': canary,
        });
        expect(
          report.isClean,
          isFalse,
          reason: 'guard failed to catch a leaked canary: $canary',
        );
      }
    });

    test('a clean conversation produces a clean payload end to end', () {
      final vault = PiiVault();
      final redactor = Redactor();
      final prompt = redactor.redact(
        'why is my food spending up this month?',
        vault: vault,
      );
      final context =
          SanitizedContextBuilder(redactor: redactor, minGroupSize: 1).build(
            aggregates: <RawCategoryAggregate>[
              const RawCategoryAggregate(
                categoryName: 'Food',
                totalMinor: 1234567,
                txnCount: 22,
              ),
            ],
            currency: 'INR',
            period: DateTime(2026, 8),
            vault: vault,
          );
      expect(prompt.isClean, isTrue);
      final report = guardFor(redactor).inspect(context.toJson());
      expect(report.isClean, isTrue, reason: report.toString());
    });

    test('nothing is disclosed when there is no aggregate to send', () {
      final context = SanitizedContextBuilder(redactor: Redactor()).build(
        aggregates: <RawCategoryAggregate>[],
        currency: 'INR',
        period: DateTime(2026, 8),
      );
      expect(context.isEmpty, isTrue);
      expect(jsonEncode(context.toJson()).contains('categoryTotals'), isTrue);
      expect(guardFor(Redactor()).inspect(context.toJson()).isClean, isTrue);
    });
  });
}
