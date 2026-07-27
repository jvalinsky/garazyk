---
phase: 14
title: Wire the auth verification cluster
status: pending
agent: worker
depends_on: [13]
---

# Phase 14: Wire the auth verification cluster

## Mission

Execute workstream 01 S8 slice 7. `Auth/Verifier/AuthVerifier`,
`PDSAccountPolicy` (`Auth/PDS/PDSAuth.m:346-385`), and
`Security/GZAuthzManager` are currently constructed nowhere in
`Garazyk/Sources`. Per the 2026-07-26 decision they are the intended auth
path and get wired up rather than deleted.

**Read this before writing any code:** wiring inverts the risk on every latent
defect in these files. Today they are harmless because nothing calls them. The
moment they carry traffic, each becomes a release blocker, and two of them are
outages:

- `GZAuthzManager validateReadAccess:` (`:216-224`) denies posts, reposts, and
  likes whenever the account row exists — there is no mute lookup despite the
  variable name. Since it runs after an owner check, wiring it as-is denies
  owners reading their own repo.
- `GZInputValidator isValidDID:` (`:33`) rejects every `did:web`, because the
  character class excludes `.`. `GZAuthzManager` gates all repo access on it,
  so wiring it as-is is a total denial for every `did:web` account.

Therefore the ordering below is mandatory: **fix first, wire last.** Do not
reorder to get something running sooner.

Live takedown enforcement currently runs through the services-container
`adminController` (`Network/XrpcAuthHelper.m:369`,
`Network/XrpcRepoPack.m:54,95`, `Network/XrpcSyncPack.m:184,1265`) and does
not touch `PDSAccountPolicy`. That path must keep working until parity with
the new one is proven.

## Read first

- `docs/plans/workstreams/01-security-and-protocol-correctness.md` § S8
  slice 7 (authoritative)
- The phase 13 ADRs on claim-type rejection and replay durability — this
  phase inherits both contracts
- `Garazyk/Sources/Network/XrpcAuthHelper.m` — the incumbent path, and the
  parity target

## Scope and order

1. **Self-recursive setters.** `AuthVerifier.m:90` and `:94`, and
   `PDSAuth.m:363`, all do `self.foo = foo` inside `-setFoo:`, which is
   unbounded recursion — the first caller gets a stack overflow. These are the
   only way to configure local-issuer verification, which is why the cluster
   has never been configurable. Assign the ivar. Add the detection sweep to CI
   so the shape cannot recur.
2. **Account policy fails closed.** Make `PDSAccountPolicy`'s admin controller
   a constructor-injected `strong` dependency instead of a `weak` optional set
   after construction. Today `isAccountAllowed:` returns `YES` when the
   controller is nil, and `weak` means it can silently become nil again later.
   A missing controller must be a startup failure, not a per-request allow.
3. **`GZAuthzManager` correctness.** Fix `validateReadAccess:` — implement the
   mute/block query the naming implies, or delete the branch. Resolve
   `isAuthorizedForAdminOperation:` (`:154-187`), which can never return `YES`
   yet runs a discarded `getAccountByDid:` query: give it a real scope check
   or remove it so no caller mistakes it for a grant.
4. **`did:web` validation.** Fix `GZInputValidator isValidDID:` to accept
   `did:web` identifiers containing `.` and percent-encoding, per the DID
   method spec. Cover `did:plc`, `did:web` with and without a port, and
   rejection of malformed input.
5. **`AuthVerifier`'s own gaps.** The absent-`aud` skip (`:372`) — inherit the
   phase 13 required-claim contract rather than reimplementing it. And `:187`,
   where a nil `request` skips DPoP proof verification entirely while leaving
   `isDPoP` true, so `:390`'s thumbprint comparison is also skipped and a
   DPoP-bound token is accepted with no proof of possession. Either require a
   request whenever the scheme is DPoP, or reject DPoP-bound tokens on
   request-less paths such as `verifyAccessToken:`.
6. **Construct and route.** Only now build the cluster and route XRPC auth
   through it. Keep `XrpcAuthHelper` working throughout. Prove parity before
   cutover: the same request must reach the same allow/deny decision on both
   paths across the acceptance matrix below.

## Acceptance gate

Parity is the gate. Build a decision matrix covering both paths and assert
identical outcomes: valid session token; expired token; token for a suspended
account; token for a taken-down account; `did:plc` owner reading own repo;
`did:web` owner reading own repo; non-owner reading another repo; admin-scoped
and non-admin-scoped calls to an admin method; DPoP-bound token with a valid
proof, with a mismatched thumbprint, and with no proof at all; and a
request-less verification path presented with a DPoP-bound token.

Regression guards that must be green before cutover:

- Takedown enforcement still works through the incumbent
  `adminController` call sites listed above.
- A `did:web` account can read and write its own repo.
- An owner can read their own posts, reposts, and likes.
- Startup fails loudly when the admin controller is not supplied.

Then the global gates:

```bash
deno task check
deno task lint
deno task test
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests
```

Bounded parallelism only (`--parallel 4`). New suites need registration in
`Garazyk/Tests/test_main.m` plus a cmake reconfigure.

## Rollback

Steps 1-5 are independent single-commit reverts and are safe on their own —
they only fix code nothing calls yet. Step 6 is the risky one: it changes
which code decides authorization. Land it behind a switch that can fall back
to `XrpcAuthHelper` without a rebuild, and define the cutover rollback trigger
in the ADR before enabling it. Do not delete the incumbent path in this phase.

## On completion

Write the ADR recording the auth-path architecture: why the cluster was wired
rather than deleted, the parity strategy, the cutover switch, and the rollback
trigger. Update S8 slice 7 status in workstream 01 with commit hashes, then set
`status: complete` here.
