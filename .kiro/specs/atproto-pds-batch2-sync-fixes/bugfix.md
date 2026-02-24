# Bugfix Requirements Document

## Introduction

The AT Protocol PDS sync endpoints have two critical spec compliance issues that break crawler compatibility and federation status reporting. Issue A2 affects `com.atproto.sync.getHead`, which returns block data instead of CID strings, preventing crawlers from parsing repository heads. Issue C1 affects `com.atproto.sync.listRepos` and `com.atproto.sync.getRepoStatus`, which hardcode `active:true` regardless of actual account status, breaking moderation propagation across federated servers.

These bugs prevent proper repository synchronization and federation, core requirements for AT Protocol interoperability.

## Bug Analysis

### Current Behavior (Defect)

**Issue A2: sync.getHead returns wrong data type**

1.1 WHEN `com.atproto.sync.getHead` is called THEN the system fetches root CID bytes, then fetches the block data for that CID, then base32-encodes the block data and returns it as a string

1.2 WHEN crawlers attempt to parse the `com.atproto.sync.getHead` response THEN the system returns a base32-encoded commit object (block data) instead of a base32-encoded CID

1.3 WHEN `getRepoRoot` is called from `sync.getHead` handler THEN the system returns block data bytes instead of CID bytes

**Issue C1: sync endpoints hardcode active status**

1.4 WHEN `com.atproto.sync.listRepos` is called THEN the system returns `active: true` for all accounts regardless of their actual status in the database

1.5 WHEN `com.atproto.sync.getRepoStatus` is called for a taken down or suspended account THEN the system returns `active: true` instead of reflecting the actual account status

1.6 WHEN federated servers query account status THEN the system provides incorrect moderation state, preventing proper takedown/suspension propagation

### Expected Behavior (Correct)

**Issue A2: sync.getHead returns wrong data type**

2.1 WHEN `com.atproto.sync.getHead` is called THEN the system SHALL fetch root CID bytes, base32-encode those CID bytes directly, and return a valid CID string

2.2 WHEN crawlers attempt to parse the `com.atproto.sync.getHead` response THEN the system SHALL return a valid CID string that can be parsed as a CID

2.3 WHEN `getRepoRoot` is called from `sync.getHead` handler THEN the system SHALL return CID bytes (not block data)

**Issue C1: sync endpoints hardcode active status**

2.4 WHEN `com.atproto.sync.listRepos` is called THEN the system SHALL query the database for each account's actual status and return the correct `active` field value

2.5 WHEN `com.atproto.sync.getRepoStatus` is called for a taken down or suspended account THEN the system SHALL return `active: false` or the appropriate status field reflecting the account's state

2.6 WHEN federated servers query account status THEN the system SHALL provide accurate moderation state enabling proper takedown/suspension propagation

### Unchanged Behavior (Regression Prevention)

**Issue A2: sync.getHead returns wrong data type**

3.1 WHEN other callers of `getRepoRoot` (in PDSRecordService.m, PDSController.m) use the result THEN the system SHALL CONTINUE TO return data that can be parsed with `[CID cidFromBytes:]`

3.2 WHEN `sync.getHead` is called for a valid repository THEN the system SHALL CONTINUE TO return a successful response (not an error)

3.3 WHEN `sync.getHead` is called for a non-existent repository THEN the system SHALL CONTINUE TO return an appropriate error response

**Issue C1: sync endpoints hardcode active status**

3.4 WHEN `com.atproto.sync.listRepos` is called THEN the system SHALL CONTINUE TO return all other fields (did, head, rev) correctly

3.5 WHEN `com.atproto.sync.getRepoStatus` is called THEN the system SHALL CONTINUE TO return all other fields (did, rev) correctly

3.6 WHEN accounts are genuinely active THEN the system SHALL CONTINUE TO return `active: true` for those accounts
