---
title: Lexicon Validation
---

# Lexicon Validation

Lexicons are the "Schema" of the AT Protocol. They define the structure of records, the input/output of XRPC methods, and the shape of subscription events. Garazyk includes a complete validation engine to ensure that all data entering or leaving the system is compliant with these schemas.

## The Validation Engine

**Location:** `Garazyk/Sources/Lexicon/`

### `ATProtoLexiconRegistry`
The registry is responsible for loading and caching lexicon JSON files. It scans the `Resources/lexicons` directory at startup and provides high-performance lookup of schema definitions by NSID.

### `ATProtoLexiconValidator`
The core validator that checks records against their definitions. It enforces:
*   **Type Safety**: Ensuring strings are strings, integers are integers, etc.
*   **Constraints**: Validating `maxLength`, `minLength`, `maximum`, `minimum`, and regex `format` requirements.
*   **Required Fields**: Verifying that all mandatory properties are present.
*   **Enum Membership**: Checking values against allowed `enum` sets.
*   **Union Discrimination**: Correctly validating values that match one of several possible schemas in a `union`.

## Validation Modes

The system supports three validation modes, which can be configured per collection:

1.  **Required**: Validation must pass. If the lexicon is unknown or the record is invalid, the operation fails with an `InvalidRequest` error.
2.  **Optimistic**: If the lexicon is known, it must pass validation. If the lexicon is unknown, the record is allowed through (enabling forward compatibility).
3.  **Off**: No validation is performed. This is primarily used for specialized or transitional record types.

## Interoperability

Strictly enforcing lexicon schemas ensures high interoperability with other PDS and AppView implementations. Our validation suite is verified against the official AT Protocol test fixtures to ensure 100% compatibility with the specification.

## Adding New Lexicons

To support custom record types or new protocol extensions:
1.  Add the lexicon JSON file to `Garazyk/Resources/lexicons/`.
2.  Restart the PDS to trigger a reload of the registry.
3.  The validator will automatically begin enforcing the new schema for matching records.

---

## Related
- [AT Protocol Basics](../02-core-concepts/atproto-basics)
- [Repository Basics](./repository-basics)
- [Reference: API](../11-reference/api-reference)
