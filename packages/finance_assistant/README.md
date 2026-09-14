# finance_assistant

Privacy boundary for every LLM call in Cubby. Redacts PII before text
leaves the device, generalizes aggregates before they are transmitted, and
re-hydrates the model's reply locally so the user still gets a natural answer.

**Zero runtime dependencies. Pure Dart. No Flutter, no plugins, no network.**

## Why a separate package

Financial data is personal data. Sending it to a hosted model means it is
logged, retained, and — on most providers' free tiers — potentially used to
improve their products. So "leave the device" is treated as a privileged
operation with exactly one door.

The load-bearing property is **structural, not procedural**. This package does
not import the database package, and the only type a transport may accept is
`SanitizedContext`, which has no field for a payee, a note, an account id, or a
transaction id. A raw row therefore has no type-level route to the network.
That is stronger than a convention to "remember to sanitize", because it cannot
be forgotten under deadline pressure. `test/architecture_test.dart` enforces it
mechanically.

## The layers

| # | Layer | Control |
|---|-------|---------|
| 1 | Schema | The query behind `RawCategoryAggregate` never selects PII columns |
| 2 | Type | `SanitizedContext` is the only payload a transport accepts |
| 3 | Value | `Redactor` scrubs free text that must pass through |
| 4 | Aggregate | Amounts bucketed; small groups merged; dates generalized to month |
| 5 | Egress | `PayloadGuard` re-scans the finished payload and rejects unknown fields |
| 6 | Verification | Canary tests inject a real value per category and assert none survive |

## Usage

```dart
final redactor = Redactor(denyList: ['Dr Sharma', 'my landlord']);
final vault = PiiVault(); // one per conversation

// 1. Scrub the user's question.
final prompt = redactor.redact(userQuestion, vault: vault);

// 2. Build the only payload that may be transmitted.
final context = SanitizedContextBuilder(redactor: redactor).build(
  aggregates: rows,          // List<RawCategoryAggregate>
  currency: 'INR',
  period: DateTime(2026, 8),
  vault: vault,
);

// 3. Hard gate before the HTTP call.
PayloadGuard(
  redactor: redactor,
  allowedKeys: SanitizedContext.jsonKeys,
).assertClean(context.toJson());

// 4. Re-hydrate the reply so tokens never reach the user.
final answer = vault.restore(modelReply);
```

## What is detected

| Kind | Validation |
|---|---|
| Payment card | Luhn, 12–19 digits, bounded trailing trim |
| IBAN | ISO 7064 mod-97 |
| Aadhaar | Verhoeff check digit, first digit 2–9 |
| PAN | Income Tax holder-type character |
| GSTIN | Reserved `Z` + embedded PAN holder type |
| IFSC | Bank code with a placeholder deny-list |
| UPI VPA | Structural: no dot in the domain |
| Email | TLD alphabetic + lettered second-level label |
| Phone | India mobile + E.164, `hasNoAdjacentDigit` |
| Bank account | Context-anchored (`a/c`, `account`, `ending`) |
| Bank reference | Context-anchored (`UTR`, `RRN`, `cheque`) |
| API keys / JWT / PEM | Google, HuggingFace, OpenAI, Stripe, GitHub, Slack, AWS |
| IP / MAC | Octet range checks; rejects `v1.2.3.4` |
| Registered names | `KeywordDetector` deny-list |

## What is NOT detected — read this

Detection is excellent for structured identifiers and deliberately conservative
for free text.

- **Names in prose are not detected.** No NER runs here. Register known names
  with `KeywordDetector`. This is the single most likely way a real leak happens.
- **A card with digits glued to the *left*** is missed. Trailing trim is bounded
  at 3 digits; only the right edge is trimmed.
- **Free-form prose in a category label can still carry meaning** even after
  redaction ("Divorce lawyer" contains no identifier but reveals a lot). Labels
  are capped at 40 characters, which bounds but does not eliminate this.
- **Your IP address is always visible to the provider.** It is set by the
  network stack, not by the payload. Only a local model avoids this.
- **Timing and volume are metadata.** How often, and at what hour, you query is
  observable regardless of payload content.

Treat this as risk reduction, not absolution. It is one layer of
defense-in-depth.

## Provider notes

The app is **bring-your-own-key**: never ship an API key inside an APK, because
APKs decompile trivially and a scraped key burns within days.

| Provider | Cost | Data handling |
|---|---|---|
| Local engine | ₹0 | Nothing leaves the device |
| Gemini, own **free** key | ₹0 | ⚠️ Content **is** used to improve Google products; 55-day retention; human review possible |
| Gemini, own **paid** key | Pennies | ✅ Not used to improve products |

Google's Gemini API Additional Terms also state the API is for professional or
business purposes, **"not for consumer use"**, and that only Paid Services may
be used when making API clients available to users in the EEA, Switzerland, or
the UK. Re-decide this before distributing to other people.

## Development

```bash
dart pub get
dart test                          # 88 tests
dart analyze
dart run ../../tool/generate_fixtures.dart   # regenerate checksum fixtures
```

Checksum-validated fixtures are generated, never guessed: a plausible-looking
Aadhaar number would produce a red test and tempt someone to "fix" a correct
detector.
