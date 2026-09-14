import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/section_card.dart';
import 'status_line.dart';

/// The privacy status block.
///
/// The encryption line is driven by a real header check on the database file,
/// including the failure case. If encryption is somehow not active, this says
/// so in the strongest terms rather than showing a reassuring green tick —
/// a user who believes their financial data is encrypted when it is not has
/// lost the ability to make an informed choice about storing it.
class PrivacyCard extends StatelessWidget {
  const PrivacyCard({required this.encrypted, super.key});

  /// True when verified encrypted, false when verified plaintext, null while
  /// the check is still running.
  final bool? encrypted;

  @override
  Widget build(BuildContext context) {
    final money = MoneyColors.of(context);
    return SectionCard(
      title: 'Privacy',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          StatusLine(
            icon: encrypted == true
                ? Icons.lock_rounded
                : Icons.lock_open_rounded,
            color: encrypted == true ? money.income : money.warning,
            title: switch (encrypted) {
              true => 'Database is encrypted',
              false => 'Database is NOT encrypted',
              null => 'Checking encryption…',
            },
            subtitle: switch (encrypted) {
              true =>
                'Verified by reading the file header: it is not plain SQLite, '
                    'so the contents are unreadable without the key held in '
                    'your device keystore.',
              false =>
                'The database file is readable as plain SQLite. The passphrase '
                    'is not being applied — treat this as a bug and do not '
                    'store real data yet.',
              null => 'Reading the database header to confirm.',
            },
          ),
          StatusLine(
            icon: Icons.storage_rounded,
            color: money.income,
            title: 'Data never leaves this device',
            subtitle: 'There is no server, no account, and no sync.',
          ),
          StatusLine(
            icon: Icons.wifi_off_rounded,
            color: money.income,
            title: 'No telemetry, no analytics',
            subtitle:
                'No background requests, no usage reporting, no crash '
                'uploading.',
          ),
        ],
      ),
    );
  }
}
