# Repository Tests

Tests for Merkle Search Tree operations, CAR file format, DAG-CBOR encoding, and core primitives.

## Files

| File | Description |
|------|-------------|
| [mst.md](mst.md) | MST interop with reference implementations, persistence, repository commits, secp256k1 signing |
| [car-cbor.md](car-cbor.md) | CAR v1 format reading/writing, DAG-CBOR canonical encoding, CID links |
| [primitives.md](primitives.md) | CID creation, TID generation, Base58 encoding, DID validation, record path validation |

## Test Classes

| Class | File Location | Purpose |
|-------|---------------|---------|
| MSTInteropTests | Tests/Repository/MSTInteropTests.m | Reference implementation compatibility |
| MSTPersistenceTests | Tests/Repository/MSTPersistenceTests.m | Database persistence |
| RepoCommitTests | Tests/Repository/RepoCommitTests.m | Commit signing/verification |
| CARInteropTests | Tests/Repository/CARInteropTests.m | CAR file format |
| ATProtoDagCBORTests | Tests/Core/ATProtoDagCBORTests.m | DAG-CBOR encoding |
| ATProtoCoreTests | Tests/Core/ATProtoCoreTests.m | CID, TID, CBOR |
| Base58Tests | Tests/Core/Base58Tests.m | Base58 encoding/decoding |
| DIDValidationTests | Tests/Core/DIDValidationTests.m | DID format validation |
| RecordPathValidationTests | Tests/Core/RecordPathValidationTests.m | Record path/NSID validation |

## Running Tests

```bash
./build/tests/AllTests -only-testing:AllTests/MSTInteropTests
./build/tests/AllTests -only-testing:AllTests/CARInteropTests
./build/tests/AllTests -only-testing:AllTests/ATProtoCoreTests
```
