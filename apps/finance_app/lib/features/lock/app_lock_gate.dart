import 'package:flutter/material.dart';

import '../../data/security/app_lock.dart';
import '../../data/security/app_lock_scope.dart';

/// Holds the app behind the platform unlock.
///
/// Installed through `MaterialApp.builder` rather than around it, so the gate
/// sits *above* the navigator: a pushed report or an open sheet is covered too,
/// which is the difference between locking the app and locking one screen of it.
///
/// The child stays mounted underneath while locked, so unlocking returns the user
/// to the tab and scroll position they left. A lock that costs you your place is
/// one people turn off.
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    required this.child,
    this.relockAfter = const Duration(seconds: 30),
    super.key,
  });

  final Widget child;

  /// How long the app may stay in the background before coming back requires an
  /// unlock. Long enough that answering a message or choosing a backup file does
  /// not demand a fingerprint; short enough that a pocketed phone re-locks.
  final Duration relockAfter;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  /// Starts unlocked and is locked on the first dependency read when the setting
  /// is on, so the ledger is never on screen while the decision is pending.
  bool _unlocked = true;

  bool _decided = false;
  bool _asking = false;
  String? _message;

  /// When the app last went to the background, for [AppLockGate.relockAfter].
  DateTime? _backgroundedAt;

  AppLockController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppLockScope.of(context);
    _controller = controller;

    if (!_decided) {
      _decided = true;
      if (controller.enabled) {
        _unlocked = false;
        // Asked after the first frame, so the lock screen is already painted
        // behind the system prompt rather than the prompt floating over nothing.
        WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
      }
      return;
    }

    if (!controller.enabled) {
      // Switched off in Settings: stop gating from now, not from the next
      // launch.
      _unlocked = true;
      _message = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Deliberately not `inactive`: the biometric prompt itself makes the app
    // inactive, so locking on that would re-lock the instant the user answered
    // it, and would ask them forever.
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
      if (_controller?.enabled == true && _unlocked) {
        setState(() {
          _unlocked = false;
          _message = null;
        });
      }
      return;
    }
    if (state != AppLifecycleState.resumed || _controller?.enabled != true) {
      return;
    }
    if (_unlocked) {
      return;
    }

    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since != null &&
        DateTime.now().difference(since) < widget.relockAfter) {
      // Back inside the grace period: the trip out was a file picker or a glance
      // at a notification, not the phone changing hands.
      setState(() => _unlocked = true);
      return;
    }
    _ask();
  }

  /// Asks the platform to unlock, and records what it said.
  Future<void> _ask() async {
    final controller = _controller;
    if (!mounted || _asking || controller == null || !controller.enabled) {
      return;
    }
    _asking = true;
    try {
      // Availability first: a phone that cannot ask is a sentence to show, not a
      // prompt to raise.
      if (!await controller.lock.isAvailable()) {
        if (mounted) {
          setState(() {
            _unlocked = false;
            _message =
                'This phone has no screen lock set, so Cubby cannot ask you to '
                'unlock. Add a fingerprint, PIN or pattern in Android settings.';
          });
        }
        return;
      }

      final outcome = await controller.lock.authenticate();
      if (!mounted) {
        return;
      }
      setState(() {
        _unlocked = outcome == AppLockOutcome.unlocked;
        _message = switch (outcome) {
          AppLockOutcome.unlocked => null,
          AppLockOutcome.cancelled => 'Cubby stays locked until you unlock it.',
          AppLockOutcome.unavailable =>
            'Cubby could not ask you to unlock. Check that a fingerprint, PIN '
                'or pattern is set in Android settings.',
        };
      });
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppLockScope.of(context);
    if (_unlocked || !controller.enabled) {
      return widget.child;
    }
    return Stack(
      children: <Widget>[
        // Kept mounted, so unlocking returns the user to where they were. Its
        // semantics are hidden and its animations paused while it is covered, so
        // a screen reader cannot read a ledger that is meant to be locked.
        ExcludeSemantics(
          child: TickerMode(enabled: false, child: widget.child),
        ),
        Positioned.fill(
          child: _LockScreen(message: _message, onUnlock: _ask),
        ),
      ],
    );
  }
}

/// What covers the app while it is locked.
class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.message, required this.onUnlock});

  /// Why the last attempt did not succeed, when there is something to say.
  final String? message;

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Icon(
                  Icons.lock_rounded,
                  size: 52,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Cubby is locked',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(
                message ??
                    'Unlock with your fingerprint or your phone\u2019s PIN to '
                        'see your ledger.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.fingerprint_rounded),
                label: const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
