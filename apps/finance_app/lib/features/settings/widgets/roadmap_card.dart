import 'package:flutter/material.dart';

import '../../../core/widgets/section_card.dart';

/// Lists what the app deliberately does not do yet.
///
/// Stated plainly on the settings screen rather than left for the user to
/// discover. A finance app that implies features it lacks is worse than one
/// that admits the gap, because the user may rely on it.
class RoadmapCard extends StatelessWidget {
  const RoadmapCard({required this.pending, super.key});

  final List<String> pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: 'Not built yet',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final item in pending)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.schedule_rounded,
                    size: 15,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      item,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
