import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'preview_details.dart';

/// Shows the user exactly what would leave the device.
///
/// This panel is what makes the privacy design credible rather than
/// aspirational. A consent dialog that *describes* what will be sent asks the
/// user to trust a description; showing the literal serialized payload does
/// not. It is also the fastest way to catch a regression — if a payee name ever
/// appeared here, the mistake would be visible before any request is made.
class PayloadPreviewCard extends StatefulWidget {
  const PayloadPreviewCard({
    required this.payload,
    this.cloudEnabled = false,
    super.key,
  });

  final Map<String, Object?> payload;

  /// Whether a network engine is currently permitted. When false the payload is
  /// still shown, so the user can see the shape of what *would* be sent.
  final bool cloudEnabled;

  @override
  State<PayloadPreviewCard> createState() => _PayloadPreviewCardState();
}

class _PayloadPreviewCardState extends State<PayloadPreviewCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final accent = widget.cloudEnabled ? money.warning : money.income;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: <Widget>[
                  Icon(
                    widget.cloudEnabled
                        ? Icons.cloud_upload_outlined
                        : Icons.shield_outlined,
                    size: 20,
                    color: accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.cloudEnabled
                              ? 'Cloud engine is enabled'
                              : 'Runs entirely on this device',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.cloudEnabled
                              ? 'Tap to see the exact payload that would be sent.'
                              : 'Tap to see what a cloud model would receive. '
                                    'Nothing has been transmitted.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...<Widget>[
            const Divider(height: 1),
            PreviewDetails(payload: widget.payload),
          ],
        ],
      ),
    );
  }
}
