import 'package:finance_app/features/settings/widgets/backup_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The passphrase dialog on a short phone with the keyboard up.
///
/// A layout regression test, not a behaviour one. The dialog's content was not
/// scrollable, so once the keyboard took the bottom of the screen the content
/// overflowed and painted *over* the actions row — which is why the repeat field
/// ended up underneath the "Create backup" button, unreadable while it was being
/// typed.
void main() {
  testWidgets('fits on a short screen with the keyboard up', (tester) async {
    // A 360x667 dp phone, the shape of a small handset in portrait.
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) => MediaQuery(
          // The keyboard, covering the bottom of the screen. `Dialog` folds
          // `viewInsets` into its padding, so this is what shrinks the dialog.
          data: MediaQuery.of(context)
              .copyWith(viewInsets: const EdgeInsets.only(bottom: 280)),
          child: child ?? const SizedBox.shrink(),
        ),
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showDialog<String>(
              context: context,
              builder: (_) => const PassphraseDialog(confirm: true),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a passphrase'), findsOneWidget);
    expect(find.text('Repeat passphrase'), findsOneWidget);

    // Scrollable, so the repeat field can always be brought clear of the
    // keyboard rather than being drawn underneath the buttons.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Scrollable),
      ),
      findsWidgets,
    );

    // And the actions stay put, below everything else.
    expect(find.text('Create backup'), findsOneWidget);
  });
}
