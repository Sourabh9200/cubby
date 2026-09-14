// ignore_for_file: avoid_print, avoid_relative_lib_imports
//
// Fixture generator, not part of the package.
//
// Test fixtures for checksum-validated detectors must actually BE checksum
// valid. Hardcoding a plausible-looking Aadhaar number produces a red test and
// tempts you to "fix" a correct detector. This script derives the fixtures from
// the same algorithms the library validates with, and the printed values are
// pasted into the test files as constants.
//
// Run: dart run tool/generate_fixtures.dart

import '../packages/finance_assistant/lib/src/checksums.dart';

const List<List<int>> _multiply = <List<int>>[
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

const List<List<int>> _permute = <List<int>>[
  <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
  <int>[1, 5, 7, 6, 2, 8, 3, 0, 9, 4],
  <int>[5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
  <int>[8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
  <int>[9, 4, 5, 3, 1, 2, 6, 8, 7, 0],
  <int>[4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
  <int>[2, 7, 9, 3, 8, 0, 6, 4, 1, 5],
  <int>[7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
];

const List<int> _inverse = <int>[0, 4, 3, 2, 1, 5, 6, 7, 8, 9];

int verhoeffCheckDigit(String payload) {
  var checksum = 0;
  final reversed = payload.split('').reversed.toList();
  for (var i = 0; i < reversed.length; i++) {
    final digit = int.parse(reversed[i]);
    checksum = _multiply[checksum][_permute[(i + 1) % 8][digit]];
  }
  return _inverse[checksum];
}

int luhnCheckDigit(String payload) {
  var sum = 0;
  var double = true;
  for (var i = payload.length - 1; i >= 0; i--) {
    var value = int.parse(payload[i]);
    if (double) {
      value *= 2;
      if (value > 9) {
        value -= 9;
      }
    }
    sum += value;
    double = !double;
  }
  return (10 - (sum % 10)) % 10;
}

void main() {
  // Canonical Wikipedia vector: prefix 236 must yield check digit 3.
  print('verhoeff(236) check digit = ${verhoeffCheckDigit('236')} (expect 3)');
  print('passesVerhoeff(2363) = ${passesVerhoeff('2363')} (expect true)');
  print('passesVerhoeff(2364) = ${passesVerhoeff('2364')} (expect false)');

  final aadhaarBase = '23456789012';
  final aadhaar = '$aadhaarBase${verhoeffCheckDigit(aadhaarBase)}';
  print(
    'aadhaar fixture = $aadhaar '
    '(valid=${passesVerhoeff(aadhaar)}, len=${aadhaar.length})',
  );

  final cardBase = '411111111111111';
  final card = '$cardBase${luhnCheckDigit(cardBase)}';
  print('card fixture = $card (valid=${passesLuhn(card)})');

  print(
    'isValidIban(GB82WEST12345698765432) = '
    '${isValidIban('GB82WEST12345698765432')} (expect true)',
  );
  print(
    'isValidIban(DE89370400440532013000) = '
    '${isValidIban('DE89370400440532013000')} (expect true)',
  );
  print(
    'isValidIban(GB82WEST12345698765433) = '
    '${isValidIban('GB82WEST12345698765433')} (expect false)',
  );
}
