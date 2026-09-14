import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// One line in the "what is not sent" checklist.
class ExclusionRow extends StatelessWidget {
  const ExclusionRow({
    required this.label,
    required this.reason,
    required this.excluded,
    super.key,
  });

  final String label;
  final String reason;
  final bool excluded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            excluded
                ? Icons.check_circle_outline_rounded
                : Icons.warning_amber_rounded,
            size: 16,
            color: excluded ? money.income : money.warning,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall,
                children: <TextSpan>[
                  TextSpan(
                    text: '$label — ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: reason,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
