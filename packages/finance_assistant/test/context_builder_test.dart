import 'package:finance_assistant/finance_assistant.dart';
import 'package:test/test.dart';

void main() {
  /// Builds a context with a plain redactor and a ₹100 (10,000 paise) bucket.
  SanitizedContext build(
    List<RawCategoryAggregate> rows, {
    int minGroupSize = 2,
    Granularity granularity = Granularity.month,
    List<PiiDetector>? detectors,
  }) => SanitizedContextBuilder(
    redactor: Redactor(detectors: detectors ?? <PiiDetector>[]),
    minGroupSize: minGroupSize,
    granularity: granularity,
  ).build(aggregates: rows, currency: 'INR', period: DateTime(2026, 8, 13));

  group('amount bucketing', () {
    test('rounds to the nearest bucket, not down', () {
      final context = build(<RawCategoryAggregate>[
        const RawCategoryAggregate(
          categoryName: 'Food',
          totalMinor: 123456,
          txnCount: 5,
        ),
        const RawCategoryAggregate(
          categoryName: 'Transport',
          totalMinor: 149000,
          txnCount: 5,
        ),
      ], minGroupSize: 1);
      final byLabel = <String, int>{
        for (final total in context.categoryTotals)
          total.label: total.bucketMinor,
      };
      // 1,234.56 -> 1,200.00 ; 1,490.00 -> 1,500.00
      expect(byLabel['Food'], 120000);
      expect(byLabel['Transport'], 150000);
    });

    test('rounds a symmetric negative away from zero', () {
      final builder = SanitizedContextBuilder(redactor: Redactor());
      expect(builder.bucketAmount(-123456), -120000);
      expect(builder.bucketAmount(0), 0);
    });

    test('sorts disclosed categories by spend descending', () {
      final context = build(<RawCategoryAggregate>[
        const RawCategoryAggregate(
          categoryName: 'Small',
          totalMinor: 20000,
          txnCount: 3,
        ),
        const RawCategoryAggregate(
          categoryName: 'Large',
          totalMinor: 900000,
          txnCount: 3,
        ),
      ], minGroupSize: 1);
      expect(
        context.categoryTotals.map((total) => total.label).toList(),
        <String>['Large', 'Small'],
      );
    });
  });

  group('k-anonymity', () {
    test('merges small groups into Other instead of dropping them', () {
      final context = build(<RawCategoryAggregate>[
        const RawCategoryAggregate(
          categoryName: 'Food',
          totalMinor: 500000,
          txnCount: 10,
        ),
        const RawCategoryAggregate(
          categoryName: 'Solo Purchase',
          totalMinor: 700000,
          txnCount: 1,
        ),
      ]);
      expect(context.mergedGroupCount, 1);
      expect(
        context.categoryTotals.map((total) => total.label),
        contains('Other'),
      );
      // The merged amount must survive, so the disclosed total reconciles with
      // what the user sees in the app.
      final other = context.categoryTotals.firstWhere(
        (total) => total.label == 'Other',
      );
      expect(other.bucketMinor, 700000);
    });

    test('discloses everything when k is 1', () {
      final context = build(<RawCategoryAggregate>[
        const RawCategoryAggregate(
          categoryName: 'Food',
          totalMinor: 500000,
          txnCount: 1,
        ),
      ], minGroupSize: 1);
      expect(context.mergedGroupCount, 0);
      expect(context.categoryTotals.single.label, 'Food');
    });
  });

  group('period generalization', () {
    final builder = SanitizedContextBuilder(redactor: Redactor());
    final august = DateTime(2026, 8, 13);

    test('formats each granularity correctly', () {
      expect(builder.periodLabel(august), '2026-08');
      expect(
        SanitizedContextBuilder(
          redactor: Redactor(),
          granularity: Granularity.quarter,
        ).periodLabel(august),
        '2026-Q3',
      );
      expect(
        SanitizedContextBuilder(
          redactor: Redactor(),
          granularity: Granularity.year,
        ).periodLabel(august),
        '2026',
      );
    });

    test('never emits day-level precision', () {
      expect(builder.periodLabel(august).contains('13'), isFalse);
    });

    test('labels January and December quarters at the boundaries', () {
      final quarter = SanitizedContextBuilder(
        redactor: Redactor(),
        granularity: Granularity.quarter,
      );
      expect(quarter.periodLabel(DateTime(2026, 1, 5)), '2026-Q1');
      expect(quarter.periodLabel(DateTime(2026, 12, 31)), '2026-Q4');
    });
  });

  group('label handling', () {
    test('redacts a registered name inside a category label', () {
      final context = build(
        <RawCategoryAggregate>[
          const RawCategoryAggregate(
            categoryName: 'Consult Dr Sharma',
            totalMinor: 500000,
            txnCount: 5,
          ),
        ],
        minGroupSize: 1,
        detectors: <PiiDetector>[
          KeywordDetector(<String>['Dr Sharma']),
        ],
      );
      expect(context.categoryTotals.single.label, 'Consult [REDACTED_1]');
    });

    test('caps label length so a pasted note cannot ride along', () {
      final context = build(<RawCategoryAggregate>[
        RawCategoryAggregate(
          categoryName: 'A' * 200,
          totalMinor: 500000,
          txnCount: 5,
        ),
      ], minGroupSize: 1);
      expect(context.categoryTotals.single.label.length, lessThanOrEqualTo(41));
    });

    test('falls back for a blank label', () {
      final context = build(<RawCategoryAggregate>[
        const RawCategoryAggregate(
          categoryName: '   ',
          totalMinor: 500000,
          txnCount: 5,
        ),
      ], minGroupSize: 1);
      expect(context.categoryTotals.single.label, 'Uncategorised');
    });
  });
}
