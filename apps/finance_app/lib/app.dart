import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'data/finance_repository.dart';
import 'data/finance_snapshot.dart';
import 'data/repository_scope.dart';
import 'data/security/app_lock.dart';
import 'data/security/app_lock_scope.dart';
import 'features/lock/app_lock_gate.dart';
import 'features/shell/home_shell.dart';

/// Application root.
///
/// The repository is injected here rather than reached for globally, which is
/// what lets a widget test supply a fixed snapshot, and what let the demo
/// repository be replaced by the encrypted database without touching a screen.
class FinanceApp extends StatelessWidget {
  const FinanceApp({
    required this.repository,
    this.initialSnapshot,
    this.appLock,
    this.appLockEnabled = false,
    super.key,
  });

  final FinanceRepository repository;

  /// A snapshot to render immediately, used by tests so they need not wait for a
  /// database round trip.
  final FinanceSnapshot? initialSnapshot;

  /// The platform unlock, or null in a build that has none.
  ///
  /// Optional so a widget test never reaches for a plugin: absent, the gate is
  /// given one that reports it cannot ask, and the app behaves exactly as it did
  /// before this feature existed.
  final AppLock? appLock;

  /// Whether the lock was on when the app started, read from the database before
  /// the first frame.
  final bool appLockEnabled;

  @override
  Widget build(BuildContext context) => _Root(
    repository: repository,
    initialSnapshot: initialSnapshot,
    appLock: appLock,
    appLockEnabled: appLockEnabled,
  );
}

/// Holds the snapshot subscription and rebuilds the tree on every emission.
class _Root extends StatefulWidget {
  const _Root({
    required this.repository,
    required this.initialSnapshot,
    required this.appLock,
    required this.appLockEnabled,
  });

  final FinanceRepository repository;
  final FinanceSnapshot? initialSnapshot;
  final AppLock? appLock;
  final bool appLockEnabled;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  /// Created once. Building the stream inside `build` would resubscribe to the
  /// database on every rebuild.
  late final Stream<FinanceSnapshot> _snapshots = widget.repository.watch();

  /// Created once, and shared: it carries whether the lock is on for the whole
  /// session, and Settings flips it through this same instance so the gate
  /// reacts at once rather than at the next launch.
  late final AppLockController _appLock = AppLockController(
    lock: widget.appLock ?? const UnavailableAppLock(),
  )..setEnabled(widget.appLockEnabled);

  @override
  void dispose() {
    _appLock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<FinanceSnapshot>(
      stream: _snapshots,
      initialData: widget.initialSnapshot,
      builder: (context, asyncSnapshot) {
        final snapshot = asyncSnapshot.data;
        // RepositoryScope must sit ABOVE MaterialApp, not inside `home`.
        // `showModalBottomSheet` pushes its sheet as a sibling route in
        // MaterialApp's navigator, so a scope placed inside `home` is not an
        // ancestor of the sheet and the sheet cannot find it.
        return RepositoryScope(
          snapshot: snapshot ?? FinanceSnapshot.empty(DateTime.now()),
          repository: widget.repository,
          child: AppLockScope(
            controller: _appLock,
            child: MaterialApp(
              title: 'Cubby',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: ThemeMode.system,
              // The gate is installed through `builder` rather than around
              // MaterialApp so it sits above the navigator — every pushed route
              // and dialog is covered — while still having the app's Theme and
              // MediaQuery to draw the lock screen with.
              builder: (BuildContext context, Widget? child) =>
                  AppLockGate(child: child ?? const SizedBox.shrink()),
              home: snapshot == null
                  ? const _LoadingScreen()
                  : const HomeShell(),
            ),
          ),
        );
      },
    );
  }
}

/// Shown only on the very first frame, before the first read completes.
///
/// A spinner rather than a blank screen is the difference between "loading" and
/// "broken" for a user opening the app.
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
