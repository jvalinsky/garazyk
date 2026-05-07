# Core Primitives and Repository Layer Review

## Findings

### 1. HIGH — Expired refresh tokens are still accepted
**File:** `Garazyk/Sources/Core/Repositories/PDSSQLiteSessionRepository.m:46-63`

`accountDidForRefreshToken:` returns the account DID for any matching token, but it never checks the `expires_at` column that `storeRefreshToken:` writes. That means a token that should be dead after 30 days remains usable indefinitely as long as the row still exists.

**Impact:** session replay and account takeover risk through expired refresh tokens.

**Recommendation:** include `expires_at > now` in the lookup query, or delete/ignore expired rows before returning a DID.

### 2. MEDIUM — AT URI parsing accepts malformed paths and skips component validation
**File:** `Garazyk/Sources/Core/ATURI.m:12-30`

The parser only checks that the string starts with `at://` and that there are at least three slash-delimited parts. Extra path segments are silently ignored, and `did`, `collection`, and `rkey` are never validated against the project’s DID/NSID/rkey rules.

**Impact:** malformed `at://` values can be normalized into a different record reference than the caller intended, which creates ambiguity and weakens input validation.

**Recommendation:** require exactly three path components and validate each component with the existing DID/collection/rkey validators before constructing the object.

### 3. MEDIUM — MST key prefix handling mixes character counts with UTF-8 byte offsets
**Files:** `Garazyk/Sources/Repository/MST.m:232-286, 754-813`

The MST serializer computes prefix lengths using `NSString` character indices, but the serialized suffix is sliced from raw UTF-8 bytes. The deserializer mirrors the same assumption when reconstructing the key. This works for pure ASCII, but any multibyte key will round-trip incorrectly because character counts do not equal byte counts.

**Impact:** non-ASCII keys can be corrupted on save/load, which breaks tree ordering, diffing, and proof generation.

**Recommendation:** store and reconstruct prefixes using UTF-8 byte offsets consistently, or explicitly reject non-ASCII keys if the format is intended to be ASCII-only.

### 4. MEDIUM — Malformed DAG-CBOR CID tags are accepted after stripping the first byte unconditionally
**File:** `Garazyk/Sources/Core/Repositories/MSTPersistence.m:195-238`

`cidFromTaggedValue:` does not verify that a tag-42 byte string begins with the required `0x00` marker. It removes the first byte regardless of its value and then tries to parse the remainder as a CID.

**Impact:** malformed or non-canonical CID links can be loaded as if they were valid, weakening structural validation for persisted MST nodes.

**Recommendation:** require the marker byte to be exactly `0x00` and reject any other prefix.

### 5. MEDIUM — RepoCommit parsing does not enforce required structural fields
**File:** `Garazyk/Sources/Repository/RepoCommit.m:135-221`

`fromCARData:` decodes the commit map but only checks that `did`, `version`, and `rev` exist. It does not enforce that `version` is the expected value (`3`), and it accepts commits even when `sig` is absent. That contradicts the method’s own documentation about validating signature presence.

**Impact:** malformed or unsigned commit objects can be accepted as valid input, pushing validation failures downstream instead of rejecting bad data at the boundary.

**Recommendation:** hard-fail when `version != 3` and when the signature field is missing or not a byte string.

### 6. LOW — MST node blocks are labeled with an incorrect content type
**File:** `Garazyk/Sources/Core/Repositories/MSTPersistence.m:147-155`

`saveMSTNode:withCID:forDid:` stores serialized MST node data with `contentType = @"application/car"`. That MIME type describes a CAR archive, not a single DAG-CBOR node block.

**Impact:** metadata consumers can misclassify the stored block, which complicates debugging and any future content-type-aware tooling.

**Recommendation:** use a node/block-appropriate type such as DAG-CBOR/raw block metadata, or omit the field if the database does not rely on it.
