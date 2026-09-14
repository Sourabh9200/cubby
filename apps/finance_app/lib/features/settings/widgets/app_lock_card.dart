import 'package:flutter/material.dart';

import '../../../core/widgets/section_card.dart';
import '../../../data/repository_scope.dart';
import '../../../data/security/app_lock.dart';
import '../../../data/security/app_lock_scope.dart';

/// Turns the screen-level lock on and off.
///
/// Both directions ask the platform to confirm who is holding the phone before
/// anything changes. Turning it *on* without proving the unlock works would let
/// someone set a lock they cannot open; turning it *off* without a check would
/// let anyone who picked up the phone remove it — which is the whole thing the
/// lock exists to prevent.
class AppLockCard extends StatefulWidget {
  const AppLockCard({super.key});

  @override
  State<AppLockCard> createState() => _AppLockCardState();
}

class _AppLockCardState extends State<AppLockCard> {
  bool _busy = false;

  Future<void> _set(bool wanted) async {
    final controller = AppLockScope.of(context);
    final repository = RepositoryScope.actions(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busy = true);
    try {
      if (wanted && !await controller.lock.isAvailable()) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'This phone has no screen lock set. Add a fingerprint, PIN or '
              'pattern in Android settings first.',
            ),
          ),
        );
        return;
      }

      final outcome = await controller.lock.authenticate();
      if (!mounted) {
        return;
      }
      if (outcome != AppLockOutcome.unlocked) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Not changed — Cubby could not confirm it was you.'),
          ),
        );
        return;
      }

      // Persisted first, then the in-memory flag: if the write fails, the tree
      // must not believe the lock is on when the next launch disagrees.
      await repository.setAppLockEnabled(wanted);
      if (!mounted) {
        return;
      }
      controller.setEnabled(wanted);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            wanted
                ? 'Lock is on. Cubby will ask for your fingerprint next time it '
                      'opens or comes back from the background.'
                : 'Lock is off. Cubby opens straight to your ledger.',
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not change the lock: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = AppLockScope.of(context);
    return SectionCard(
      title: 'App lock',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Your ledger is already encrypted with a key held in this '
            'phone\u2019s keystore. This puts a lock screen in front of it, so '
            'someone who picks up your unlocked phone cannot read your spending.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.fingerprint_rounded),
            title: const Text('Unlock with fingerprint or PIN'),
            subtitle: Text(
              controller.enabled
                  ? 'Asked when Cubby opens or returns from the background'
                  : 'Off — Cubby opens straight to the ledger',
            ),
            value: controller.enabled,
            onChanged: _busy ? null : _set,
          ),
        ],
      ),
    );
  }
}
