import 'package:finance_app/data/repository_scope.dart';
import 'package:finance_app/data/security/app_lock.dart';
import 'package:finance_app/data/security/app_lock_scope.dart';
import 'package:finance_app/features/lock/app_lock_gate.dart';
import 'package:finance_app/features/settings/widgets/app_lock_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// The app lock, without a platform plugin.
///
/// `local_auth` cannot run under `flutter test`, which is why the gate talks to
/// an [AppLock] rather than to the plugin: every decision worth asserting — when
/// the lock screen appears, what a dismissed prompt means, whether leaving the
/// app re-locks it — is on this side of that seam.
void main() {
  /// A gate over a stand-in for the app, so a test is about the lock rather than
  /// about the ledger.
  Future<AppLockController> pumpGate(
    WidgetTester tester,
    FakeAppLock lock, {
    bool enabled = true,
    Duration relockAfter = Duration.zero,
  }) async {
    final controller = AppLockController(lock: lock)..setEnabled(enabled);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      AppLockScope(
        controller: controller,
        child: MaterialApp(
          home: const Scaffold(body: Text('the ledger')),
          builder: (BuildContext context, Widget? child) => AppLockGate(
            relockAfter: relockAfter,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  /// Drives the platform lifecycle the way a phone does — through `inactive` and
  /// `hidden` — because a direct jump between `resumed` and `paused` is not a
  /// transition the framework ever produces.
  Future<void> sendLifecycle(
    WidgetTester tester,
    List<AppLifecycleState> states,
  ) async {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
  }

  const List<AppLifecycleState> goingAway = <AppLifecycleState>[
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  const List<AppLifecycleState> comingBack = <AppLifecycleState>[
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];

  testWidgets('a locked app shows the lock screen and asks once', (
    tester,
  ) async {
    final lock = FakeAppLock(
      outcomes: <AppLockOutcome>[AppLockOutcome.cancelled],
    );
    await pumpGate(tester, lock);

    expect(lock.attempts, 1);
    expect(find.text('Cubby is locked'), findsOneWidget);
    // The ledger stays mounted underneath so unlocking returns the user to
    // where they were — but its semantics are hidden, so a screen reader cannot
    // read a ledger that is meant to be locked.
    expect(
      find.ancestor(
        of: find.text('the ledger'),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an unlocked app goes straight to the ledger', (tester) async {
    final lock = FakeAppLock();
    await pumpGate(tester, lock);

    expect(lock.attempts, 1);
    expect(find.text('Cubby is locked'), findsNothing);
    expect(find.text('the ledger'), findsOneWidget);
  });

  testWidgets('with the lock off, the platform is never asked', (tester) async {
    final lock = FakeAppLock();
    await pumpGate(tester, lock, enabled: false);

    expect(lock.attempts, 0);
    expect(find.text('Cubby is locked'), findsNothing);
    expect(find.text('the ledger'), findsOneWidget);
  });

  testWidgets('a dismissed prompt keeps the lock, and the button retries', (
    tester,
  ) async {
    final lock = FakeAppLock(
      outcomes: <AppLockOutcome>[
        AppLockOutcome.cancelled,
        AppLockOutcome.unlocked,
      ],
    );
    await pumpGate(tester, lock);

    expect(
      find.text('Cubby stays locked until you unlock it.'),
      findsOneWidget,
    );
    expect(lock.attempts, 1);

    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(lock.attempts, 2);
    expect(find.text('Cubby is locked'), findsNothing);
    expect(find.text('the ledger'), findsOneWidget);
  });

  testWidgets('a phone with no screen lock is told, not prompted', (
    tester,
  ) async {
    final lock = FakeAppLock()..available = false;
    await pumpGate(tester, lock);

    expect(lock.attempts, 0);
    expect(find.textContaining('no screen lock set'), findsOneWidget);
  });

  testWidgets('coming back after the grace period asks again', (tester) async {
    // The second answer is a dismissal, so the lock screen is still up at the
    // end — which is what proves the re-lock actually happened. (Nothing renders
    // while the app is paused: the framework suppresses frames, so the visible
    // consequence can only be asserted once it is back.)
    final lock = FakeAppLock(
      outcomes: <AppLockOutcome>[
        AppLockOutcome.unlocked,
        AppLockOutcome.cancelled,
      ],
    );
    await pumpGate(tester, lock);
    expect(lock.attempts, 1);
    expect(find.text('Cubby is locked'), findsNothing);

    await sendLifecycle(tester, goingAway);
    await sendLifecycle(tester, comingBack);
    await tester.pumpAndSettle();

    expect(lock.attempts, 2);
    expect(find.text('Cubby is locked'), findsOneWidget);
    expect(
      find.text('Cubby stays locked until you unlock it.'),
      findsOneWidget,
    );
  });

  testWidgets('a quick trip out and back does not re-lock', (tester) async {
    // The grace period is what stops choosing a backup file, or glancing at a
    // notification, from costing a fingerprint every time.
    final lock = FakeAppLock();
    await pumpGate(tester, lock, relockAfter: const Duration(hours: 1));
    expect(lock.attempts, 1);

    await sendLifecycle(tester, goingAway);
    await sendLifecycle(tester, comingBack);
    await tester.pumpAndSettle();

    expect(lock.attempts, 1);
    expect(find.text('Cubby is locked'), findsNothing);
  });

  testWidgets('the setting asks before it changes, then remembers the answer', (
    tester,
  ) async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);
    final lock = FakeAppLock();
    final controller = AppLockController(lock: lock);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      RepositoryScope(
        snapshot: await fixture.snapshot(),
        repository: fixture.repository,
        child: AppLockScope(
          controller: controller,
          child: const MaterialApp(home: Scaffold(body: AppLockCard())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.enabled, isFalse);
    expect(
      find.text('Off — Cubby opens straight to the ledger'),
      findsOneWidget,
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    // Proving the unlock works comes first: setting a lock you cannot open is
    // worse than having none.
    expect(lock.attempts, 1);
    expect(controller.enabled, isTrue);
    expect(
      find.text('Asked when Cubby opens or returns from the background'),
      findsOneWidget,
    );

    // Read through the real async zone: drift schedules timers the fake clock
    // would otherwise leave pending.
    final persisted = await tester.runAsync(fixture.repository.appLockEnabled);
    expect(persisted, isTrue);

    // Let the confirmation snack bar time out, so its timer is not still pending
    // when the tree is torn down.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('a refused unlock changes nothing', (tester) async {
    final fixture = makeFixture();
    addTearDown(fixture.dispose);
    final lock = FakeAppLock(
      outcomes: <AppLockOutcome>[AppLockOutcome.cancelled],
    );
    final controller = AppLockController(lock: lock);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      RepositoryScope(
        snapshot: await fixture.snapshot(),
        repository: fixture.repository,
        child: AppLockScope(
          controller: controller,
          child: const MaterialApp(home: Scaffold(body: AppLockCard())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(controller.enabled, isFalse);
    final persisted = await tester.runAsync(fixture.repository.appLockEnabled);
    expect(persisted, isFalse);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
