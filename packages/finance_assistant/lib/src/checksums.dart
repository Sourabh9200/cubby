/// Pure-Dart checksum algorithms used to raise detector precision.
///
/// Checksum-validated detection is the difference between redacting a real
/// card number and mangling an unrelated 16-digit bank reference. Every
/// function here is a *validator*, never a generator: nothing on the egress
/// path may synthesize a plausible identifier.
///
/// No third-party code. This file is inside a trust boundary.
library;

/// Luhn (ISO/IEC 7812) check-digit validation for payment cards.
///
/// Rejects anything outside the 12..19 digit range that the major card
/// networks actually issue, so short numeric noise cannot be mistaken for a
/// primary account number.
bool passesLuhn(String digits) {
  if (digits.length < 12 || digits.length > 19) {
    return false;
  }
  var sum = 0;
  var double = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    final code = digits.codeUnitAt(i) - 48;
    if (code < 0 || code > 9) {
      return false;
    }
    var value = code;
    if (double) {
      value *= 2;
      if (value > 9) {
        value -= 9;
      }
    }
    sum += value;
    double = !double;
  }
  return sum % 10 == 0;
}

/// Streaming mod-97 (ISO 7064) over an alphanumeric string.
///
/// Implemented digit-by-digit so we never need arbitrary-precision integers,
/// which keep this usable anywhere in Dart.
int mod97(String input) {
  var remainder = 0;
  for (var i = 0; i < input.length; i++) {
    final code = input.codeUnitAt(i);
    if (code >= 0x30 && code <= 0x39) {
      remainder = (remainder * 10 + (code - 0x30)) % 97;
    } else if (code >= 0x41 && code <= 0x5A) {
      // 'A' (0x41) maps to 10, 'Z' (0x5A) maps to 35.
      remainder = (remainder * 100 + (code - 0x37)) % 97;
    } else if (code >= 0x61 && code <= 0x7A) {
      remainder = (remainder * 100 + (code - 0x57)) % 97;
    } else {
      return -1; // Not part of the IBAN alphabet.
    }
  }
  return remainder;
}

/// IBAN validation: move the four leading characters to the end, then
/// require mod-97 == 1.
bool isValidIban(String iban) {
  final compact = iban.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  if (compact.length < 15 || compact.length > 34) {
    return false;
  }
  if (!RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z0-9]+$').hasMatch(compact)) {
    return false;
  }
  final rearranged = '${compact.substring(4)}${compact.substring(0, 4)}';
  return mod97(rearranged) == 1;
}

// ---------------------------------------------------------------------------
// Verhoeff (used by Aadhaar)
// ---------------------------------------------------------------------------

const List<List<int>> _verhoeffMultiply = <List<int>>[
  <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
  <int>[1, 2, 3, 4, 0, 6, 7, 8, 9, 5],
  <int>[2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
  <int>[3, 4, 0, 1, 2, 8, 9, 5, 6, 7],
  <int>[4, 0, 1, 2, 3, 9, 5, 6, 7, 8],
  <int>[5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
  <int>[6, 5, 9, 8, 7, 1, 0, 4, 3, 2],
  <int>[7, 6, 5, 9, 8, 2, 1, 0, 4, 3],
  <int>[8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
  <int>[9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
];

const List<List<int>> _verhoeffPermute = <List<int>>[
  <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
  <int>[1, 5, 7, 6, 2, 8, 3, 0, 9, 4],
  <int>[5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
  <int>[8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
  <int>[9, 4, 5, 3, 1, 2, 6, 8, 7, 0],
  <int>[4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
  <int>[2, 7, 9, 3, 8, 0, 6, 4, 1, 5],
  <int>[7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
];

/// Verhoeff check-digit validation, as used by 12-digit Aadhaar numbers.
///
/// This is the single highest-value validator in the India pack: without it
/// every 12-digit number in a statement (UTR fragments, cheque ranges) would
/// be redacted, which would destroy analytical utility for no privacy gain.
bool passesVerhoeff(String digits) {
  if (digits.isEmpty) {
    return false;
  }
  var checksum = 0;
  var position = 0;
  for (var i = digits.length - 1; i >= 0; i--) {
    final code = digits.codeUnitAt(i) - 48;
    if (code < 0 || code > 9) {
      return false;
    }
    checksum =
        _verhoeffMultiply[checksum][_verhoeffPermute[position % 8][code]];
    position++;
  }
  return checksum == 0;
}
