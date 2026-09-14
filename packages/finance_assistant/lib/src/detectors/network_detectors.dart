/// Detectors for network identifiers and leaked credentials.
library;

import '../checksums.dart';
import '../pii.dart';

/// Payment cards, validated with Luhn.
///
/// Over-matches a run of digits with optional separators, then trims back to
/// the longest Luhn-valid sub-run rather than discarding the whole match.
/// Discarding would leak the valid card whenever a trailing transaction digit
/// happened to be glued onto it.
class PaymentCardDetector extends RegexDetector {
  const PaymentCardDetector();

  @override
  PiiKind get kind => PiiKind.paymentCard;

  @override
  RegExp get pattern => RegExp(r'\d(?:[ \-]?\d){11,22}');

  @override
  bool validate(RegExpMatch match) =>
      hasNoAdjacentDigit(match) && longestLuhnRun(match) != null;

  @override
  ({int start, int end})? refine(RegExpMatch match) => longestLuhnRun(match);

  @override
  String normalize(RegExpMatch match) {
    final run = longestLuhnRun(match);
    final text = run == null
        ? match.group(0)!
        : match.input.substring(run.start, run.end);
    return text.replaceAll(RegExp(r'\D'), '');
  }
}

/// Finds the Luhn-valid span inside an over-matched run of digits.
///
/// Tries the full run first, then trims at most [_maxTrailingTrim] digits off
/// the right. Only the right edge is trimmed, and only by a bounded amount,
/// which matters for two reasons:
///
/// * Trimming the right edge models the real case of a reference number glued
///   onto the end of a card (`411111111111111199`).
/// * Searching for a valid sub-run at *any* offset does not: it happily finds a
///   nonsense span starting mid-number, producing a redaction that both leaks
///   the leading digit and mangles the surrounding text.
({int start, int end})? longestLuhnRun(RegExpMatch match) {
  final raw = match.group(0)!;
  final digitOffsets = <int>[];
  final digits = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final code = raw.codeUnitAt(i);
    if (code >= 0x30 && code <= 0x39) {
      digitOffsets.add(match.start + i);
      digits.writeCharCode(code);
    }
  }
  final all = digits.toString();
  for (var trimmed = 0; trimmed <= _maxTrailingTrim; trimmed++) {
    final length = all.length - trimmed;
    if (length < 12 || length > 19) {
      continue;
    }
    if (passesLuhn(all.substring(0, length))) {
      return (start: digitOffsets[0], end: digitOffsets[length - 1] + 1);
    }
  }
  return null;
}

/// How many trailing digits may be discarded when hunting for a card number.
const int _maxTrailingTrim = 3;

/// IBANs, validated with ISO 7064 mod-97.
class IbanDetector extends RegexDetector {
  const IbanDetector();

  @override
  PiiKind get kind => PiiKind.iban;

  @override
  RegExp get pattern => RegExp(r'[A-Za-z]{2}\d{2}(?:[ ]?[A-Za-z0-9]){11,30}');

  @override
  bool validate(RegExpMatch match) {
    if (isAsciiLetterAt(match, match.start - 1)) {
      return false;
    }
    return isValidIban(match.group(0)!);
  }

  @override
  String normalize(RegExpMatch match) =>
      match.group(0)!.replaceAll(RegExp(r'\s+'), '').toUpperCase();
}

/// IPv4 addresses, with octet range validation.
class IpAddressDetector extends RegexDetector {
  const IpAddressDetector();

  @override
  PiiKind get kind => PiiKind.ipAddress;

  @override
  RegExp get pattern => RegExp(r'\d{1,3}(?:\.\d{1,3}){3}');

  @override
  bool validate(RegExpMatch match) {
    // `v1.2.3.4` is a version string, not an address. This is the single most
    // common false positive for naive IPv4 patterns.
    if (isAsciiLetterAt(match, match.start - 1)) {
      return false;
    }
    for (final octet in match.group(0)!.split('.')) {
      if (int.parse(octet) > 255) {
        return false;
      }
    }
    return true;
  }
}

/// MAC addresses.
class MacAddressDetector extends RegexDetector {
  const MacAddressDetector();

  @override
  PiiKind get kind => PiiKind.macAddress;

  @override
  RegExp get pattern => RegExp(r'[0-9A-Fa-f]{2}(?:[:-][0-9A-Fa-f]{2}){5}');

  @override
  String normalize(RegExpMatch match) =>
      match.group(0)!.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
}

/// Credentials: API keys, JWTs, bearer tokens, and PEM private keys.
///
/// Directly relevant to this app: a leaked `AIza…` (Google) or `hf_…`
/// (HuggingFace) token would let a third party spend the user's quota, so
/// these carry the highest precedence in the entire pipeline.
class SecretDetector implements PiiDetector {
  const SecretDetector();

  /// Prefix-anchored credential formats, kept as an explicit list so that
  /// supporting a new provider is a deliberate, reviewable change.
  static final List<RegExp> _prefixPatterns = <RegExp>[
    RegExp(r'AIza[0-9A-Za-z_\-]{35}'), // Google API key.
    RegExp(r'hf_[0-9A-Za-z]{30,}'), // HuggingFace token.
    RegExp(r'sk-[A-Za-z0-9]{20,}'), // OpenAI-style secret key.
    RegExp(r'sk_live_[0-9A-Za-z]{20,}'), // Stripe live secret.
    RegExp(r'pk_live_[0-9A-Za-z]{20,}'), // Stripe publishable.
    RegExp(r'gh[pousr]_[0-9A-Za-z]{30,}'), // GitHub token.
    RegExp(r'xox[baprs]-[0-9A-Za-z\-]{10,}'), // Slack token.
    RegExp(r'AKIA[0-9A-Z]{16}'), // AWS access key id.
  ];

  /// A JWT: three base64url segments, the first a JSON header.
  static final RegExp _jwt = RegExp(
    r'eyJ[0-9A-Za-z_\-]{8,}\.[0-9A-Za-z_\-]{8,}\.[0-9A-Za-z_\-]{8,}',
  );

  static final RegExp _pem = RegExp(r'-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----');

  static final RegExp _bearer = RegExp(
    r'Bearer\s+[0-9A-Za-z_\-\.]{16,}',
    caseSensitive: false,
  );

  @override
  PiiKind get kind => PiiKind.secret;

  /// Prefix-matched credentials are recognized by their own shape, with no
  /// surrounding context required.
  @override
  bool get isContextAnchored => false;

  @override
  Iterable<PiiSpan> detect(String input) sync* {
    for (final pattern in <RegExp>[..._prefixPatterns, _jwt, _pem, _bearer]) {
      for (final match in pattern.allMatches(input)) {
        yield PiiSpan(
          start: match.start,
          end: match.end,
          kind: PiiKind.secret,
          text: match.group(0)!,
          normalized: match.group(0)!,
        );
      }
    }
  }
}
