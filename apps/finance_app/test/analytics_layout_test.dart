import 'package:finance_app/core/widgets/charts/chart_bar.dart';
import 'package:finance_app/data/composition.dart';
import 'package:finance_app/data/spending_rhythm.dart';
import 'package:finance_app/features/trends/widgets/composition_over_time_card.dart';
import 'package:finance_app/features/trends/widgets/spending_rhythm_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bar charts, on a narrow phone.
///
/// A device run on a 347 dp-wide screen (1216px at density 3.5) caught two
/// things this file now pins. A `Container` with only a height collapses to zero
/// width inside a `Column`, because `Container` wraps a childless box in a
/// `LimitedBox(maxWidth: 0)` — so a decoration-only bar is invisible, which no
/// semantics tree and no overflow error would ever reveal. And the month labels
/// of a twelve-column year chart wrap once a column is about twenty dp wide,
/// which overflowed a fixed chart height by 19 pixels.
void main() {
  /// A 347 dp-wide phone, at the density the bugs were found at.
  Future<void> pumpChart(WidgetTester tester, Widget chart) async {
    tester.view.devicePixelRatio = 3.5;
    tester.view.physicalSize = const Size(1216, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: chart)),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Twelve months of composition: the shape of the year chart.
  List<CompositionPoint> yearPoints() => <CompositionPoint>[
    for (var month = 1; month <= 12; month++)
      CompositionPoint(
        month: DateTime(2026, month),
        totals: CompositionTotals(
          incomeMinor: 5000000 + month * 1000,
          expenseMinor: 2000000 + month * 100,
          investmentMinor: 1000000,
        ),
        isPartial: month == 12,
      ),
  ];

  /// All seven days, so every column has something to draw and one of them is
  /// the tallest.
  SpendingRhythm rhythm() => SpendingRhythm(
    byWeekday: <WeekdaySpend>[
      for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++)
        WeekdaySpend(weekday: weekday, totalMinor: 10000 * weekday, days: 4),
    ],
    totalMinor: 280000,
    activeDays: 20,
    recordedDays: 28,
  );

  testWidgets('the year chart draws twelve columns without overflowing', (
    tester,
  ) async {
    final points = yearPoints();
    await pumpChart(tester, CompositionOverTimeCard(points: points));

    // Every month needs a band with real area. The legend swatches are 10 dp
    // wide and are filtered out, so a zero-width band cannot hide behind them.
    final decorations = find.descendant(
      of: find.byType(CompositionOverTimeCard),
      matching: find.byType(DecoratedBox),
    );
    var bands = 0;
    for (var index = 0; index < decorations.evaluate().length; index++) {
      final size = tester.getSize(decorations.at(index));
      if (size.width > 12 && size.height > 0) {
        bands++;
      }
    }
    expect(
      bands,
      greaterThanOrEqualTo(points.length),
      reason: 'a month column has no area',
    );
    // A wrapped month label is what used to overflow the fixed chart height.
    expect(tester.takeException(), isNull);
  });

  testWidgets('the weekday chart draws seven bars, each with width', (
    tester,
  ) async {
    await pumpChart(tester, SpendingRhythmCard(rhythm: rhythm()));

    final bars = find.descendant(
      of: find.byType(SpendingRhythmCard),
      matching: find.byType(ChartBar),
    );
    expect(bars, findsNWidgets(7));
    for (var index = 0; index < 7; index++) {
      final size = tester.getSize(bars.at(index));
      expect(size.width, greaterThan(0), reason: 'bar $index has no width');
      expect(size.height, greaterThan(0), reason: 'bar $index has no height');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a month with nothing recorded still gets a stub', (
    tester,
  ) async {
    // The stub is what makes an empty month read as a quiet one rather than as a
    // missing one, so it has to have area too.
    final points = <CompositionPoint>[
      CompositionPoint(
        month: DateTime(2026, 1),
        totals: const CompositionTotals(
          incomeMinor: 0,
          expenseMinor: 0,
          investmentMinor: 0,
        ),
        isPartial: false,
      ),
      CompositionPoint(
        month: DateTime(2026, 2),
        totals: const CompositionTotals(
          incomeMinor: 1000000,
          expenseMinor: 500000,
          investmentMinor: 0,
        ),
        isPartial: false,
      ),
    ];

    await pumpChart(tester, CompositionOverTimeCard(points: points));

    final stubs = find.descendant(
      of: find.byType(CompositionOverTimeCard),
      matching: find.byType(ChartBar),
    );
    expect(stubs, findsOneWidget);
    expect(tester.getSize(stubs).width, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
