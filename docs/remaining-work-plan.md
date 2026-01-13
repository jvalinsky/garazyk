# Remaining Work Plan

## Overview

Two categories of remaining work:
1. **Critical**: Sign commit blocks for cryptographic verification
2. **Testing**: Validate implementation with actual pdsls.dev

---

## Priority 1: Sign Commit Blocks

### Problem
- Current CAR export includes unsigned commit blocks
- pdsls.dev `verifyRecord()` will fail signature verification
- Records display but show verification warnings

### Solution
Sign commits when exporting records for sync.getRecord.

### Sub-tasks

#### 1.1 Review Key Storage
- [ ] Find where repo signing keys are stored
- [ ] Understand key format (secp256k1 expected)

#### 1.2 Load Signing Key for DID
- [ ] Add method to get signing key for a DID
- [ ] Handle key not found case gracefully

#### 1.3 Sign Commit in getRecordWithProof
- [ ] Call commit.signWithPrivateKey before serialization
- [ ] Ensure signature is included in CAR

#### 1.4 Verify Locally
- [ ] Unit test for signed commit creation
- [ ] Verify CID computation matches after signing

### Files to Modify
- `PDSRepositoryService.m` - Add signing to getRecordWithProof
- May need key access from PDSController or KeyManager

---

## Priority 2: Testing with pdsls.dev

### Sub-tasks

#### 2.1 Build and Run PDS
- [ ] Ensure project builds cleanly
- [ ] Start PDS server locally

#### 2.2 Test Basic Endpoints
- [ ] Test describeServer
- [ ] Test listRepos
- [ ] Test getRecord

#### 2.3 Test WebSocket Firehose
- [ ] Connect with wscat or similar
- [ ] Verify handshake completes
- [ ] Check if events stream

#### 2.4 Test with pdsls.dev
- [ ] Point pdsls at local PDS
- [ ] Verify record viewing works
- [ ] Check verification status

---

## Execution Order

1. **Sign commits** (Priority 1) - Most impactful for verification
2. **Local testing** - Validate the implementation
3. **pdsls testing** - Final validation

---

## Progress

| Task | Status | Notes |
|------|--------|-------|
| 1.1 Review key storage | ✅ | Keys in ActorStore via Keychain |
| 1.2 Load signing key | ✅ | signingKeyPrivateBytesWithError added |
| 1.3 Sign commit | ✅ | commit.signWithPrivateKey called |
| 1.4 Verify locally | ✅ | ActorStoreTests + RepoCommitTests pass |
| 2.1 Build and run | ⬜ | |
| 2.2 Test endpoints | ⬜ | |
| 2.3 Test WebSocket | ⬜ | |
| 2.4 Test pdsls | ⬜ | |
