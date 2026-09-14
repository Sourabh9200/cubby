import 'package:finance_assistant/finance_assistant.dart';
import 'package:test/test.dart';

import 'fixtures.dart'
    show fires, validAadhaar, validGstin, validIfsc, validPan;

void main() {
  group('AadhaarDetector', () {
    const detector = AadhaarDetector();

    test('finds the checksum-valid fixture, spaced or not', () {
      expect(fires(detector, 'aadhaar $validAadhaar'), isTrue);
      expect(fires(detector, 'aadhaar 2345 6789 0124'), isTrue);
    });

    test('rejects an invalid check digit', () {
      expect(fires(detector, 'aadhaar 234567890123'), isFalse);
    });

    test('rejects leading 0 or 1, which Aadhaar never issues', () {
      expect(fires(detector, 'number 123456789012'), isFalse);
      expect(fires(detector, 'number 023456789012'), isFalse);
    });
  });

  group('PanDetector', () {
    const detector = PanDetector();

    test('finds a structurally valid PAN', () {
      expect(fires(detector, 'pan $validPan'), isTrue);
    });

    test('rejects an invalid holder-type character', () {
      // 'X' is not one of the Income Tax Department holder types.
      expect(fires(detector, 'pan ABCXD1234E'), isFalse);
    });
  });

  group('IfscDetector', () {
    const detector = IfscDetector();

    test('finds a real-shaped IFSC whose branch starts with zero', () {
      // Regression guard: an earlier version wrongly rejected this.
      expect(fires(detector, 'ifsc $validIfsc'), isTrue);
    });

    test('rejects the deny-listed placeholder prefix', () {
      expect(fires(detector, 'ifsc CODE0XYZ123'), isFalse);
    });
  });

  group('GstinDetector', () {
    const detector = GstinDetector();

    test('finds a structurally valid GSTIN', () {
      expect(fires(detector, 'gstin $validGstin'), isTrue);
    });

    test('rejects a GSTIN whose reserved character is wrong', () {
      expect(fires(detector, 'gstin 27ABCPD1234E1Y5'), isFalse);
    });
  });

  group('UpiVpaDetector', () {
    const detector = UpiVpaDetector();

    test('finds UPI handles', () {
      expect(fires(detector, 'paid ramesh@okhdfcbank'), isTrue);
      expect(fires(detector, 'paid ramesh@ybl'), isTrue);
    });

    test('leaves email addresses to the email detector', () {
      expect(fires(detector, 'mail ramesh@gmail.com'), isFalse);
    });
  });

  group('context-anchored detectors', () {
    test('bank accounts need a label', () {
      const detector = BankAccountDetector();
      expect(fires(detector, 'a/c 123456789012'), isTrue);
      expect(fires(detector, 'account no 123456789012'), isTrue);
      // Without an anchor this is indistinguishable from any other long number.
      expect(fires(detector, 'value 123456789012'), isFalse);
    });

    test('bank accounts include masked statement forms', () {
      const detector = BankAccountDetector();
      expect(fires(detector, 'card ending XXXX1234'), isTrue);
    });

    test('bank references need a label', () {
      const detector = BankReferenceDetector();
      expect(fires(detector, 'UTR 123456789012'), isTrue);
      expect(fires(detector, 'grocery store payment'), isFalse);
    });
  });

  group('KeywordDetector', () {
    test('matches a registered name case-insensitively', () {
      final detector = KeywordDetector(<String>['Dr Sharma']);
      expect(fires(detector, 'consultation with dr sharma today'), isTrue);
      expect(fires(detector, 'consultation with dr verma today'), isFalse);
    });

    test('ignores one-character keywords', () {
      final detector = KeywordDetector(<String>['A', '  ']);
      expect(detector.isEmpty, isTrue);
    });
  });
}
