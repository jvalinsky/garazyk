---
title: Lexicon Validation
---

# Lexicon Validation

Lexicons define the structure of AT Protocol records, XRPC methods, and subscription events. Garazyk uses a validation engine to ensure all data complies with these schemas.

## Validation Engine

- **Registry**: `ATProtoLexiconRegistry` loads and caches lexicon JSON files from `Resources/lexicons`.
- **Validator**: `ATProtoLexiconValidator` enforces type safety, field constraints (length, range, regex), required fields, and enum membership.

## Validation Modes

Validation can be configured per collection:

1. **Required**: Must pass validation. Unknown lexicons or invalid records cause failure.
2. **Optimistic**: Must pass if the lexicon is known. Unknown lexicons are allowed (forward compatibility).
3. **Off**: No validation performed.

## Interoperability

Strict enforcement ensures compatibility with other AT Protocol implementations. The validation suite is verified against official protocol fixtures.

## Adding Lexicons

1. Add the lexicon JSON to `Garazyk/Resources/lexicons/`.
2. Restart the PDS to reload the registry.

## Related Deep Dives
- [Repository Basics](./repository-basics)
- [CBOR Serialization](./cbor-serialization)
- [CID and Hashing](./cid-and-hashing)

## Related Reading
- [Record Write to Commit Walkthrough](./record-write-to-commit-walkthrough)
- [API Reference](../11-reference/api-reference)
- [Glossary](../GLOSSARY)
