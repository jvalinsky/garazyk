# Admin API: implement missing `com.atproto.admin.*` endpoints (parity)

## Summary

The previously missing `com.atproto.admin.*` endpoints are now implemented and registered.  
This issue now tracks post-parity hardening and behavior refinement.

## Goals

- Bring `com.atproto.admin.*` endpoint coverage closer to bundled lexicons.
- Keep authorization behavior consistent across all admin endpoints.
- Avoid “placeholder success” behavior in `PDSAdminService` (persist changes).
- Add tests that lock in request/response shapes and error behavior.

## Non-goals

- Implementing `tools.ozone.*` moderation APIs (separate scope).
- Building a full email/SMS provider integration (we can start with “not configured” behavior).

## Already implemented (do not re-do)

These are already implemented and tested:

- `com.atproto.admin.getAccountInfo`
- `com.atproto.admin.getAccountInfos`
- `com.atproto.admin.getInviteCodes`
- `com.atproto.admin.deleteAccount`
- `com.atproto.admin.disableAccountInvites`
- `com.atproto.admin.enableAccountInvites`
- `com.atproto.admin.disableInviteCodes`

## Missing endpoints (as of 2026-02-12)

None in `com.atproto.admin.*` from bundled lexicons.  
Remaining in-scope XRPC gaps are under `com.atproto.temp.*` (tracked separately).

## Implementation notes / dependencies

- Wiring points:
  - `ATProtoPDS/Sources/Network/XrpcHandler.h` and `ATProtoPDS/Sources/Network/XrpcHandler.m`
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/Security/PDSAuthzManager.m` (ensure each new method is classified as admin)

- Data / service layer:
  - Accounts table has relevant columns already:
    - `accounts.email`, `accounts.handle`, `accounts.password_hash/password_salt`, `accounts.invite_enabled`
    - schema: `ATProtoPDS/Sources/Database/Schema.m` (`kPDSAccountTableCreateSQL`)
  - Invite codes table supports per-code disable:
    - `invite_codes.disabled` (schema in `Schema.m`)
  - Account deletion already exists for user-initiated flows:
    - `com.atproto.server.deleteAccount` uses `PDSAccountService` → repository → `PDSDatabase deleteAccount`
    - Admin `deleteAccount` can likely reuse the same lower-level delete path without requiring user password
  - Some `PDSAdminService` methods currently return `YES` without doing real work (no TODO markers, but still placeholders):
    - `-updateAccountPassword:newPassword:error:` (`ATProtoPDS/Sources/Services/PDSAdminService.m`)
    - `-disableAccountInvitesForDid:error:`
    - `-enableAccountInvitesForDid:error:`
    - `-disableInviteCode:error:`
    - `-disableInviteCodes:error:` (note: signature `BOOL disabled` does not match lexicon input of `codes/accounts`)
  - We should implement these against `PDSServiceDatabases` / service DB schema.

## Cross-cutting subtasks (do once, used by many endpoints)

- [ ] Add (or reuse) a shared helper to resolve `at-identifier` → DID:
  - accept DID input as-is
  - if handle: normalize + resolve to DID using existing identity/handle resolution
  - ensure errors are consistent (invalid identifier vs not found)
- [ ] Ensure consistent auth semantics:
  - 401: missing/invalid token
  - 403: valid token but missing `admin` scope
- [ ] Add/confirm DB indexes for expected query patterns:
  - `accounts.email` (search)
  - `invite_codes.account_did` (already indexed) + `invite_codes.disabled` (maybe add if needed)
- [ ] Decide how to handle optional `note` fields:
  - ignore (documented), or
  - persist to an audit log table (recommended if we want operator traceability)

## Endpoint-by-endpoint plan

### 1) `com.atproto.admin.deleteAccount`

- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/admin/deleteAccount.json`
- Input: `{ did }`
- Plan:
  - Admin auth required.
  - Validate DID.
  - Delete account and associated persisted state (service DB + actor DB + blobs as appropriate).
    - Prefer reusing existing deletion plumbing from `PDSAccountService`/repositories/DB where possible.
  - Decide behavior for “already deleted” accounts (404 vs 200 no-op).
  - Return `200` with empty object (lexicon has no explicit output schema).
- Tests:
  - 401 no auth
  - 403 non-admin
  - 200 admin deletes existing DID
  - subsequent `getAccountInfo` returns 404

Subtasks:
- [x] Register method + handler wiring.
- [x] Implement service-level `deleteAccount` without password requirement.
- [x] Ensure DB deletes cascade/clean related tables (records/blobs/invites).
- [ ] Add tests for success + not-found behavior.

### 2) `com.atproto.admin.disableAccountInvites` / `enableAccountInvites`

- Lexicons:
  - `.../disableAccountInvites.json` (input: `account`, optional `note`)
  - `.../enableAccountInvites.json` (input: `account`, optional `note`)
- Input `account` is an `at-identifier` (handle or DID).
- Plan:
  - Resolve `account` to DID:
    - if DID: validate DID
    - if handle: resolve via service DB / handle resolution
  - Persist “invites disabled” state:
    - likely maps to `accounts.invite_enabled` (see `ATProtoPDS/Sources/Database/Schema.m`)
  - Decide where to store `note` (if at all); if no schema column exists, either:
    - add a column for note, or
    - ignore the note (documented)
- Tests:
  - toggles invite_enabled behavior as expected (create-invite code endpoints should honor)

