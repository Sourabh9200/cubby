import 'dart:convert';

import 'package:flutter/material.dart';

import 'exclusion_row.dart';

/// The expanded body of the payload preview: the literal JSON, then the list of
/// fields that are deliberately absent.
class PreviewDetails extends StatelessWidget {
  const PreviewDetails({required this.payload, super.key});

  final Map<String, Object?> payload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final json = const JsonEncoder.withIndent('  ').convert(payload);

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              json,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Never included',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          const ExclusionRow(
            label: 'Payees and merchant names',
            reason: 'the most identifying field in a statement',
            excluded: true,
          ),
          const ExclusionRow(
            label: 'Exact amounts',
            reason: 'floored to the nearest ₹100',
            excluded: true,
          ),
          const ExclusionRow(
            label: 'Account and transaction identifiers',
            reason: 'stable join keys back to your records',
            excluded: true,
          ),
          const ExclusionRow(
            label: 'Individual dates',
            reason: 'month granularity only, so no daily trace',
            excluded: true,
          ),
          const ExclusionRow(
            label: 'Category labels',
            reason:
                'user-authored text, so the one field the redactor still has '
                'to scrub',
            excluded: false,
          ),
        ],
      ),
    );
  }
}
