# Test Matrix

## Unit Tests

- `PLCOperationTests`: `prev:null`, DID/CID derivation, legacy `create`, no metadata leakage into signed data.
- `PLCStoreTests` or `PLCReplicaStoreTests`: migration, unique `(did,cid)`, `seq`, timestamp preservation, nullification rollback.
- `PLCDIDKeyTests`: P-256 uncompressed parity.

## Socket And Server Tests

- `PLCServerTests`: `/log/audit`, legacy `/export`, sequence `/export?after=0`, timestamp export, invalid query errors, tombstone `/data`.
- `PLCReplicaServerTests`: read-only mutation rejection, host-aware initializer, stream route.

## Sync Tests

- `PLCSyncClientTests`: sequence cursoring and malformed JSONL batch failure.
- `PLCSyncEngineTests`: cursor durability, duplicate policy, recovery nullification, `ConsumerTooSlow` reconnect.

## Verification Commands

```bash
xcodegen generate
xcodebuild -scheme AllTests build
build/tests/AllTests -XCTest PLCOperationTests
build/tests/AllTests -XCTest PLCStoreTests
PDS_RUN_SOCKET_TESTS=1 build/tests/AllTests -XCTest PLCServerTests
PDS_RUN_SOCKET_TESTS=1 build/tests/AllTests -XCTest PLCReplicaServerTests
PDS_TEST_REGISTRATION_AUDIT=1 build/tests/AllTests
scripts/dev/check_module_boundaries.sh
```

## Gated Conformance

Use `scripts/plc/` tools for at least one live-compatible conformance pass against a small export page from `https://plc.directory`. Keep this gated so default XCTest remains offline.

