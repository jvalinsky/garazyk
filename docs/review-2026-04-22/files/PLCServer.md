# PLCServer.m — Per-File Analysis

**File**: `Garazyk/Sources/PLC/PLCServer.m`
**Lines**: 817

## Findings

### H1: `/export` endpoint buffers all operations in memory

**Location**: Lines 658-705

`handleExport:` builds a complete `NSMutableString` of all JSONL lines before sending. For large directories, this will:
1. Consume excessive memory
2. Delay first byte of response
3. Potentially OOM

The implementation does correctly:
- Support `count` and `after` query parameters
- Clamp count to 1-1000 range
- Use `application/jsonlines; charset=utf-8` content type
- Include `did`, `operation`, `cid`, `nullified`, `createdAt` fields per spec

### L1: No recovery window enforcement

**Location**: Lines 535-624

`handlePostDID:` accepts and applies operations immediately. No recovery window for rotation key changes.

### L2: Validation could be stricter

**Location**: Lines 61-308

`PLCValidateIncomingOperation` validates:
- Operation size (4KB max)
- Operation type (plc_operation or plc_tombstone)
- Signature format
- alsoKnownAs count and length
- rotationKeys count and did:key format
- services count and field lengths
- verificationMethods count and field lengths

But does NOT validate:
- `alsoKnownAs` entries should start with `at://`
- Service endpoints should be valid HTTPS URLs
- Duplicate alsoKnownAs entries (only rotationKeys checked for duplicates)

### DID genesis validation is correct

**Location**: Lines 588-603

Genesis operations must have `null prev` and the DID must match the calculated DID from the operation data. This is per spec.

### Tombstone handling is correct

**Location**: Lines 97-119

`plc_tombstone` operations are validated to only contain `type`, `prev`, and `sig` fields. Returns 410 Gone for tombstoned DIDs.

### Static file serving has path traversal protection

**Location**: Lines 717-768

`serveStaticFile:response:` checks for `..` in paths and verifies the resolved path is within the assets directory.

## Cross-references

- [[../high.md#H1]] — PLC export streaming
- [[../low.md#L1]] — Recovery window
- [[../low.md#L2]] — Lexicon validation