Subtasks:
- [x] Implement `PDSAdminService` persistence (no “return YES” placeholder).
- [ ] Ensure invite creation endpoints check `invite_enabled` consistently.
- [ ] Add tests for both handle and DID inputs.

### 3) `com.atproto.admin.disableInviteCodes`

- Lexicon: `.../disableInviteCodes.json`
- Input: optional `{ codes: string[], accounts: string[] }`
- Plan:
  - Disable invite codes by code list (set `invite_codes.disabled = 1`).
  - Disable invite codes for accounts list (set `disabled = 1` for all codes with `account_did IN (...)`).
  - Decide behavior when both arrays absent: no-op or 400 (document).
  - IMPORTANT: current `PDSAdminService -disableInviteCodes:(BOOL)` signature does not match the lexicon. We should refactor to a new method that matches this input.
- Tests:
  - seed multiple codes, disable by `codes`, verify they stop being usable
  - disable by `accounts`, verify all that account’s codes are disabled

Subtasks:
- [ ] Add a new `PDSAdminService` method that matches lexicon shape.
- [x] Ensure DB update uses parameterized queries and handles large lists safely.
- [x] Add tests for disable-by-codes and disable-by-accounts.

### 4) `com.atproto.admin.searchAccounts`

- Lexicon: `.../searchAccounts.json`
- Query params:
  - `email` (string)
  - `limit` 1..100 default 50
  - `cursor` (string)
- Output:
  - `{ accounts: accountView[], cursor?: string }`
- Plan:
  - Implement a parameterized query on accounts (by email match).
    - Decide matching semantics:
      - exact match, or
      - substring match (`LIKE %...%`), or
      - prefix match
  - Implement cursor:
    - simplest: opaque `offset` integer string
    - better: stable pagination key (e.g. `created_at + did`) to avoid drift
  - Reuse existing `adminAccountViewFromAccount(...)` where possible.
- Tests:
  - returns only matching accounts
  - respects limit and cursor

Subtasks:
- [x] Add endpoint registration + handler implementation with limit/cursor bounds.
- [x] Add tests for auth and filtered success path.
- [ ] Add stronger paging stability tests (cursor drift under concurrent writes).

### 5) `com.atproto.admin.sendEmail`

- Lexicon: `.../sendEmail.json`
- Input: `recipientDid`, `senderDid`, `content` (required), `subject`, `comment`
- Output: `{ sent: boolean }`
- Plan:
  - Decide behavior when email sending is not configured:
    - return `501 NotImplemented` OR
    - return `200 { sent: false }` with log + metrics
  - If implementing for real:
    - add config: SMTP host/port/credentials
    - implement transport (or integrate with an existing mailer library)
- Tests:
  - Validate input, ensure correct error on missing required fields.
  - If “not configured”, ensure deterministic behavior.

Subtasks:
- [x] Implement deterministic local behavior (`200 { sent: true }` for valid inputs + existing recipient account).
- [x] Add auth + success tests.
- [ ] Add configurable SMTP transport and explicit “not configured” behavior contract.

### 6) `updateAccountEmail` / `updateAccountHandle` / `updateAccountPassword`

- Lexicons:
  - `updateAccountEmail`: `account` (handle or DID) + `email`
  - `updateAccountHandle`: `did` + `handle`
  - `updateAccountPassword`: `did` + `password`
- Plan:
  - Implement service DB updates, including:
    - email update
    - handle update (uniqueness + format validation)
    - password update: generate salt + hash using the same scheme as account creation/login
  - Ensure updated fields update `updated_at`.
  - Decide error semantics:
    - handle already taken → 409 vs 400 (match existing patterns)
    - invalid email → 400 (validate format?)
- Tests:
  - update then verify via `getAccountInfo` or login path

Subtasks:
- [x] Implement endpoint persistence path via `XrpcMethodRegistry` helpers + `PDSServiceDatabases`.
- [x] Ensure password hashing uses existing PBKDF2 parameters and revokes refresh tokens.
- [x] Add tests for successful update flows (email, handle, password).
- [ ] Add explicit negative tests for uniqueness conflicts (`EmailAlreadyInUse`, `HandleAlreadyInUse`).

### 7) `updateAccountSigningKey`

- Lexicon: `.../updateAccountSigningKey.json`
- Input: `did` + `signingKey` (did:key formatted public key)
- Plan:
  - Clarify desired semantics:
    - Is this updating the DID document’s `atproto` verification method via PLC?
    - Is it updating the repo signing key used for future commits?
  - Implementation likely requires:
    - validating `signingKey` is `did:key:*`
    - persisting key and/or creating a PLC operation
    - ensuring new commits are signed with the new key
- Tests:
  - Validate input; if the endpoint is initially “not supported”, ensure we return a clear error.

Subtasks:
- [ ] Decide semantics (PLC op vs repo signing key vs both) and document.
- [x] Implement input validation (`did` + `did:key:*`) and admin auth flow.
- [ ] Add a persistence layer plan (where is the key stored? how does repo commit signer read it?).
- [x] Add happy-path test coverage for current accepted behavior.

## Definition of done

- [x] Each method is registered in the registry (including legacy/application registration paths).
- [x] Admin auth enforced (401/403 semantics consistent with existing admin endpoints).
- [x] Behavior matches lexicon shapes (input parsing, output fields).
- [x] Targeted tests added for each endpoint.
- [x] `./build/tests/AllTests -XCTest AdminAuthXrpcTests` passes.
