/// User-supplied deny-list detector.
///
/// Pattern detection cannot find a person's name written in prose, and that is
/// the single most common way a real leak would happen here: the user's own
/// name, a landlord, an employer, a doctor. The app lets the user register
/// those words explicitly, which converts an unsolvable NLP problem into a
/// trivial lookup.
library;

import '../pii.dart';

/// Matches any of a fixed set of literal keywords, case-insensitively.
class KeywordDetector implements PiiDetector {
  /// Creates a detector over [keywords].
  ///
  /// Blank and one-character keywords are dropped: a one-letter "name" such as
  /// `A` would redact the indefinite article out of every sentence.
  KeywordDetector(Iterable<String> keywords, {this.kind = PiiKind.custom})
    : _keywords =
          keywords
              .map((keyword) => keyword.trim())
              .where((keyword) => keyword.length > 1)
              .toSet()
              .toList()
            ..sort((a, b) => b.length.compareTo(a.length));

  final List<String> _keywords;

  @override
  final PiiKind kind;

  /// A registered name is matched literally, so no anchor is involved.
  @override
  bool get isContextAnchored => false;

  /// True when there is nothing to match, so the scanner can skip this
  /// detector entirely on the hot path.
  bool get isEmpty => _keywords.isEmpty;

  @override
  Iterable<PiiSpan> detect(String input) sync* {
    if (_keywords.isEmpty) {
      return;
    }
    final haystack = input.toLowerCase();
    // Longest-first so that "Sourabh Sharma" wins over a registered "Sourabh".
    for (final keyword in _keywords) {
      final needle = keyword.toLowerCase();
      var from = 0;
      while (true) {
        final index = haystack.indexOf(needle, from);
        if (index < 0) {
          break;
        }
        final end = index + needle.length;
        if (_isBoundary(input, index - 1) && _isBoundary(input, end)) {
          yield PiiSpan(
            start: index,
            end: end,
            kind: kind,
            text: input.substring(index, end),
            normalized: needle,
          );
        }
        from = index + 1;
      }
    }
  }

  /// Treats a position as a boundary when it is outside the string or is not
  /// an alphanumeric character.
  bool _isBoundary(String input, int index) {
    if (index < 0 || index >= input.length) {
      return true;
    }
    final code = input.codeUnitAt(index);
    final isDigit = code >= 0x30 && code <= 0x39;
    final isUpper = code >= 0x41 && code <= 0x5A;
    final isLower = code >= 0x61 && code <= 0x7A;
    return !isDigit && !isUpper && !isLower;
  }
}
