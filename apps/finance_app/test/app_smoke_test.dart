import 'package:finance_app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

void main() {
  testWidgets('dashboard renders on a fresh install without crashing', (
    tester,
  ) async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);

    await tester.pumpWidget(
      FinanceApp(
        repository: fixture.repository,
        initialSnapshot: await fixture.snapshot(),
      ),
    );
    await tester.pumpAndSettle();

    // A brand-new install has no entries, so the headline is ₹0 and the donut
    // shows an empty state — not a crash and not a blank panel.
    expect(find.textContaining('Spent this month'), findsOneWidget);
    expect(find.text('Spending pace'), findsOneWidget);
    expect(find.text('Where it went'), findsOneWidget);
    expect(find.text('No spending yet'), findsOneWidget);

    for (final label in <String>[
      'Overview',
      'Ledger',
      'Trends',
      'Ask',
      'Settings',
    ]) {
      expect(find.text(label), findsWidgets, reason: 'missing tab: $label');
    }
  });

  testWidgets('a recorded expense appears in the ledger', (tester) async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);
    await seedMinimal(fixture);

    await tester.pumpWidget(
      FinanceApp(
        repository: fixture.repository,
        initialSnapshot: await fixture.snapshot(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ledger'));
    await tester.pumpAndSettle();

    expect(find.text('BigBasket'), findsOneWidget);
    expect(find.text('Salary credit'), findsOneWidget);
  });

  testWidgets('ledger search narrows the list', (tester) async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);
    await seedMinimal(fixture);

    await tester.pumpWidget(
      FinanceApp(
        repository: fixture.repository,
        initialSnapshot: await fixture.snapshot(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ledger'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'zzznotamerchant');
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches'), findsOneWidget);
  });

  testWidgets('assistant preview discloses what would be transmitted', (
    tester,
  ) async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);

    await tester.pumpWidget(
      FinanceApp(
        repository: fixture.repository,
        initialSnapshot: await fixture.snapshot(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();

    expect(find.text('Runs entirely on this device'), findsOneWidget);

    await tester.tap(find.text('Runs entirely on this device'));
    await tester.pumpAndSettle();

    expect(find.text('Never included'), findsOneWidget);
    // The exclusion rows are RichText, so the finder must opt into spans.
    expect(
      find.textContaining('Payees and merchant names', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Exact amounts', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('settings surfaces the data controls', (tester) async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);

    await tester.pumpWidget(
      FinanceApp(
        repository: fixture.repository,
        initialSnapshot: await fixture.snapshot(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Data never leaves this device'), findsOneWidget);
    expect(find.text('Load sample data'), findsOneWidget);
    expect(find.text('Remove sample data'), findsOneWidget);
    expect(find.text('Erase every transaction'), findsOneWidget);
  });
}
