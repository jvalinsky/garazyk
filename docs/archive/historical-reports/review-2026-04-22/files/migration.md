# Account Migration Implementation Plan

## Scope

Account migration is a core AT Protocol feature that allows users to move their account between PDS instances. This is a large scope item requiring multiple new endpoints and significant architectural changes.

## Spec Reference

https://atproto.com/guides/account-migration

## Missing Endpoints

### Identity Endpoints

| Endpoint | Purpose | Priority |
|----------|---------|----------|
| `com.atproto.identity.getRecommendedDidCredentials` | Returns recommended DID credentials for migration | P1 |
| `com.atproto.identity.requestPlcOperationSignature` | Requests signature for PLC operation from current PDS | P1 |
| `com.atproto.identity.signPlcOperation` | Signs a PLC operation with rotation key | P1 |
| `com.atproto.identity.updateIdentity` | Updates DID document | P1 |

### Server Endpoints

| Endpoint | Purpose | Priority |
|----------|---------|----------|
| `com.atproto.server.prepareDeleteAccount` | Prepares account for deletion/migration | P1 |
| `com.atproto.server.deleteAccount` | Already exists | — |
| `com.atproto.server.createAppPassword` | Already exists | — |

## Implementation Phases

### Phase 1: DID Credential Management (2-3 weeks)

1. Implement `getRecommendedDidCredentials` endpoint
   - Returns current rotation keys, signing key, handle, and PDS service endpoint
   - Requires auth (account owner or admin)

2. Implement `requestPlcOperationSignature` endpoint
   - PDS signs a PLC operation with its rotation key
   - Used by the new PDS to update the DID document
   - Must verify the request comes from the account owner

3. Implement `signPlcOperation` endpoint
   - Signs a PLC operation with the user's rotation key
   - Used for DID document updates during migration

### Phase 2: Account Export (1-2 weeks)

1. Implement `prepareDeleteAccount` endpoint
   - Returns a signed token confirming the account is ready for migration
   - Sets a "pending migration" status on the account
   - Token has a TTL (typically 48 hours)

2. Implement account data export
   - Export repository as CAR file
   - Export account metadata (handle, email, preferences)
   - Export blob references

### Phase 3: Account Import (2-3 weeks)

1. Implement account import from migration token
   - Verify migration token from old PDS
   - Import repository from CAR file
   - Import blobs
   - Update DID document to point to new PDS

2. Implement account status model
   - Add `status` field to account model: `active`, `deactivated`, `takendown`, `migrating`
   - Emit appropriate `#account` firehose events for each transition

### Phase 4: Testing (1-2 weeks)

1. Unit tests for each endpoint
2. Integration test: full migration flow between two PDS instances
3. E2E test with Docker testnet

## Dependencies

- C1 fix (generic `#account` broadcast) must be implemented first
- Account status model must be extended before migration
- PLC operation signing requires access to rotation keys

## Estimated Total Effort

6-10 weeks of focused development.
