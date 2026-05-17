# PLC Protocol Verification Tools

Node.js tools for verifying and analyzing the PLC (Public Log of DIDs) protocol against the live
`plc.directory` export. These scripts serve as reference implementations for cross-checking the
Garazyk Objective-C codebase.

## Setup

```bash
cd scripts/plc
npm install
```

## Configuration

All scripts support both CLI flags and environment variable overrides. Environment variables have
the lowest priority; CLI flags override them.

| Env Variable     | CLI Flag       | Used By         | Default                 |
| ---------------- | -------------- | --------------- | ----------------------- |
| `PLC_SERVER`     | `--server`     | all scripts     | `https://plc.directory` |
| `PLC_AFTER`      | `--after`      | simulate, audit | (beginning of export)   |
| `PLC_COUNT`      | `--count`      | simulate, audit | `1000`                  |
| `PLC_BATCH_SIZE` | `--batch-size` | simulate, audit | `100`                   |
| `PLC_SYNC_MODE`  | `--mode`       | simulate        | `sequential`            |

Example:

```bash
# Override server and count via environment
PLC_SERVER=http://localhost:2582 PLC_COUNT=500 node simulate_plc_sync.mjs
```

## Scripts

### verify_plc_operation.mjs — Single Operation Verifier

Verifies a single PLC operation's CBOR encoding, SHA-256 hash, DID derivation, CID calculation, and
cryptographic signature against rotation keys.

```bash
# Verify a DID from plc.directory
node verify_plc_operation.mjs did:plc:ragtjsm2j2vknwkz3zp4oxrd

# Verify with verbose output (CBOR hex, hash hex, CID)
node verify_plc_operation.mjs -v did:plc:ragtjsm2j2vknwkz3zp4oxrd

# Verify a raw JSON operation
node verify_plc_operation.mjs --json '{"sig":"...","prev":null,"type":"create",...}'

# Pipe from stdin
echo '{"sig":"..."}' | node verify_plc_operation.mjs --stdin

# Use a different PLC server
node verify_plc_operation.mjs --server http://localhost:2582 did:plc:xyz
```

Exit code 0 if all checks pass, 1 on failure, 2 on usage error.

### simulate_plc_sync.mjs — Sync Pipeline Simulator

Simulates the PLCSyncEngine against the real plc.directory export, verifying each operation's
signature and prev-link chain integrity.

```bash
# Sequential mode (correct, matches fixed sync engine)
node simulate_plc_sync.mjs --count 2000 --batch-size 100

# Concurrent mode (demonstrates the old validation bug)
node simulate_plc_sync.mjs --mode concurrent --count 2000

# Start from a specific timestamp
node simulate_plc_sync.mjs --after '2024-06-01T00:00:00.000Z' --count 500

# Verbose per-batch output
node simulate_plc_sync.mjs -v --count 500
```

**Modes:**

- `sequential` (default) — Validate and ingest each operation before the next. This matches the
  fixed sync engine behavior.
- `concurrent` — Validate all operations in a batch against the store state before the batch, then
  ingest. This simulates the old buggy concurrent validation where non-genesis operations in the
  same batch could not find their predecessors.

Exit code 0 if all operations pass, 1 if any fail.

### audit_plc_export.mjs — Export Structure Analyzer

Analyzes the composition of the plc.directory export: operation types, key types (secp256k1 vs
P-256), field presence, and batch composition.

```bash
# Analyze 1000 operations from the beginning
node audit_plc_export.mjs

# Analyze from a specific timestamp
node audit_plc_export.mjs --after '2024-06-01T00:00:00.000Z' --count 2000

# Larger batch size for fewer HTTP requests
node audit_plc_export.mjs --count 5000 --batch-size 500
```

Always exits 0 (informational only).

## Shared Libraries

### lib/plc.mjs — PLC Protocol Library

Core protocol operations shared across all scripts:

- `unsignedData(op)` / `signedData(op)` — Strip/keep sig field
- `deriveDID(op)` — First 24 chars of base32(SHA-256(signed CBOR))
- `calculateCID(op)` — CIDv1 dag-cbor + sha2-256
- `getRotationKeys(op)` — Extract rotation keys from any operation type
- `verifyOperationSignature(op)` — Verify sig against rotation keys
- `classifyDidKey(didKey)` — Classify as secp256k1, p256, or unknown
- `validateFields(op)` — Check required fields for operation type
- `fetchExportBatch(server, after, count)` — Fetch from /export endpoint
- `fetchDIDLog(did, server)` — Fetch full log for a DID
- `DIDStore` — In-memory DID history store for simulation
- `bytesToHex`, `base64UrlDecode`, `base64UrlEncode` — Encoding helpers

### lib/args.mjs — CLI Argument Parser

Declarative option parser with env var fallbacks and auto-generated --help:

- `option(spec)` — Define a CLI option (flag, type, default, env, description)
- `parseArgs(argv, options)` — Parse argv, returns `{ args, rest, helpRequested }`
- `printHelpAndExit(description, usage, options, examples)` — Print help and exit

## Cross-Referencing with ObjC Code

The `--verbose` flag on `verify_plc_operation.mjs` prints CBOR hex and SHA-256 hash values that can
be compared directly with the ObjC test vectors in `PLCAuditorTests.m` and `PLCOperationTests.m`.

Key correspondence:

- `unsignedData(op)` matches `[PLCAuditor unsignedDataForOperation:]`
- `calculateCID(op)` matches `[PLCOperation calculateCIDForOperation:]`
- `deriveDID(op)` matches `[PLCOperation calculateDIDForSignedOperation:]`
- `verifyOperationSignature(op)` matches the combined `[PLCAuditor hashForOperationData:]` +
  `[Secp256k1 verifySignature:forHash:]` (note: `@atproto/crypto` hashes internally; our ObjC code
  pre-hashes)

## Important Notes

- `@atproto/crypto`'s `verifySignature(didKey, data, sig)` takes **raw CBOR bytes** and hashes
  internally. Do NOT pre-hash before calling it.
- Our ObjC code correctly pre-hashes with SHA-256 and passes the 32-byte hash to
  `secp256k1_ecdsa_verify`. Both approaches produce the same result.
- The scripts handle both **secp256k1** and **P-256** keys. Approximately 1% of PLC operations use
  P-256 keys (multicodec 0x1200).
