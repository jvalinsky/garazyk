# AT Protocol PDS Refactor & Spec Compliance Plan

**Generated:** 2026-02-24T13:48:25Z
**Repository:** github.com/jvalinsky/september

## Execution Order (least impact → most impact)

### Batch 1 — Trivial Fixes (< 1 hour)

- [x] **A3.** `repo.importRepo` — return 501 instead of silent 200
- [x] **C3.** Remove `did:key:placeholder` dead fallback (line 3680)
- [x] **C2.** Remove `label.subscribeLabels` stub — PDS is not a labeler
- [x] **E2.** Remove debug `fprintf` in `getLatestCommit` handler (line 6039)

### Batch 2 — Targeted Spec Fixes (2-3 hours)

- [x] **A2.** `sync.getHead` — return CID string via `getLatestCommitForDid:`, also fixed `PDSController.getRepoHeadForDid:`
- [x] **C1.** `sync.getRepoStatus` — now includes `rev` field from latest commit

### Batch 3 — Identity Correctness (4-6 hours)

- [x] **A1.** `identity.resolveDid` — resolves via PLC directory for `did:plc`; falls back to local account when PLC unreachable
- [x] **B1.** Enforce JWT minter — UUID fallback removed; returns error when minter unavailable; updated test setup

### Batch 4 — Auth Interop (3-4 hours)

- [x] **B2.** DPoP nonce flow — **audited and confirmed compliant**: nonce is correctly read from proof JWT `nonce` claim (line 820 of OAuth2.m); removed unnecessary request header read
- [x] **B3.** OAuth `.well-known` metadata — removed duplicate routes from `HttpRouter.m` (dead code); `OAuth2Handler` is single source of truth

### Batch 5 — Refactor: Split XrpcMethodRegistry.m (multi-day)

- [ ] **D2.** Extract shared helpers (XrpcAuthHelper, XrpcIdentityHelper, XrpcErrorHelper)
- [ ] **D1.** Split into domain modules (Server, Repo, Sync, Identity, Admin, Label, AppBsky)

### Batch 6 — Minor Cleanups

- [ ] **E1.** Linux HandleResolver — use callback queue instead of main queue
- [ ] **E3.** Audit firehose EventFormatter required fields against lexicon

## Issue Details

See thread https://ampcode.com/threads/T-019c8fdf-b060-723d-99de-fbd781917416 for full analysis.
