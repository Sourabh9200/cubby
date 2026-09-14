// ignore_for_file: avoid_print
//
// Runnable demonstration on realistic Indian financial text.
//
//   dart run example/redaction_demo.dart
//
// Shows what the model would see versus what the user typed, and proves that
// the real values survive only in the local vault.

import 'dart:convert';

import 'package:finance_assistant/finance_assistant.dart';

/// Realistic statement lines and messages, of the shape a bank or UPI app
/// actually produces.
const List<String> samples = <String>[
  'UPI/9876543210@ybl/Dr Sharma Clinic/consultation fee',
  'NEFT UTR 123456789012 from A/c 50100123456789 at HDFC0001234',
  'Aadhaar linked 2345 6789 0124 verified for KYC',
  'Paid 1234.56 using card 4111 1111 1111 1111 at Amazon',
  'Send the report to jane.doe@acme.com, card ending XXXX1234',
  'receipt_hospital_dad.jpg filed under Divorce lawyer consultations',
  'my api key is AIzaSyD-9tSrke72PouQMnMX-a7eZSW0jkFMBWY do not share',
  'I spent 1,234.56 on groceries on 2026-08-13, budget is 25000',
];

void main() {
  final redactor = Redactor(denyList: <String>['Divorce lawyer', 'Dr Sharma']);

  print('=' * 78);
  print('LAYER 1-3: FREE TEXT REDACTION');
  print('=' * 78);
  for (final sample in samples) {
    final result = redactor.redact(sample);
    final kinds = result.spans.map((span) => span.kind.name).join(', ');
    print('\nIN   : $sample');
    print('OUT  : ${result.text}');
    print('FOUND: ${result.isClean ? '(nothing — safe as-is)' : kinds}');
  }

  const vault = 'remembered locally only';

  print('\n${'=' * 78}');
  print('LAYER 4: AGGREGATE GENERALIZATION');
  print('=' * 78);
  final context = SanitizedContextBuilder(redactor: redactor).build(
    aggregates: <RawCategoryAggregate>[
      const RawCategoryAggregate(
        categoryName: 'Groceries',
        totalMinor: 1234567, // ₹12,345.67
        txnCount: 22,
      ),
      const RawCategoryAggregate(
        categoryName: 'Card 4111 1111 1111 1111',
        totalMinor: 987654, // ₹9,876.54
        txnCount: 6,
      ),
      const RawCategoryAggregate(
        categoryName: 'Consult Dr Sharma',
        totalMinor: 500000,
        txnCount: 1, // Below k, so it is merged into Other.
      ),
    ],
    currency: 'INR',
    period: DateTime(2026, 8),
  );

  final payload = context.toJson();
  print('\nExact ₹12,345.67 became ₹12,300.00 (bucket = ₹100).');
  print('The one-off "Consult Dr Sharma" was merged into Other, not dropped,');
  print('so the disclosed total still reconciles with the app.\n');
  print(const JsonEncoder.withIndent('  ').convert(payload));

  print('\n${'=' * 78}');
  print('LAYER 5: EGRESS GUARD');
  print('=' * 78);
  final guard = PayloadGuard(
    redactor: redactor,
    allowedKeys: SanitizedContext.jsonKeys,
  );

  final clean = guard.inspect(payload);
  print('\nclean payload      -> isClean=${clean.isClean}');

  // Simulate a future bug that bypasses redaction and adds a field.
  final buggy = <String, Object?>{
    ...payload,
    'note': 'paid Dr Sharma 5000',
    'accountId': 50100123456789,
  };
  final report = guard.inspect(buggy);
  print('payload with a bug -> isClean=${report.isClean}');
  for (final violation in report.violations) {
    print('   ${violation.kind.name}: ${violation.path}');
  }
  print('\nA red CI test here is a release blocker, by design.');

  print('\n${'=' * 78}');
  print('LAYER 6: RE-HYDRATION (the model never saw the real value)');
  print('=' * 78);
  final vaultInstance = PiiVault();
  final scrubbed = redactor.redact(
    'Was the payment to 9876543210@ybl larger than usual?',
    vault: vaultInstance,
  );
  print('\nsent to model : ${scrubbed.text}');
  final modelReply =
      'Yes — [UPI_1] received [PHONE_9] worth of activity this month.';
  print('model replied : $modelReply');
  print('shown to user : ${vaultInstance.restore(modelReply)}');
  print(
    '\nNote [PHONE_9]: it was never issued, so it is left untouched rather '
    'than substituted. Matching is restricted to tokens we actually created, '
    'which is what makes the lenient restore safe.',
  );
  print(
    '\nVault ($vault) holds ${vaultInstance.size} mapping(s); it is never '
    'serialized.',
  );
}
