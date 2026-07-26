# Legacy PLC `create` Operation Type

## What It Is

The AT Protocol's PLC (Public Log of DIDs) directory stores DID operation history as a
hash-linked chain. Each operation has a `type` field that specifies the kind of state
transition.

The current spec (did-method-plc v0.3.0) defines two operation types:

| Type | Purpose |
|------|---------|
| `plc_operation` | Update rotation keys, verification methods, `alsoKnownAs`, or services |
| `plc_tombstone` | Permanently deactivate a DID |

A **third type**, `create`, exists in the codebase for historical DID genesis operations.

### Field Comparison: `create` vs `plc_operation`

| Field | `create` | `plc_operation` |
|-------|----------|-----------------|
| `type` | `"create"` | `"plc_operation"` |
| `did` | yes | no (in wrapper) |
| `prev` | no (genesis) | yes (CID of previous operation) |
| `sig` | yes | yes |
| `handle` | `handle` field | in `alsoKnownAs` (at:// format) |
| `service` | `service` field (string) | in `services` (object) |
| `recoveryKey` | `recoveryKey` field | in `rotationKeys` (array, first entry) |
| `signingKey` | `signingKey` field | in `verificationMethods` (atproto key) + `rotationKeys` (second entry) |
| `rotationKeys` | absent | present (array of did:key) |
| `verificationMethods` | absent | present (object) |
| `alsoKnownAs` | absent (handle is separate) | present (array of at:// URIs) |
| `services` | absent (service is separate) | present (object) |

## Why It Still Exists

The `create` type is a **legacy genesis operation format** used in the first version
of the `did:plc` method. Early DID documents (created before the `plc_operation` format
was standardized) used `create` as their genesis operation.

Historical DIDs with immutable `create` genesis ops remain in the PLC audit log and
**must remain resolvable** for backward compatibility:

1. **DID resolution stability**: Any DID in the directory must be resolvable for the
   lifetime of the directory. Changing the resolution algorithm to reject `create` ops
   would break existing DIDs.
2. **Chain verification**: The PLC state replayer (`PLCStateReplayer`) replays the full
   operation chain in order. If a genesis op is `create`, the replayer must handle it
   to compute the correct initial state.
3. **Test vectors**: Several test vectors use the `create` format to exercise the
   replayer and auditor with legacy data.

## Where It Lives in the Codebase

### Source Locations

| File | Line(s) | Usage |
|------|---------|-------|
| `Garazyk/Sources/PLC/PLCOperation.m` | 265–268 (`plc_operation` case) | `PLCStateReplayer.replayHistory:` handles `create` type alongside `plc_operation` and `plc_tombstone` |
| `Garazyk/Sources/PLC/PLCOperation.m` | 269–277 (`create` case in replayer) | Maps `create` fields (`recoveryKey`, `signingKey`, `handle`, `service`) to the modern `PLCDIDState` structure |
| `Garazyk/Sources/PLC/PLCOperation.m` | 166 (`toDictionary`) | Emits `prev: null` for both `plc_operation` and `create` types |
| `Garazyk/Sources/PLC/PLCOperation.h` | 33–37 (comment) | `calculateDIDForData:` documents that it's retained for legacy test vectors |
| `Garazyk/Sources/PLC/PLCOperation.h` | 65–67 (`calculateDIDForData:` declaration) | Method retained for backward compatibility |

### Test Locations

| File | Usage |
|------|-------|
| `Garazyk/Tests/PLC/PLCOperationTests.m` | Tests that replay `create` genesis operations |
| `Garazyk/Tests/PLC/PLCAuditorTests.m` | Tests that verify `create` ops pass audit validation |
| `Garazyk/Tests/PLC/PLCStoreTests.m` | Tests that store and retrieve DIDs with `create` genesis ops |

## Dead-Code Helpers

These methods exist solely to support legacy `create` operation handling:

- `PLCNormalizeAtprotoHandle(NSString *value)` — Normalizes a bare handle to `at://` format.
  Used in the `create` case of `PLCStateReplayer.replayHistory:`.
- `PLCNormalizeServiceEndpoint(NSString *value)` — Normalizes a bare endpoint to `https://` format.
  Used in the `create` case of `PLCStateReplayer.replayHistory:`.
- `calculateDIDForData:` — Hashes unsigned data (legacy approach). Superseded by
  `calculateDIDForSignedOperation:` per spec v0.3.0.
- `isBase32Char(unichar c)` — Base32 character validation. Used by both legacy and
  modern code paths.

## What Would Break If Removed

1. **DID resolution**: All DIDs whose genesis was a `create` operation would resolve to
   an empty/error state.
2. **PLC state replay**: `PLCStateReplayer.replayHistory:` would skip the genesis op,
   resulting in `nil` rotation keys, verification methods, and services.
3. **Chain verification**: The auditor would reject chains anchored by a `create` genesis.
4. **Tests**: 8+ tests across 3 test files would fail:
   - `PLCOperationTests.m` — tests that replay `create` genesis ops
   - `PLCAuditorTests.m` — tests that verify `create` ops pass audit
   - `PLCStoreTests.m` — tests that store DIDs with `create` genesis ops

## Conditions for Safe Removal

Before the `create` type can be removed from the codebase:

1. **Full PLC directory audit**: Scan the production PLC directory to confirm zero
   remaining DIDs have a `create` genesis operation. This requires exporting the
   full audit log and checking every DID's first operation.
2. **Test vector migration**: All test vectors using `create` ops must be updated to
   use `plc_operation` genesis ops instead.
3. **Replayer removal**: Remove the `create` case from `PLCStateReplayer.replayHistory:`
   and let it return an error for unknown operation types.
4. **Dead-code cleanup**: Remove `PLCNormalizeAtprotoHandle`, `PLCNormalizeServiceEndpoint`,
   and `calculateDIDForData:`.
