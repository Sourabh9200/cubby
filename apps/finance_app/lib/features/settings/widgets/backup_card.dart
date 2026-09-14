import 'package:flutter/material.dart';

import '../../../core/widgets/section_card.dart';
import '../../../data/backup/backup_crypto.dart';
import '../../../data/backup/backup_failure.dart';
import '../../../data/backup/backup_file_store.dart';
import '../../../data/repository_scope.dart';
import 'action_tile.dart';

/// Backup and restore, as one encrypted file the user keeps.
///
/// The card leads with *why* this exists rather than with what it does. The
/// database key lives in the phone's keystore, which is what makes the file
/// unreadable to anyone else — and also what makes it die with the app. A user
/// who does not know that will not understand why a local-first app needs a
/// backup at all, and will not make one.
class BackupCard extends StatefulWidget {
  const BackupCard({this.fileStore, super.key});

  /// Injected by tests, which have no platform file dialog to call. The app
  /// uses the system one.
  final BackupFileStore? fileStore;

  @override
  State<BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<BackupCard> {
  bool _busy = false;

  late final BackupFileStore _files =
      widget.fileStore ?? const SystemBackupFileStore();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: 'Backup & restore',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Cubby\u2019s encryption key is held on this phone, so your data '
            'cannot follow the app through a reinstall. A backup is one file '
            'you keep elsewhere: it reopens on a fresh install, or on another '
            'phone, with the passphrase you choose.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          ActionTile(
            icon: Icons.enhanced_encryption_rounded,
            title: 'Create encrypted backup',
            subtitle: _busy
                ? 'Working\u2026'
                : 'One file, protected by a passphrase you choose',
            enabled: !_busy,
            onTap: _createBackup,
          ),
          ActionTile(
            icon: Icons.settings_backup_restore_rounded,
            title: 'Restore from backup',
            subtitle: 'Replaces everything currently in the app',
            enabled: !_busy,
            onTap: _restore,
          ),
        ],
      ),
    );
  }

  /// Seals a snapshot and hands it to the save dialog.
  Future<void> _createBackup() async {
    final passphrase = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const PassphraseDialog(confirm: true),
    );
    if (passphrase == null || !mounted) {
      return;
    }

    setState(() => _busy = true);
    final repository = RepositoryScope.actions(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await repository.exportBackup(passphrase: passphrase);
      final where = await _files.save(fileName: _fileName(), bytes: bytes);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            where == null
                ? 'No file was saved. Your data is unchanged.'
                : 'Backup saved. Keep it somewhere you will find it again — '
                      'Cubby cannot recover the passphrase for you.',
          ),
        ),
      );
    } on BackupFailure catch (failure) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// `cubby-backup-20260914.cubby` — sorted by name is sorted by date.
  String _fileName() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return 'cubby-backup-${now.year}$month$day.cubby';
  }

  /// Picks a file, asks for its passphrase, and replaces the ledger with it.
  Future<void> _restore() async {
    final picked = await _files.pick();
    if (picked == null || !mounted) {
      return;
    }
    final passphrase = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const PassphraseDialog(confirm: false),
    );
    if (passphrase == null || !mounted) {
      return;
    }

    // Destructive, and not undoable from inside the app, so it is confirmed
    // with the file's name in front of the user rather than a generic warning.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Replace everything?'),
        content: Text(
          'Restoring "${picked.name}" removes every entry, budget change, '
          'category and recurring rule currently in the app, and puts the '
          'backup in their place. This cannot be undone from inside Cubby.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Replace everything'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _busy = true);
    final repository = RepositoryScope.actions(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final report = await repository.restoreBackup(
        bytes: picked.bytes,
        passphrase: passphrase,
      );
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Restored ${_entries(report.transactions)}, '
            '${report.categories} categories and '
            '${report.recurringRules} recurring rules.',
          ),
        ),
      );
    } on BackupFailure catch (failure) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// "1 entry" / "4 entries", so no line reads "1 entries".
  String _entries(int count) => count == 1 ? '1 entry' : '$count entries';
}

/// Asks for the passphrase that protects a backup.
///
/// A dialog rather than an inline field for two reasons. The value should not be
/// visible in the settings list, where a screenshot would carry it; and creating
/// a backup needs it entered twice, because a mistyped passphrase produces a file
/// that nobody — including the user — can ever open again.
class PassphraseDialog extends StatefulWidget {
  const PassphraseDialog({required this.confirm, super.key});

  /// True when creating a backup: asks twice and enforces a minimum length.
  /// False when restoring, where the passphrase is whatever was chosen before.
  final bool confirm;

  @override
  State<PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<PassphraseDialog> {
  final TextEditingController _passphrase = TextEditingController();
  final TextEditingController _repeat = TextEditingController();

  /// Shown under the first field: the length rule, or nothing.
  String? _passphraseError;

  /// Shown under the repeat field, which is where a mismatch actually is.
  String? _repeatError;

  @override
  void dispose() {
    _passphrase.dispose();
    _repeat.dispose();
    super.dispose();
  }

  /// Clears both complaints as soon as the user edits either field.
  ///
  /// A red message left under a field the user has already corrected reads as a
  /// refusal to accept the fix — and this dialog is the one place in the app
  /// where getting a detail exactly right is the whole point.
  void _clearErrors() {
    if (_passphraseError == null && _repeatError == null) {
      return;
    }
    setState(() {
      _passphraseError = null;
      _repeatError = null;
    });
  }

  void _submit() {
    final value = _passphrase.text;
    if (widget.confirm) {
      final minimum = BackupCrypto.minimumPassphraseLength;
      if (value.length < minimum) {
        // The entered length is stated on purpose. "Too short" alone is
        // indistinguishable from a keyboard that never delivered the text at
        // all, and this app runs on phones whose manufacturers swap in a
        // separate secure keyboard for password fields.
        setState(
          () => _passphraseError =
              'Use at least $minimum characters. That one was ${value.length}.',
        );
        return;
      }
      if (value != _repeat.text) {
        setState(() {
          _passphraseError = null;
          _repeatError = 'The two passphrases do not match.';
        });
        return;
      }
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      // Scrollable, so the fields can always be brought clear of the keyboard.
      // Without it the content overflows a short screen once the keyboard is up
      // and paints over the actions row, which puts the repeat field underneath
      // the "Create backup" button exactly while it is being typed.
      scrollable: true,
      title: Text(
        widget.confirm ? 'Choose a passphrase' : 'Enter your passphrase',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            widget.confirm
                ? 'Cubby cannot recover this passphrase. Without it the backup '
                      'cannot be opened — not by you and not by us.'
                : 'The passphrase you chose when this backup was created.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passphrase,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Passphrase',
              // Stated before the mistake, not only after it.
              helperText: widget.confirm
                  ? 'At least ${BackupCrypto.minimumPassphraseLength} '
                        'characters'
                  : null,
              errorText: _passphraseError,
            ),
            onChanged: (_) => _clearErrors(),
            onSubmitted: widget.confirm ? null : (_) => _submit(),
          ),
          if (widget.confirm) ...<Widget>[
            const SizedBox(height: 12),
            TextField(
              controller: _repeat,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Repeat passphrase',
                errorText: _repeatError,
              ),
              onChanged: (_) => _clearErrors(),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirm ? 'Create backup' : 'Restore'),
        ),
      ],
    );
  }
}
