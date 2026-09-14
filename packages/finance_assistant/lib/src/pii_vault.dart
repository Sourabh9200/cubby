/// Reversible tokenization of redacted values.
///
/// The vault is what makes redaction usable rather than merely safe. The model
/// still sees that "the same merchant appeared 12 times" because `[UNIP_3]` is
/// stable across turns, while the real value stays on-device. The model's reply
/// is then re-hydrated locally, so the user reads a natural answer.
///
/// SECURITY: an instance of this class holds the plaintext originals. It must
/// never be serialized, logged, or transmitted. It exists only for the lifetime
/// of one conversation and is scoped to a single [RedactionSession].
library;

import 'pii.dart';

/// Maps sensitive values to stable placeholder tokens and back again.
class PiiVault {
  PiiVault();

  final Map<String, String> _tokenByKey = <String, String>{};
  final Map<String, String> _originalByToken = <String, String>{};
  final Map<String, int> _nextIndexByKind = <String, int>{};
  final List<IssuedToken> _issued = <IssuedToken>[];

  /// Number of distinct values currently tokenized.
  int get size => _issued.length;

  /// The tokens issued so far, for audit display only.
  ///
  /// Callers must show this behind an explicit reveal action and must never
  /// include it in a payload.
  List<IssuedToken> get auditTrail => List<IssuedToken>.unmodifiable(_issued);

  /// Returns the stable token for [normalized], creating one on first sight.
  ///
  /// Identity is `(kind, normalized)`, so `+91 98765 43210` and `+919876543210`
  /// collapse to a single token instead of two.
  String tokenFor(PiiKind kind, String normalized, String original) {
    final key = '${kind.name}\u0000$normalized';
    final existing = _tokenByKey[key];
    if (existing != null) {
      return existing;
    }
    final index = (_nextIndexByKind[kind.tokenPrefix] ?? 0) + 1;
    _nextIndexByKind[kind.tokenPrefix] = index;
    final token = '[${kind.tokenPrefix}_$index]';
    _tokenByKey[key] = token;
    _originalByToken[token] = original;
    _issued.add(IssuedToken(token: token, original: original, kind: kind));
    return token;
  }

  /// Replaces placeholder tokens in [text] with their original values.
  ///
  /// Deliberately lenient: models routinely emit `[EMAIL\_1]`, `[email_1]`, or
  /// a bare `EMAIL_1`. Being strict here would leave raw tokens in front of the
  /// user, which looks broken and invites them to paste the token somewhere
  /// else. Matching is constrained to the tokens we actually issued, so
  /// leniency cannot cause a wildcard substitution.
  String restore(String text) {
    var result = text;
    for (final issued in _issued) {
      final underscore = issued.token.lastIndexOf('_');
      final label = issued.token.substring(1, underscore);
      final index = int.parse(
        issued.token.substring(underscore + 1, issued.token.length - 1),
      );
      result = result.replaceAll(
        _lenientPattern(label, index),
        issued.original,
      );
    }
    return result;
  }

  /// Clears all mappings. Call when a conversation ends.
  void clear() {
    _tokenByKey.clear();
    _originalByToken.clear();
    _nextIndexByKind.clear();
    _issued.clear();
  }

  /// Builds a tolerant matcher for one issued token.
  ///
  /// Tolerates optional brackets, intra-label whitespace, markdown escaping
  /// (`EMAIL\_1`), zero-padding (`EMAIL_001`), and separator variation.
  ///
  /// Bracket-adjacent whitespace is grouped *with* the bracket
  /// (`(?:\[\s*)?` rather than `\[?\s*`) so that a bare `EMAIL_1` does not
  /// consume the space in front of it and run two words together.
  static RegExp _lenientPattern(String label, int index) {
    final letters = label.split('').map(RegExp.escape).join(r'\\?\s*');
    return RegExp(
      r'(?:\[\s*)?' +
          letters +
          r'\\?\s*[_\-]?\s*0*' +
          '$index' +
          r'(?!\d)' +
          r'(?:\s*\])?',
      caseSensitive: false,
    );
  }
}

/// One token issued by a [PiiVault], recorded for audit display.
final class IssuedToken {
  const IssuedToken({
    required this.token,
    required this.original,
    required this.kind,
  });

  final String token;
  final String original;
  final PiiKind kind;

  @override
  String toString() => '$token <- ${kind.name}';
}
