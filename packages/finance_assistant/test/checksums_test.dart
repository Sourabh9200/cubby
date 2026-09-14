import 'package:finance_assistant/finance_assistant.dart';
import 'package:test/test.dart';

import 'fixtures.dart' show validAadhaar, validCard, validIbanDe, validIbanGb;

void main() {
  group('passesVerhoeff', () {
    test('matches the canonical published vector', () {
      // From the standard Verhoeff worked example: 236 must yield check digit 3.
      expect(passesVerhoeff('2363'), isTrue);
      expect(passesVerhoeff('2364'), isFalse);
    });

    test('accepts the generated 12-digit fixture', () {
      expect(passesVerhoeff(validAadhaar), isTrue);
    });

    test('rejects a single-digit mutation', () {
      expect(passesVerhoeff('234567890125'), isFalse);
    });

    test('rejects empty and non-numeric input', () {
      expect(passesVerhoeff(''), isFalse);
      expect(passesVerhoeff('abcdef'), isFalse);
    });
  });

  group('passesLuhn', () {
    test('accepts known-good test card numbers', () {
      expect(passesLuhn(validCard), isTrue);
      expect(passesLuhn('5555555555554444'), isTrue); // Mastercard test PAN.
    });

    test('rejects a mutated check digit', () {
      expect(passesLuhn('4111111111111112'), isFalse);
    });

    test('rejects lengths outside the issued range', () {
      expect(passesLuhn('41111111111'), isFalse); // 11 digits.
      expect(passesLuhn('41111111111111111111'), isFalse); // 20 digits.
    });
  });

  group('mod97 and IBAN', () {
    test('accepts well-known valid IBANs', () {
      expect(isValidIban(validIbanGb), isTrue);
      expect(isValidIban(validIbanDe), isTrue);
    });

    test('rejects a corrupted IBAN', () {
      expect(isValidIban('GB82WEST12345698765433'), isFalse);
    });

    test('tolerates spaces and lowercase', () {
      expect(isValidIban('gb82 west 1234 5698 7654 32'), isTrue);
    });

    test('rejects structurally invalid input', () {
      expect(isValidIban(''), isFalse);
      expect(isValidIban('not-an-iban'), isFalse);
    });
  });
}
