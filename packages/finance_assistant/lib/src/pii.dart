/// Core contracts for the redaction pipeline.
///
/// Everything here is deliberately synchronous and pure. A detector that
/// performs I/O could fail open (throw, time out, return early), and a
/// redaction layer that fails open is worse than no redaction layer at all
/// because it manufactures false confidence.
library;

/// The categories of sensitive data we recognize.
///
/// Note the deliberate distinction between identifiers that are *inherently*
/// sensitive (a payment card) and ones that are sensitive only in context
/// (a bank reference number). That split is what [PiiKindLabel.precedence]
/// encodes, and it drives the default redaction policy.
enum PiiKind {
  // Globally applicable.
  email,
  phone,
  paymentCard,
  iban,
  ipAddress,
  macAddress,
  secret, // API keys, JWTs, private keys.
  // India financial pack.
  aadhaar,
  pan,
  ifsc,
  upiVpa,
  bankAccount,
  gstin,
  bankReference,

  // Free text that only the caller can identify.
  custom,
}

extension PiiKindLabel on PiiKind {
  /// Stable, uppercase token prefix used in the vault, e.g. `EMAIL`.
  ///
  /// Kept stable because vault tokens are part of the wire contract: changing
  /// this string changes what the model sees and what `restore` must match.
  String get tokenPrefix => switch (this) {
    PiiKind.email => 'EMAIL',
    PiiKind.phone => 'PHONE',
    PiiKind.paymentCard => 'CARD',
    PiiKind.iban => 'IBAN',
    PiiKind.ipAddress => 'IP',
    PiiKind.macAddress => 'MAC',
    PiiKind.secret => 'SECRET',
    PiiKind.aadhaar => 'AADHAAR',
    PiiKind.pan => 'PAN',
    PiiKind.ifsc => 'IFSC',
    PiiKind.upiVpa => 'UPI',
    PiiKind.bankAccount => 'ACCOUNT',
    PiiKind.gstin => 'GSTIN',
    PiiKind.bankReference => 'REF',
    PiiKind.custom => 'REDACTED',
  };

  /// Relative precedence when two detectors claim overlapping text.
  ///
  /// Higher wins. Inherently-sensitive identifiers outrank ambiguous numeric
  /// patterns so that a card number is never downgraded to `bankAccount`.
  int get precedence => switch (this) {
    PiiKind.secret => 100,
    PiiKind.paymentCard => 95,
    PiiKind.iban => 94,
    PiiKind.aadhaar => 93,
    PiiKind.pan => 92,
    PiiKind.gstin => 88,
    PiiKind.upiVpa => 87,
    PiiKind.ifsc => 86,
    PiiKind.email => 85,
    PiiKind.phone => 84,
    PiiKind.ipAddress => 70,
    PiiKind.macAddress => 70,
    PiiKind.bankReference => 60,
    PiiKind.bankAccount => 50,
    PiiKind.custom => 40,
  };
}

/// A single located PII occurrence within a piece of text.
final class PiiSpan {
  const PiiSpan({
    required this.start,
    required this.end,
    required this.kind,
    required this.text,
    required this.normalized,
    this.contextAnchored = false,
  });

  /// Inclusive start offset into the source string.
  final int start;

  /// Exclusive end offset into the source string.
  final int end;

  final PiiKind kind;

  /// The exact original substring, preserved for `restore()`.
  final String text;

  /// Canonical form used as vault identity, so that `+91 98765 43210` and
  /// `+919876543210` resolve to the *same* token instead of two.
  final String normalized;

  /// True when the producing detector relied on contextual evidence. Carried on
  /// the span so that overlap resolution can prefer context over a checksum.
  final bool contextAnchored;

  int get length => end - start;

  @override
  String toString() => 'PiiSpan(${kind.name}, $start..$end)';
}

/// A pure, synchronous, deterministic PII finder.
///
/// Implementations MUST be safe to run on the caller's isolate and MUST NOT
/// perform I/O. A detector that throws is treated as a bug, not as "no match".
abstract interface class PiiDetector {
  /// Which kind this detector reports.
  PiiKind get kind;

  /// All spans found in [input], in unspecified order.
  Iterable<PiiSpan> detect(String input);

