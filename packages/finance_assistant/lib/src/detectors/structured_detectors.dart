/// Detectors for globally-recognizable structured identifiers.
///
/// These do not depend on locale or country.
library;

import '../pii.dart';

/// Email addresses.
class EmailDetector extends RegexDetector {
  const EmailDetector();

  @override
  PiiKind get kind => PiiKind.email;

  @override
  RegExp get pattern =>
      RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+');

  @override
  bool validate(RegExpMatch match) {
    final value = match.group(0)!;
    final at = value.lastIndexOf('@');
    final local = value.substring(0, at);
    final domain = value.substring(at + 1);
    if (local.isEmpty || local.startsWith('.') || local.endsWith('.')) {
      return false;
    }
    final labels = domain.split('.');
    if (labels.length < 2) {
      return false;
    }
    // A TLD is always alphabetic.
    final tld = labels.last;
    if (!RegExp(r'^[A-Za-z]{2,24}$').hasMatch(tld)) {
      return false;
    }
    // The label immediately before the TLD must contain a letter. This is what
    // separates a real domain (`acme.com`) from a version or file name that
    // happens to end in a word-like suffix (`report@2.0.pdf`), and it also
    // rejects bare dotted quads such as `user@192.168.1.1`.
    return RegExp(r'[A-Za-z]').hasMatch(labels[labels.length - 2]);
  }

  @override
  String normalize(RegExpMatch match) => match.group(0)!.toLowerCase();
}

/// Phone numbers: international E.164-ish plus the India mobile range.
///
/// A bare `[6-9]\d{9}` would otherwise bite the leading digits out of a longer
/// run, so [hasNoAdjacentDigit] is doing real work here.
class PhoneDetector extends RegexDetector {
  const PhoneDetector();

  @override
  PiiKind get kind => PiiKind.phone;

  @override
  RegExp get pattern =>
      RegExp(r'\+\d{1,3}[\s\-]?\d[\d\s\-]{5,13}\d|[6-9]\d{9}');

  @override
  bool validate(RegExpMatch match) {
    if (!hasNoAdjacentDigit(match)) {
      return false;
    }
    final digits = match.group(0)!.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10 || digits.length > 15) {
      return false;
    }
    // Reject repeated-digit noise such as 9999999999.
    return !RegExp(r'^(\d)\1+$').hasMatch(digits);
  }

  @override
  String normalize(RegExpMatch match) =>
      match.group(0)!.replaceAll(RegExp(r'\D'), '');
}
