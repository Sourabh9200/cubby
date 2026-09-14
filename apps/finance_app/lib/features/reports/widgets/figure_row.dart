import 'package:flutter/material.dart';

/// One figure in a report: what it is, what it comes to, and a line of context.
///
/// Shared by the reports screen and the year in review so the two cannot drift
/// apart in spacing or emphasis. The detail line is where honesty goes in this
/// app — "12% more than the previous month", "avg ₹240", "measured against
/// today's limits" — because a figure with no qualifier is the one that misleads.
class FigureRow extends StatelessWidget {
  const FigureRow({
    required this.label,
    required this.value,
    this.detail,
    this.color,
    this.onTap,
    super.key,
  });

  final String label;

  /// Already formatted: this widget does not decide how money reads.
  final String value;

  final String? detail;

  /// Tints the figure. Used for the three measures so a spend is red and income
  /// green in a table where the labels alone would have to be read carefully.
  final Color? color;

  /// Makes the row a link. Rows are tappable only when there is somewhere to go.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = this.detail;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (detail != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );

    if (onTap == null) {
      return row;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }
}