  /// Whether this detector's evidence is contextual (a nearby label such as
  /// `a/c`) rather than a probabilistic property of the value itself.
  ///
  /// Used as the first tie-breaker when two detectors claim exactly the same
  /// span. Context is evidence about *this occurrence*; a checksum is merely a
  /// property that a value can satisfy by coincidence, so context wins.
  bool get isContextAnchored => false;
}

/// Convenience base class for regex-driven detectors.
///
/// Subclasses supply a deliberately *permissive* pattern plus a strict
/// [validate] predicate. This split matters: a tight regex silently misses
/// real data (a leak), while a permissive regex plus a checksum validator
/// only ever costs us a wasted check.
abstract class RegexDetector implements PiiDetector {
  const RegexDetector();

  /// Regex-driven detectors are value-based unless a subclass says otherwise;
  /// [ContextAnchoredDetector] overrides this to `true`.
  @override
  bool get isContextAnchored => false;

  /// Per-match validation. Returning `false` discards the candidate.
  bool validate(RegExpMatch match) => true;

  /// Canonical vault identity for a match. Defaults to the trimmed text.
  String normalize(RegExpMatch match) => match.group(0)!.trim();

  /// Optional refinement of the matched span. Return `null` to keep the match
  /// as-is, or a pair of offsets to narrow it to the checksum-valid region.
  ({int start, int end})? refine(RegExpMatch match) => null;

  @override
  Iterable<PiiSpan> detect(String input) sync* {
    for (final match in pattern.allMatches(input)) {
      if (!validate(match)) {
        continue;
      }
      final bounds = refine(match);
      final start = bounds?.start ?? match.start;
      final end = bounds?.end ?? match.end;
      final text = input.substring(start, end);
      yield PiiSpan(
        start: start,
        end: end,
        kind: kind,
        text: text,
        normalized: bounds == null ? normalize(match) : text,
        contextAnchored: isContextAnchored,
      );
    }
  }

  /// The pattern to scan with. Should over-match; [validate] narrows it.
  RegExp get pattern;
}

/// A detector that only fires when a keyword appears shortly *before* the
/// match.
///
/// This exists because bare digit-run matching is hopeless in a financial
/// context: 9-to-18 digit sequences are account numbers, bank references,
/// cheque numbers, and phone fragments all at once. Requiring an anchor such
/// as `a/c` or `UTR` nearby converts a noisy detector into a precise one.
/// Precision matters here: over-redaction destroys the analytical utility
/// that justifies the LLM call in the first place.
abstract class ContextAnchoredDetector extends RegexDetector {
  const ContextAnchoredDetector();

  @override
  bool get isContextAnchored => true;

  /// Lowercase keywords, any one of which permits the match.
  List<String> get anchors;

  /// How many characters before the match to search for an anchor.
  int get anchorWindow => 24;

  @override
  bool validate(RegExpMatch match) {
    final haystack = match.input.toLowerCase();
    final from = (match.start - anchorWindow).clamp(0, haystack.length);
    final preceding = haystack.substring(from, match.start);
    return anchors.any(preceding.contains);
  }
}

/// True when the character at [index] is an ASCII digit.
bool isAsciiDigitAt(RegExpMatch match, int index) {
  if (index < 0 || index >= match.input.length) {
    return false;
  }
  final code = match.input.codeUnitAt(index);
  return code >= 0x30 && code <= 0x39;
}

/// True when the character at [index] is an ASCII letter.
bool isAsciiLetterAt(RegExpMatch match, int index) {
  if (index < 0 || index >= match.input.length) {
    return false;
  }
  final code = match.input.codeUnitAt(index);
  return (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
}

/// True when the character at [index] is an ASCII dot.
bool isDotAt(RegExpMatch match, int index) {
  if (index < 0 || index >= match.input.length) {
    return false;
  }
  return match.input.codeUnitAt(index) == 0x2E;
}

/// True when no digit is glued to either edge of the match.
///
/// Prevents the classic failure where a 10-digit phone pattern bites the
/// leading ten digits out of a 12-digit identifier, which both leaks the tail
/// and mangles the text.
bool hasNoAdjacentDigit(RegExpMatch match) =>
    !isAsciiDigitAt(match, match.start - 1) &&
    !isAsciiDigitAt(match, match.end);
