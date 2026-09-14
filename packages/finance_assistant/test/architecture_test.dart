/// Mechanical enforcement of the architectural privacy rules.
///
/// These are not style tests. Each one guards a property that, if broken,
/// would silently widen what can reach a third party.
library;

import 'dart:convert';
import 'dart:io';

import 'package:finance_assistant/finance_assistant.dart';
import 'package:test/test.dart';

void main() {
  group('structural guarantees', () {
    test('the payload key allowlist is exactly what was reviewed', () {
      // A golden test. Adding a field to the wire format must be a deliberate
      // act that updates this list, never an accident.
      expect(SanitizedContext.jsonKeys, <String>{
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
      });
    });

    test('the serialized payload introduces no extra keys', () {
      final decoded = jsonDecode(
        jsonEncode(
          SanitizedContextBuilder(redactor: Redactor(), minGroupSize: 1)
              .build(
                aggregates: <RawCategoryAggregate>[
                  const RawCategoryAggregate(
                    categoryName: 'Food',
                    totalMinor: 500000,
                    txnCount: 3,
                  ),
                ],
                currency: 'INR',
                period: DateTime(2026, 8),
              )
              .toJson(),
        ),
      );
      final keys = <String>{};
      void collect(Object? node) {
        if (node is Map<String, Object?>) {
          keys.addAll(node.keys);
          node.values.forEach(collect);
        } else if (node is List<Object?>) {
          node.forEach(collect);
        }
      }

      collect(decoded);
      expect(keys.difference(SanitizedContext.jsonKeys), isEmpty);
    });

    test('no library file references the database or Flutter', () {
      // The architectural rule: because the transport cannot import
      // finance_db, a raw transaction has no type-level route to the network.
      // Guarded mechanically so a future "convenience" import cannot quietly
      // break the guarantee.
      final sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();
      expect(sources, isNotEmpty);
      for (final source in sources) {
        final contents = source.readAsStringSync();
        expect(
          contents.contains('finance_db'),
          isFalse,
          reason: '${source.path} references the database package.',
        );
        expect(
          contents.contains('package:flutter/'),
          isFalse,
          reason:
              '${source.path} depends on Flutter; this package must stay '
              'pure Dart so it stays testable and auditable anywhere.',
        );
      }
    });

    test('the package declares no runtime dependencies', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        RegExp(r'^dependencies:\s*\{\}\s*$', multiLine: true).hasMatch(pubspec),
        isTrue,
        reason:
            'finance_assistant must stay dependency-free: every runtime '
            'dependency inside a trust boundary is unauditable code that can '
            'see pre-redaction data.',
      );
    });
  });
}
