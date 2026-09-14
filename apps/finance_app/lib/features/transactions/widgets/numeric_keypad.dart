import 'package:flutter/material.dart';

/// Numeric pad, sized for thumbs.
///
/// A dedicated pad rather than the system keyboard: the system numeric keyboard
/// varies by device and input mode, and on many Android builds it steals half
/// the screen. A fixed 4x3 grid keeps the amount, the category, and the buttons
/// all visible at once, which is what makes entry fast.
class NumericKeypad extends StatelessWidget {
  const NumericKeypad({required this.onKey, super.key});

  /// Emits `0`-`9`, `.`, or `del`.
  final ValueChanged<String> onKey;

  static const List<List<String>> _rows = <List<String>>[
    <String>['1', '2', '3'],
    <String>['4', '5', '6'],
    <String>['7', '8', '9'],
    <String>['.', '0', 'del'],
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        for (final row in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: <Widget>[
                for (final key in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Material(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => onKey(key),
                          child: SizedBox(
                            height: 52,
                            child: Center(
                              child: key == 'del'
                                  ? const Icon(
                                      Icons.backspace_outlined,
                                      size: 20,
                                    )
                                  : Text(
                                      key,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
