---
title: CBOR Serialization
---

# CBOR Serialization

## Overview

CBOR (Concise Binary Object Representation) is the primary serialization format for ATProto records and IPLD blocks. Garazyk uses **DAG-CBOR**, a deterministic variant that ensures consistent hashing.

## DAG-CBOR Constraints

1. **Canonical Ordering**: Map keys are sorted by their encoded bytes.
2. **Deterministic Integers**: Minimal encoding for integers.
3. **No Floating Point**: Only integers are permitted.
4. **No Undefined/Null**: All values must be defined.

## Implementation

`ATProtoCBORSerialization.m` handles encoding and decoding:

```objc
// Encoding to DAG-CBOR
NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:record error:&error];

// Decoding from CBOR
id decoded = [ATProtoCBORSerialization JSONObjectWithData:cborData error:&error];
```

## CID Generation

CIDs are generated from the DAG-CBOR bytes of a record or block. Changing a single byte in the CBOR representation will result in a completely different CID.

## Related Deep Dives
- [CID and Hashing](./cid-and-hashing)
- [CAR Format](./car-format)
- [Repository Basics](./repository-basics)

## Related Reading
- [Lexicon Validation](./lexicon-validation)
- [Record Write to Commit Walkthrough](./record-write-to-commit-walkthrough)
- [Glossary](../GLOSSARY)
