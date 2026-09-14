import 'dart:typed_data';

import 'package:finance_app/data/backup/backup_failure.dart';
import 'package:finance_app/data/backup/backup_file_store.dart';
import 'package:finance_app/data/repository_scope.dart';
import 'package:finance_app/features/settings/widgets/backup_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// The backup path, end to end, against the real encrypted-database stack.
///
/// The point of these is the property the feature exists for: after the ledger
/// is gone, a backup brings it back. Everything else — the format, the dialog,
/// the file dialog — is in service of that one outcome.
void main() {
  const String passphrase = 'a good passphrase';

  test('a backup brings the ledger back after it is wiped', () async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);
    await seedMinimal(fixture);

    final bytes = await fixture.repository.exportBackup(passphrase: passphrase);
    expect(bytes, isNotEmpty);

    // Simulate the loss the feature exists to survive.
    await fixture.repository.eraseTransactions();
    expect((await fixture.snapshot()).transactions, isEmpty);

    final report = await fixture.repository.restoreBackup(
      bytes: bytes,
      passphrase: passphrase,
    );
    expect(report.transactions, 2);

    final restored = await fixture.snapshot();
    expect(restored.transactions, hasLength(2));
    expect(
      restored.transactions.map((txn) => txn.payee),
      containsAll(<String>['BigBasket', 'Salary credit']),
    );
  });

  test('a wrong passphrase leaves the ledger untouched', () async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);
    await seedMinimal(fixture);
    final bytes = await fixture.repository.exportBackup(passphrase: passphrase);

    await expectLater(
      fixture.repository.restoreBackup(
        bytes: bytes,
        passphrase: 'the wrong passphrase',
      ),
      throwsA(isA<BackupFailure>()),
    );

    // Decryption is attempted before the replace, so nothing was lost.
    expect((await fixture.snapshot()).transactions, hasLength(2));
  });

  testWidgets('the card refuses a passphrase it could not protect', (
    tester,
  ) async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);
    await seedMinimal(fixture);
    final files = InMemoryBackupFileStore();

    await tester.pumpWidget(
      RepositoryScope(
        snapshot: await fixture.snapshot(),
        repository: fixture.repository,
        child: MaterialApp(
          home: Scaffold(body: BackupCard(fileStore: files)),
        ),
      ),
    );

    expect(find.text('Create encrypted backup'), findsOneWidget);
    expect(find.text('Restore from backup'), findsOneWidget);

    await tester.tap(find.text('Create encrypted backup'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a passphrase'), findsOneWidget);

    // Too short: refused before anything is encrypted or written.
    await tester.enterText(find.byType(TextField).first, 'short');
    await tester.tap(find.text('Create backup'));
    await tester.pumpAndSettle();
    expect(
      find.text('Use at least 8 characters. That one was 5.'),
      findsOneWidget,
    );
    expect(files.savedBytes, isNull);

    // Correcting the field clears the complaint, instead of leaving it sitting
    // under a field the user has already fixed.
    await tester.enterText(find.byType(TextField).first, passphrase);
    await tester.pumpAndSettle();
    expect(find.textContaining('That one was'), findsNothing);

    // Entered twice and differently: a mistyped passphrase would produce a file
    // nobody can open, so it is caught here.
    await tester.enterText(find.byType(TextField).first, passphrase);
    await tester.enterText(find.byType(TextField).last, 'a different one');
    await tester.tap(find.text('Create backup'));
    await tester.pumpAndSettle();
    expect(find.text('The two passphrases do not match.'), findsOneWidget);
    expect(files.savedBytes, isNull);
  });

  testWidgets('restore asks for confirmation before replacing anything', (
    tester,
  ) async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);
    await seedMinimal(fixture);

    // A file that exists but is not ours: the confirmation must come before any
    // attempt to read it, so the choice belongs to the user, not to the parser.
    final files = InMemoryBackupFileStore(
      nextPick: PickedBackup(
        name: 'cubby-backup-20260914.cubby',
        bytes: Uint8List.fromList(List<int>.filled(96, 3)),
      ),
    );

    await tester.pumpWidget(
      RepositoryScope(
        snapshot: await fixture.snapshot(),
        repository: fixture.repository,
        child: MaterialApp(
          home: Scaffold(body: BackupCard(fileStore: files)),
        ),
      ),
    );

    await tester.tap(find.text('Restore from backup'));
    await tester.pumpAndSettle();

    // The passphrase comes first, then the destructive confirmation.
    await tester.enterText(find.byType(TextField).first, passphrase);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(find.text('Replace everything?'), findsOneWidget);
    expect(find.textContaining('cubby-backup-20260914.cubby'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Replace everything?'), findsNothing);

    // Read the database in the real async zone: drift's query streams schedule
    // timers that the widget test's fake clock would leave pending at teardown.
    final snapshot = await tester.runAsync(fixture.snapshot);
    expect(snapshot!.transactions, hasLength(2));
  });
}
