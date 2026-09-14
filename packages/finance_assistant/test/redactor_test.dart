import 'package:finance_assistant/finance_assistant.dart';
import 'package:test/test.dart';

import 'fixtures.dart' show validAadhaar, validCard, validGoogleKey;

void main() {
  group('Redactor', () {
    test('leaves the original nowhere in the output', () {
      final result = Redactor().redact('mail me at jane@acme.com');
      expect(result.text, 'mail me at [EMAIL_1]');
      expect(result.text.contains('jane@acme.com'), isFalse);
      expect(result.isClean, isFalse);
      expect(result.kinds, <PiiKind>{PiiKind.email});
    });

    test('reports clean text without allocating tokens', () {
      final result = Redactor().redact('spent 450 on groceries');
      expect(result.isClean, isTrue);
      expect(result.text, 'spent 450 on groceries');
      expect(result.vault.size, 0);
    });

    test('gives one stable token per distinct value', () {
      final redactor = Redactor();
      final vault = PiiVault();
      final first = redactor.redact('a@x.com and b@x.com', vault: vault);
      final second = redactor.redact('again a@x.com', vault: vault);
      expect(first.text, '[EMAIL_1] and [EMAIL_2]');
      // The same address keeps its token across turns, so the model can reason
      // about repetition without knowing the value.
      expect(second.text, 'again [EMAIL_1]');
    });

    test('collapses format variations to a single token', () {
      final redactor = Redactor();
      final vault = PiiVault();
      redactor.redact('call +91 98765 43210', vault: vault);
      final second = redactor.redact('or +919876543210', vault: vault);
      expect(second.text, 'or [PHONE_1]');
      expect(vault.size, 1);
    });

    test('prefers contextual evidence over a coincidental checksum', () {
      // A 14-digit account number satisfies Luhn roughly 10% of the time by
      // chance, so without the context tie-break this is mislabelled a card.
      final result = Redactor().redact('A/c 50100123456789');
      expect(result.kinds, <PiiKind>{PiiKind.bankAccount});
      expect(result.text, 'A/c [ACCOUNT_1]');
    });

    test('still reports an unanchored card as a card', () {
      final result = Redactor().redact('card $validCard');
      expect(result.kinds, <PiiKind>{PiiKind.paymentCard});
      expect(result.text, 'card [CARD_1]');
    });

    test('does not slice an Aadhaar number into a phone number', () {
      final result = Redactor().redact('id $validAadhaar');
      expect(result.kinds, <PiiKind>{PiiKind.aadhaar});
      expect(result.text, 'id [AADHAAR_1]');
    });

    test('redacts secrets even inside a sentence', () {
      final result = Redactor().redact('my key is $validGoogleKey ok');
      expect(result.kinds, <PiiKind>{PiiKind.secret});
      expect(result.text.contains(validGoogleKey), isFalse);
    });

    test('redacts names supplied through the deny list', () {
      // The only defense against a proper noun in prose, so it must work.
      final redactor = Redactor(denyList: <String>['Dr Sharma']);
      final result = redactor.redact('paid Dr Sharma 5000 for the visit');
      expect(result.text, 'paid [REDACTED_1] 5000 for the visit');
      expect(result.kinds, <PiiKind>{PiiKind.custom});
    });

    test('honours a deny list alongside an explicit detector set', () {
      final redactor = Redactor(
        detectors: <PiiDetector>[const EmailDetector()],
        denyList: <String>['Acme Corp'],
      );
      expect(redactor.detectors.length, 2);
      expect(redactor.redact('Acme Corp billed me').isClean, isFalse);
    });
  });

  group('PiiVault.restore', () {
    late RedactionResult result;

    setUp(() {
      result = Redactor().redact('mail jane@acme.com');
    });

    test('restores the exact form', () {
      expect(
        result.restore('I emailed [EMAIL_1].'),
        'I emailed jane@acme.com.',
      );
    });

    test('tolerates the many ways a model mangles a token', () {
      // Every one of these appears in real model output, and a strict matcher
      // would leave a raw token in front of the user.
      for (final mangled in <String>[
        '[email_1]',
        'EMAIL_1',
        r'[EMAIL\_1]',
        '[EMAIL_001]',
        '[EMAIL-1]',
        '[EMAIL 1]',
      ]) {
        expect(
          result.restore('I emailed $mangled.'),
          'I emailed jane@acme.com.',
          reason: 'failed to restore $mangled',
        );
      }
    });

    test('never substitutes a token that was not issued', () {
      // Only EMAIL_1 exists, so a reference to EMAIL_2 must be left alone.
      expect(result.restore('see [EMAIL_2]'), 'see [EMAIL_2]');
    });

    test('does not treat a longer token as a shorter one', () {
      expect(result.restore('see [EMAIL_11]'), 'see [EMAIL_11]');
    });

    test('clear() removes all mappings', () {
      result.vault.clear();
      expect(result.vault.size, 0);
      expect(result.restore('[EMAIL_1]'), '[EMAIL_1]');
    });

    test('audit trail records tokens for the review UI', () {
      final trail = result.vault.auditTrail;
      expect(trail.length, 1);
      expect(trail.single.token, '[EMAIL_1]');
      expect(trail.single.kind, PiiKind.email);
    });
  });
}
