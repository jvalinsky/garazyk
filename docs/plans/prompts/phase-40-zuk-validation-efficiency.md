---
phase: 40
title: Zuk validation correctness and identity efficiency
status: pending
agent: worker
depends_on: [38]
last_updated: 2026-08-13
---

# Phase 40: Zuk validation correctness and identity efficiency

## Mission

Make repository-commit verification correct for both ATProto signing curves
and remove synchronous identity-network latency from the bounded relay worker
critical path. Preserve explicit validation guarantees in strict, log-only,
and lenient modes.

## Read first

- [`workstream 17`](../workstreams/17-zuk-relay-resource-bounds.md), Phase 40
- [incident evidence](../workstreams/17-zuk-relay-resource-bounds/incident-evidence.md)
- workstream 01 S6 G5 and its existing security/rollback contract
- ATProto cryptography, DID, repository, and sync specifications
- `Garazyk/Sources/Sync/Relay/RelayEventValidator.{h,m}`
- `Garazyk/Sources/Identity/DIDPLCResolver.{h,m}`
- `ATProtoDIDDocumentFields`, `RepoCommit`, PDS import verification, and tests
- Phase 38 admission/worker contracts

## Security invariants

- Never treat a P-256 key as secp256k1 or vice versa.
- Verify the signed commit block addressed by the event CID; recompute/bind the
  CID and require the commit DID to equal the event repository.
- Resolution, parsing, curve selection, and signature failures remain
  distinguishable.
- Cache only public verification material and non-sensitive resolution
  metadata. Never cache or log private keys, credentials, raw records, or
  authorization headers.
- Strict mode fails closed. Log-only forwards only after a real validation
  attempt. Lenient must be named and measured as unverified forwarding.

## Slice 1 — Curve-tagged signing key

Replace the secp256k1-only extraction API with a result that includes:

```text
curve: p256 | k256
canonical public-key bytes
source layout/key id needed for diagnostics without the full DID document
```

Accept the published `#atproto` DID document forms already supported by the
importer. Reject ambiguous, duplicate, malformed, wrong-purpose, and
unsupported keys with typed errors. Keep shared parsing in Core so Relay and
PDS import cannot drift.

## Slice 2 — Verification dispatch

Dispatch `RepoCommit` verification by the tagged curve. Reuse existing tested
crypto primitives and their encoding/low-S policies; do not duplicate OpenSSL
calls in Relay. Add known-good fixtures for both curves and negative variants:
tampered commit, wrong DID, wrong key, wrong curve tag, malformed signature,
and valid CID pointing at a commit signed by another key.

## Slice 3 — Failure taxonomy and metrics

Provide one outcome factory for each reason:

- DID resolution unavailable/not found;
- no usable `#atproto` key;
- malformed/unsupported key;
- missing or malformed signed commit block;
- advertised CID mismatch;
- repository DID mismatch;
- signature mismatch;
- internal/transient verifier error.

Attempts, failures by reason, forwarded, and dropped totals must not be
double-counted. Rate-limit identical log records and emit aggregate deltas.

## Slice 4 — Asynchronous resolution and coalescing

Remove semaphore waits from the relay processing shard. Resolution must be
asynchronous and return completion onto the owning shard/generation. Coalesce
simultaneous requests for the same DID into one network operation. Bound:

- in-flight distinct DIDs;
- waiters per DID;
- response bytes;
- redirects and timeout through the existing safe HTTP client;
- cancellation on shutdown/upstream generation change.

A full in-flight table must apply Phase 38 pressure or return a typed transient
result; it must not allocate another unbounded waiter list.

## Slice 5 — Compact byte-capped cache

Cache parsed curve/key material rather than full arbitrary DID documents where
possible. Start with a 64 MiB byte cap and 15-minute positive TTL; choose and
test a short negative TTL for not-found/malformed results. Identity events and
known PLC updates invalidate the relevant entry. A signature mismatch may
trigger one bounded refresh before final failure, never an unbounded retry.

Export hit/miss/coalesced/evicted/refresh/negative counts, current bytes and
entries, and resolution latency.

## Slice 6 — Honest mode contracts

| Mode | Required work | Forwarding |
| --- | --- | --- |
| `strict` | Structural, CID/DID, resolution, supported-curve signature | Only valid events |
| `log-only` | Same full validation as strict | Valid and invalid, with truthful reason metric and bounded diagnostics |
| `lenient` | Cheap frame/size/shape/CID-presence checks explicitly documented | Structurally accepted events; metric labels them unverified |

Startup and Admin UI must expose the selected mode without credentials. Do not
change the production mode until shadow evidence explains the incident's
near-total failure count.

## Acceptance gate

```bash
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests -f 'RelayEventValidatorTests' --gated=run
./build/tests/AllTests -f 'ATProtoDIDDocumentFieldsTests' --gated=run
./build/tests/AllTests -f 'RepoAuthRepoTests' --gated=run
./build/tests/AllTests -f 'DIDPLCResolverTests' --gated=run
./build/tests/AllTests -f 'ZukCommandTests' --gated=run
./build/tests/AllTests --gated=run
./scripts/dev/check_module_boundaries.sh .
./scripts/check_module_boundaries.sh build
./scripts/check-recursive-setters.sh
# Run Linux/GNUstep crypto + relay verification.
```

Add a synthetic latency test with more distinct DIDs than the in-flight and
cache limits. It must remain within the Phase 38 queue budget and complete
cleanup at zero outstanding waiters/bytes.

## Shadow validation gate

Before production strict mode:

1. run log-only on a bounded sample;
2. record reason counts and both curves without DID documents or event bodies;
3. investigate any dominant non-signature category;
4. compare known-good public fixtures;
5. set a written threshold for strict promotion and a rollback trigger.

## Stop conditions

Stop if correct P-256 support would weaken the shared P-256 policy, if
resolution bypasses SSRF/DNS pinning/response limits, if a retry can loop, or
if lenient/log-only labeling is ambiguous.

## On completion

Update workstreams 01 and 17 without duplicating ownership: WS01 records the
security outcome; WS17 records resource/throughput and rollout evidence. Update
mega-plan and this prompt in the same change, and record the action/outcome
under deciduous goal 416.

Rollback returns to log-only or the prior resolver implementation while
retaining curve-correct parsing and failure metrics whenever possible.
