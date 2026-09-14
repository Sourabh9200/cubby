import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'data/finance_repository.dart';
import 'data/finance_snapshot.dart';
import 'data/repository_scope.dart';
import 'features/shell/home_shell.dart';

/// Application root.
///
/// The repository is injected here rather than reached for globally, which is
/// what lets a widget test supply a fixed snapshot, and what let the demo
/// repository be replaced by the encrypted database without touching a screen.
class FinanceApp extends StatelessWidget {
  const FinanceApp({required this.repository, this.initialSnapshot, super.key});

  final FinanceRepository repository;

  /// A snapshot to render immediately, used by tests so they need not wait for a
  /// database round trip.
  final FinanceSnapshot? initialSnapshot;

  @override
  Widget build(BuildContext context) =>
      _Root(repository: repository, initialSnapshot: initialSnapshot);
}

/// Holds the snapshot subscription and rebuilds the tree on every emission.
class _Root extends StatefulWidget {
  const _Root({required this.repository, this.initialSnapshot});

  final FinanceRepository repository;
  final FinanceSnapshot? initialSnapshot;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  /// Created once. Building the stream inside `build` would resubscribe to the
  /// database on every rebuild.
  late final Stream<FinanceSnapshot> _snapshots = widget.repository.watch();

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
          child: MaterialApp(
            title: 'Cubby',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: ThemeMode.system,
            home: snapshot == null ? const _LoadingScreen() : const HomeShell(),
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
