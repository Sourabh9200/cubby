import 'package:finance_assistant/finance_assistant.dart';
import 'package:test/test.dart';

import 'fixtures.dart'
    show
        fires,
        kindsIn,
        validCard,
        validGoogleKey,
        validHuggingFaceToken,
        validIbanDe,
        validIbanGb;

void main() {
  group('EmailDetector', () {
    const detector = EmailDetector();

    test('finds ordinary addresses in prose', () {
      expect(fires(detector, 'write to jane.doe@acme.com please'), isTrue);
      expect(fires(detector, 'a@b.co'), isTrue);
    });

    test('does not confuse a version string for an address', () {
      expect(fires(detector, 'see report@2.0.pdf for details'), isFalse);
    });
  });

  group('PhoneDetector', () {
    const detector = PhoneDetector();

    test('finds Indian mobile numbers with and without a country code', () {
      expect(fires(detector, 'call 9876543210 today'), isTrue);
      expect(fires(detector, 'call +91 98765 43210 today'), isTrue);
    });

    test('rejects repeated-digit noise', () {
      expect(fires(detector, 'reference 9999999999 here'), isFalse);
    });

    test('does not bite digits out of a longer run', () {
      // Matching a 10-digit sub-run would both leak the tail and mangle text.
      expect(fires(detector, 'id 987654321012 end'), isFalse);
    });
  });

  group('PaymentCardDetector', () {
    const detector = PaymentCardDetector();

    test('finds Luhn-valid cards, spaced or not', () {
      expect(fires(detector, 'card $validCard'), isTrue);
      expect(fires(detector, 'card 4111 1111 1111 1111'), isTrue);
    });

    test('rejects Luhn-invalid digit runs', () {
      expect(fires(detector, 'ref 4111111111111112'), isFalse);
    });

    test('trims back to the card when digits are glued on', () {
      final result = Redactor().redact('card ${validCard}99');
      final span = result.spans.singleWhere(
        (candidate) => candidate.kind == PiiKind.paymentCard,
      );
      expect(span.text, validCard);
    });
  });

  group('IbanDetector', () {
    const detector = IbanDetector();

    test('finds valid IBANs', () {
      expect(fires(detector, 'iban $validIbanGb'), isTrue);
      expect(fires(detector, 'iban $validIbanDe'), isTrue);
    });

    test('rejects checksum-invalid candidates', () {
      expect(fires(detector, 'iban GB82WEST12345698765433'), isFalse);
    });
  });

  group('SecretDetector', () {
    const detector = SecretDetector();

    test('finds provider-prefixed API keys', () {
      expect(fires(detector, 'key $validGoogleKey'), isTrue);
      expect(fires(detector, 'token $validHuggingFaceToken'), isTrue);
    });

    test('finds PEM private key headers', () {
      expect(fires(detector, '-----BEGIN RSA PRIVATE KEY-----'), isTrue);
    });
  });

  group('false-positive traps', () {
    // Over-redaction is not free: it destroys the analytical utility that
    // justifies sending anything to a model at all.
    test('ordinary financial prose stays clean', () {
      for (final safe in <String>[
        'I spent 1,234.56 on groceries on 2026-08-13',
        'running version v1.2.3.4 of the app',
        'ordered 3 items for INR 450',
        'paid the electricity bill twice this month',
        'my budget is 25000 per month',
      ]) {
        expect(kindsIn(safe), isEmpty, reason: 'unexpected match in: $safe');
      }
    });
  });
}
