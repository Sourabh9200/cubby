import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/section_card.dart';

/// The switch that permits a cloud model, plus the disclosure that has to
/// accompany it.
///
/// The disclosure is not boilerplate. On the free tier of every major provider,
/// submitted content may be used to improve their products, and human review is
/// possible. A user enabling this deserves to know that in the same view as the
/// switch, not in a linked policy.
class AiEngineCard extends StatelessWidget {
  const AiEngineCard({
    required this.cloudEnabled,
    required this.onChanged,
    super.key,
  });

  final bool cloudEnabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);

    return SectionCard(
      title: 'AI assistant',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SwitchListTile(
            value: cloudEnabled,
            onChanged: onChanged,
            title: const Text('Allow a cloud model'),
            subtitle: const Text(
              'Off by default. When on, only the aggregates shown in the '
              'assistant preview are sent — never payees, notes, exact '
              'amounts, or account identifiers.',
            ),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: money.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: money.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The free tier of most providers uses your content to '
                    'improve their products, and human review is possible. A '
                    'paid key does not. That is your call to make, which is why '
                    'the app asks rather than decides.',
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
