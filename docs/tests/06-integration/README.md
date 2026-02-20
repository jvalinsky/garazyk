# Integration Tests

End-to-end tests for complete system flows, PLC directory, and federation.

## Files

| File | Description |
|------|-------------|
| [e2e.md](e2e.md) | Full lifecycle: account creation, sessions, records, blobs, commit chains, firehose |
| [plc.md](plc.md) | PLC server, operation storage, DID key parsing, local development PLC |
| [federation.md](federation.md) | Cross-PDS communication, DID-based routing, relay synchronization |

## Test Classes

| Class | File Location | Purpose |
|-------|---------------|---------|
| PDSIntegrationTests | Tests/Integration/PDSIntegrationTests.m | End-to-end flows |
| CommitChainTests | Tests/Integration/CommitChainTests.m | Merkle chain integrity |
| FirehoseIntegrationTests | Tests/Integration/FirehoseIntegrationTests.m | Event broadcasting |
| PDSPLCIntegrationTests | Tests/Integration/PDSPLCIntegrationTests.m | PLC integration |
| PLCServerTests | Tests/PLC/PLCServerTests.m | Local PLC server |
| PLCStoreTests | Tests/PLC/PLCStoreTests.m | Operation storage |
| PLCDIDKeyTests | Tests/PLC/PLCDIDKeyTests.m | did:key parsing |
| FederationClientTests | Tests/Federation/FederationClientTests.m | Request forwarding |
| RelayClientTests | Tests/Sync/RelayClientTests.m | Relay sync |

## Running Tests

```bash
./build/tests/AllTests -only-testing:AllTests/PDSIntegrationTests
./build/tests/AllTests -only-testing:AllTests/PLCServerTests
./build/tests/AllTests -only-testing:AllTests/FederationClientTests
```
