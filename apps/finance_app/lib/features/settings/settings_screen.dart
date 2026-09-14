import 'package:flutter/material.dart';

import '../../core/widgets/section_card.dart';
import '../../data/repository_scope.dart';
import '../../data/snapshot_views.dart';
import '../budgets/budgets_screen.dart';
import 'widgets/action_tile.dart';
import 'widgets/ai_engine_card.dart';
import 'widgets/privacy_card.dart';
import 'widgets/roadmap_card.dart';

/// Settings, ordered by what a privacy-conscious user wants to verify first.
///
/// Privacy status sits at the top rather than buried under an About screen,
/// because "where is my financial data" is the first question anyone asks of an
/// app like this, and the answer should not require hunting for it.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _cloudEngine = false;
  bool _busy = false;

  /// Whether the database file is genuinely encrypted, or null while unknown.
  bool? _encrypted;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_encrypted == null && !_busy) {
      _refreshEncryptionStatus();
    }
  }

  Future<void> _refreshEncryptionStatus() async {
    final repository = RepositoryScope.actions(context);
    final encrypted = await repository.verifyEncrypted();
    if (mounted) {
      setState(() => _encrypted = encrypted);
    }
  }

  Future<void> _loadSampleData() async {
    setState(() => _busy = true);
    final repository = RepositoryScope.actions(context);
    final messenger = ScaffoldMessenger.of(context);
    final count = await repository.loadSampleData();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    messenger.showSnackBar(
      SnackBar(content: Text('Added $count sample transactions.')),
    );
  }

  Future<void> _eraseSampleData() async {
    setState(() => _busy = true);
    final repository = RepositoryScope.actions(context);
    final messenger = ScaffoldMessenger.of(context);
    await repository.eraseSampleData();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Sample data removed. Your own entries were kept.'),
      ),
    );
  }

  Future<void> _eraseAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Erase every transaction?'),
        content: const Text(
          'This removes your own entries as well as any sample data. Your '
          'categories, accounts, and budgets stay. It cannot be undone from '
          'inside the app.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Erase everything'),
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
    await repository.eraseTransactions();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    messenger.showSnackBar(
      const SnackBar(content: Text('All transactions erased.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = RepositoryScope.of(context);
    final sampleCount = snapshot.sampleTransactionCount;
    final ownCount = snapshot.ownTransactionCount;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        PrivacyCard(encrypted: _encrypted),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Your data',
          trailing: Text(
            '$ownCount yours · $sampleCount sample',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          child: Column(
            children: <Widget>[
              ActionTile(
                icon: Icons.auto_awesome_rounded,
                title: 'Load sample data',
                subtitle: 'Six months of plausible history, to try the charts',
                enabled: !_busy,
                onTap: _loadSampleData,
              ),
              ActionTile(
                icon: Icons.cleaning_services_rounded,
                title: 'Remove sample data',
                subtitle: sampleCount == 0
                    ? 'No sample entries to remove'
                    : 'Removes $sampleCount sample entries and keeps your own',
                enabled: !_busy && sampleCount > 0,
                onTap: _eraseSampleData,
              ),
              ActionTile(
                icon: Icons.delete_forever_rounded,
                title: 'Erase every transaction',
                subtitle: ownCount == 0 && sampleCount == 0
                    ? 'Nothing to erase'
                    : 'Deletes all ${ownCount + sampleCount} entries, '
                          'including your own',
                enabled: !_busy && (ownCount + sampleCount) > 0,
                onTap: _eraseAll,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Budgets',
          child: ActionTile(
            icon: Icons.tune_rounded,
            title: 'Categories & budgets',
            subtitle: 'Set or change the limit for any expense category',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BudgetsScreen()),
            ),
          ),
        ),
        const SizedBox(height: 14),
        AiEngineCard(
          cloudEnabled: _cloudEngine,
          onChanged: (value) => setState(() => _cloudEngine = value),
        ),
        const SizedBox(height: 14),
        const RoadmapCard(
          pending: <String>[
            'Importing a bank statement (CSV)',
            'Receipt photos and OCR',
            'Monthly PDF export',
            'Encrypted backup and restore',
            'Budget alerts as notifications',
            'Unlock with fingerprint or PIN',
            'Editing an existing entry',
          ],
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(
            'Version 1.0.0',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
