---
name: garazyk-plc-tools
description: "PLC Protocol Verification Node.js tools for checking and simulating the Public Log of DIDs. Covers verification, pipeline simulation, structure analysis, libraries, and cross-referencing with the Objective-C storage layer."
---

# Garazyk PLC Protocol Verification Tools

A suite of Node.js utility tools in `scripts/plc/` designed to verify, simulate, and analyze the PLC (Public Log of DIDs) protocol against the live `plc.directory` export. These scripts serve as reference implementations for verifying the correctness of the Garazyk Objective-C storage and sync engines.

## When to Use

- Verify a single PLC operation's CBOR, SHA-256 hash, DID derivation, or signature
- Simulate the Public Log (PLCSyncEngine) pipeline against historical batch exports
- Audit the key types, operation shapes, and distribution metrics of `plc.directory`
- Cross-reference hash calculations, CID generation, or signature verifications with Objective-C test vectors

## Setup & Configuration

Configure the scripts using command line flags or environment variables:

```bash
cd scripts/plc
npm install
```

| Env Variable | CLI Flag | Default | Description |
|---|---|---|---|
| `PLC_SERVER` | `--server` | `https://plc.directory` | Target PLC API server |
| `PLC_AFTER` | `--after` | Beginning | ISO timestamp to start exports |
| `PLC_COUNT` | `--count` | `1000` | Max operations to fetch/simulate |
| `PLC_BATCH_SIZE` | `--batch-size` | `100` | Pagination page size |
| `PLC_SYNC_MODE` | `--mode` | `sequential` | `sequential` or `concurrent` |

## Verification CLI Commands

### 1. Single Operation Verification
Validates a single DID or raw JSON operation payload:

```bash
# Verify a specific DID from the target server
node verify_plc_operation.mjs did:plc:ragtjsm2j2vknwkz3zp4oxrd

# Verify with detailed output (prints unsigned data hex, signature, hash, CID)
node verify_plc_operation.mjs -v did:plc:ragtjsm2j2vknwkz3zp4oxrd

# Verify a raw JSON operation piped from stdin
echo '{"type":"create", ...}' | node verify_plc_operation.mjs --stdin
```

### 2. Ingest Sync Simulator
Simulates the ingestion queue, verifying signature links and prev-link integrity across a chain of operations:

```bash
# Verify chronological block-by-block integrity
node simulate_plc_sync.mjs --count 2000 --batch-size 100

# Start simulation from a specific timestamp
node simulate_plc_sync.mjs --after '2026-01-01T00:00:00.000Z'
```

### 3. Log Auditor
Audits formatting statistics, rotation key types, and cryptographic signatures across historical logs:

```bash
node audit_plc_export.mjs --count 5000
```

## Protocol Library (`lib/plc.mjs`)

All tools rely on `lib/plc.mjs` for core cryptographic and encoding rules:

- `unsignedData(op)` / `signedData(op)`: Strips or includes the signature field.
- `deriveDID(op)`: Computes `did:plc:` using `base32(SHA-256(signed CBOR))`.
- `calculateCID(op)`: Calculates the CIDv1 (dag-cbor + sha2-256).
- `verifyOperationSignature(op)`: Validates the signature against rotation keys (handles **secp256k1** and **P-256**).
- `DIDStore`: Simulated in-memory database of active/historical DIDs.

## Cross-Referencing with Objective-C

The outputs produced by `verify_plc_operation.mjs -v` correspond directly to Objective-C classes:

| JS Helper | Objective-C Equivalent | Purpose |
|---|---|---|
| `unsignedData(op)` | `[PLCAuditor unsignedDataForOperation:]` | Canonical CBOR strip |
| `calculateCID(op)` | `[PLCOperation calculateCIDForOperation:]` | Verification of state hashes |
| `deriveDID(op)` | `[PLCOperation calculateDIDForSignedOperation:]` | DID derivation |
| `verifyOperationSignature(op)` | `[Secp256k1 verifySignature:forHash:]` | ECDSA rotation validation |

> [!IMPORTANT]
> - JS `@atproto/crypto` takes **raw unsigned CBOR bytes** and computes the SHA-256 hash internally.
> - Objective-C `Secp256k1` expects the **pre-hashed 32-byte SHA-256 digest** directly. Both produce identical signature verifications, but when checking intermediate test vectors, do not hash twice.

## Related Skills

- **sqlite-sql-best-practices** — Indexes and queries optimizing PDS sync stores
- **garazyk-database** — The Objective-C SQLite schema mirroring PLC operations
- **objc-security-audit** — Deep audit on cryptographic primitives and ECDSA routines
