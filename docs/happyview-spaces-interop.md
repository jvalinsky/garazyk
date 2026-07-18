# HappyView and Permissioned Spaces: Interop Analysis

*Investigated 2026-07-18 against `github.com/gamesgamesgamesgamesgames/happyview`
tag `v2.7.0` (commit `53d0816`).*

## Question

Can HappyView participate in our PDS's permissioned-spaces implementation —
either as the space host that a member on our PDS joins, or as a reader of a
space our PDS hosts?

## Answer

**Not without an adapter.** HappyView and our PDS both implement "permissioned
spaces," but they implement *different, wire-incompatible* systems, and they
disagree on the underlying architecture. The two never exchange a byte of a
shared protocol today.

The spec-native showcase of our permissioned-spaces implementation is therefore
**PDS-to-PDS** — [scenario 93](../scripts/scenarios/scenarios/93_permissioned_spaces.ts),
which passes 19/19 as of 2026-07-18 (see
[permissioned-spaces-compatibility.md](permissioned-spaces-compatibility.md)).
HappyView is not part of that story.

## Architectural mismatch: who hosts the space

- **Reference Proposal 0016 (what our PDS implements):** the space is
  **PDS-hosted**. The authority is a DID whose PDS publishes an
  `#atproto_space_host` service endpoint; each member's records live in that
  member's own PDS isolated store; the authority tracks membership and issues
  credentials. Permissioned data deliberately never enters the AppView,
  firehose, relay, or search — that exclusion is the security model.
- **HappyView `v2.7.0`:** the space is **AppView-hosted**. HappyView (an
  AppView) stores the space's records in its own database, issues its own
  credentials, and is itself the host. This is a coherent all-in-one design,
  but it puts the AppView in the role the reference spec assigns to a PDS.

## Wire-protocol deltas (v2.7.0)

| Dimension | Our PDS (Proposal 0016) | HappyView v2.7.0 |
| --- | --- | --- |
| XRPC namespace | `com.atproto.space.*` / `com.atproto.simplespace.*` | `dev.happyview.space.*` (no `com.atproto.space` in source) |
| Space URI | `at://<did>/space/<type>/<skey>` | `ats://<did>/<type>/<skey>` |
| Member → credential | member's PDS signs an **ES256K** delegation with its DID `#atproto_space` key; authority verifies against the DID doc, then issues a credential | member calls `getMemberGrant` (**HS256**, HappyView's own secret) → `getSpaceCredential` returns an **ES256/P-256** JWT |
| Signing curve | secp256k1 (`alg: ES256K`) | P-256 (`alg: ES256`) — hard-required in `verify_credential` |
| Cross-host credential verify | expects issuer `#atproto_space` secp256k1 key | `verify_external_credential` expects issuer `#atproto` **P-256 multicodec** key |
| Delegation-token concept | `com.atproto.space.getDelegationToken` on the member's PDS | none — HappyView mints its own grant |

Source: HappyView `src/spaces/routes.rs` (namespace, `ats://` URIs, grant flow)
and `src/spaces/credential.rs` (HS256 grant, ES256/P-256 credential,
`verify_external_credential` DID-doc `#atproto` P-256 expectation).

## Consequences

- Our scenario-93 client (`com.atproto.space.getDelegationToken` + `at://…/space/…`
  URIs + ES256K delegations) cannot drive HappyView as-is.
- HappyView's `verify_external_credential` cannot accept our credentials: it
  requires a P-256 `#atproto` key, ours are secp256k1 `#atproto_space`.
- HappyView's own docs describe `com.atproto.space.*` aliases "until v3." That
  is a *future* migration; it is not present in any shipped tag, including
  v2.7.0's unreleased "Latest" changelog (still `dev.happyview.space` / `ats://`
  / P-256).

## If HappyView interop is wanted later

Two viable shapes, both real engineering rather than demo-sized:

1. **HappyView-native, our PDS as OAuth IdP.** A user on our PDS logs into
   HappyView via atproto OAuth (HappyView as an OAuth client of our PDS) and
   uses HappyView's own `dev.happyview.space` flow. This exercises our PDS's
   *OAuth*, not our `com.atproto.space` implementation, and the space lives
   entirely in HappyView.
2. **Protocol adapter / await HappyView v3.** A shim translating namespace,
   `at://`↔`ats://`, and the grant/delegation flow — plus a resolution of the
   ES256K↔P-256 curve split — or HappyView's own migration to
   `com.atproto.space` with reference-spec credential semantics.

The `scripts/scenarios/topologies/happyview.json` preset remains useful for
exercising HappyView's *AppView* capabilities (lexicon-driven XRPC, OAuth,
sync), which is what it is built for — not for the spec permissioned-spaces flow.
