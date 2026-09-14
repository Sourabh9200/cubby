/// India-specific government and tax identifiers.
///
/// These carry the highest privacy weight in an Indian personal-finance
/// dataset: an Aadhaar number is a national identity credential, and a PAN is
/// a tax identity. Both must never leave the device.
library;

import '../checksums.dart';
import '../pii.dart';

/// Aadhaar numbers, validated with the Verhoeff check digit.
///
/// The checksum is what makes this usable. Without it, every 12-digit run in a
/// statement — UTR fragments, cheque ranges, reference clusters — would be
/// redacted, destroying analytical utility for zero privacy benefit.
/// Real Aadhaar numbers also never start with 0 or 1.
class AadhaarDetector extends RegexDetector {
  const AadhaarDetector();

  @override
  PiiKind get kind => PiiKind.aadhaar;

  @override
  RegExp get pattern => RegExp(r'\d{4}[\s\-]?\d{4}[\s\-]?\d{4}');

  @override
  bool validate(RegExpMatch match) {
    if (isAsciiDigitAt(match, match.start - 1)) {
      return false;
    }
    final digits = match.group(0)!.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 12) {
      return false;
    }
    final first = digits.codeUnitAt(0) - 0x30;
    if (first < 2) {
      return false;
    }
    return passesVerhoeff(digits);
  }

  @override
  String normalize(RegExpMatch match) =>
      match.group(0)!.replaceAll(RegExp(r'\D'), '');
}

/// Permanent Account Number (PAN): `AAAAA9999A`.
///
/// The fourth character encodes the holder type, so we can reject strings that
/// merely look like a PAN from a shape standpoint. The fifth character is the
/// first letter of the holder's surname, which is precisely why a PAN is
/// identifying rather than merely a number.
class PanDetector extends RegexDetector {
  const PanDetector();

  /// Holder-type characters defined by the Income Tax Department.
  /// Public so that GSTIN validation can reuse the same definition.
  static const String holderTypes = 'PCHFATBLJG';

  @override
  PiiKind get kind => PiiKind.pan;

  @override
  RegExp get pattern => RegExp(r'[A-Za-z]{3}[A-Za-z]{2}\d{4}[A-Za-z]');

  @override
  bool validate(RegExpMatch match) {
    if (isAsciiLetterAt(match, match.start - 1) ||
        isAsciiDigitAt(match, match.end)) {
      return false;
    }
    final value = match.group(0)!.toUpperCase();
    if (!holderTypes.contains(value[3])) {
      return false;
    }
    // Reject the all-identical-character placeholder forms that appear in
    // sample data and test fixtures.
    return !RegExp(r'^(.)\1+$').hasMatch(value);
  }

  @override
  String normalize(RegExpMatch match) => match.group(0)!.toUpperCase();
}

/// IFSC codes: four bank letters, a reserved `0`, then six branch characters.
class IfscDetector extends RegexDetector {
  const IfscDetector();

  @override
  PiiKind get kind => PiiKind.ifsc;

  @override
  RegExp get pattern => RegExp(r'[A-Za-z]{4}0[A-Za-z0-9]{6}');

  @override
  bool validate(RegExpMatch match) {
    if (isAsciiLetterAt(match, match.start - 1) ||
        isAsciiDigitAt(match, match.end) ||
        isAsciiLetterAt(match, match.end)) {
      return false;
    }
    // The fifth character is reserved and is always a zero; the pattern already
    // enforces that. The remaining false-positive risk is an ordinary
    // word-shaped string such as `CODE0XYZ12` appearing in prose, so we reject
    // a small deny-list of common non-bank four-letter prefixes.
    final bankCode = match.group(0)!.substring(0, 4).toUpperCase();
    return !_nonBankPrefixes.contains(bankCode);
  }

  /// Four-letter sequences that look like an IFSC bank code but are not.
  static const Set<String> _nonBankPrefixes = <String>{
    'CODE',
    'TEST',
    'DEMO',
    'SAMPLE',
    'NULL',
    'XXXX',
    'ABCD',
  };

  @override
  String normalize(RegExpMatch match) => match.group(0)!.toUpperCase();
}

/// GSTIN: a 15-character tax registration that *embeds* a full PAN.
///
/// Detecting GSTIN separately matters because the embedded PAN would otherwise
/// be redacted as a bare PAN while the state code and entity number leaked.
class GstinDetector extends RegexDetector {
  const GstinDetector();

  @override
  PiiKind get kind => PiiKind.gstin;

  @override
  RegExp get pattern => RegExp(r'\d{2}[A-Za-z]{5}\d{4}[A-Za-z]\d[A-Za-z]\d');

  @override
  bool validate(RegExpMatch match) {
    if (isAsciiDigitAt(match, match.start - 1) ||
        isAsciiLetterAt(match, match.start - 1) ||
        isAsciiDigitAt(match, match.end)) {
      return false;
    }
    final value = match.group(0)!.toUpperCase();
    // Position 14 is a reserved 'Z' by definition.
    if (value[13] != 'Z') {
      return false;
    }
    // The embedded PAN occupies positions 2..12, so its holder-type character
    // (index 3 of the PAN) lands at index 5 of the GSTIN. Validating it here
    // avoids needing to re-enter the PAN validator with a synthetic match.
    return PanDetector.holderTypes.contains(value[5]);
  }

  @override
  String normalize(RegExpMatch match) => match.group(0)!.toUpperCase();
}
