# Troubleshooting Ghost Posts + `createRecord` Crash (GNUstep)
**Date**: February 26, 2026  
**Recorded**: 2026-02-26T18:44:41Z  
**Systems**:
- **PDS**: `https://pds.garazyk.xyz` (exe.dev VM: `DEPLOY_HOST`)
- **Reverse proxy**: `nginx` on `:3000` → PDS on `:2583`
- **Actor**: `did:plc:5rpam44qoj2eeisejtxmke7e` (handle: `test5.garazyk.xyz`)

This document is an incident-style writeup of two production issues we hit while posting from our PDS and validating that posts show up correctly across:
- the PDS itself (`com.atproto.repo.listRecords`)
- Bluesky AppView (`api.bsky.app`)
- clients (e.g. Witchsky)
- public indexing tools (e.g. pdsls/pds.ls)

It focuses on how we discovered each problem, the fixes, why they work, and what we learned.

---

## Summary
We encountered three intertwined problems:

1. **“Ghost post”**: AppView showed `postsCount=2` but the author feed displayed only **one** post. The missing post existed in the repo, but AppView omitted it from feeds.
2. **PDS crash on `com.atproto.repo.createRecord` (GNUstep)**: Posting via XRPC caused `curl` to report `Empty reply from server` / `connection reset by peer`.
3. **Stale counter after delete**: After deleting the bad post out-of-band, AppView counters remained inconsistent until we re-issued the delete via an XRPC write path.

We fixed these by:
- enforcing a **createdAt↔TID coherence guardrail** for `app.bsky.feed.post`
- preventing the server from crashing by catching unhandled exceptions at the XRPC boundary (short-term mitigation)
- fixing the GNUstep crash in lexicon string validation (root cause)
- using `com.atproto.repo.applyWrites` to ensure deletes are broadcast to firehose consumers (AppView)

---

## Environment notes (exe.dev + custom domains)
This deployment runs on an **exe.dev** VM with a reverse proxy. We also configured custom domains (CNAME) so the service is reachable at:
- `https://pds.garazyk.xyz`
- `https://garazyk.xyz`
- `https://*.garazyk.xyz` (e.g. `test5.garazyk.xyz`)

From exe.dev’s documentation (`https://exe.dev/llms.txt`):
- Non-apex subdomains use a **CNAME** to `vmname.exe.xyz`.
- Apex domains typically require an ALIAS/ANAME at the apex and a CNAME for `www` (provider-dependent).

Sanity checks we used:
- Proxy routing via `Host` header locally:
  - `curl -H "Host: pds.garazyk.xyz" http://localhost:3000/xrpc/com.atproto.server.describeServer`
- Public endpoint correctness:
  - `curl https://pds.garazyk.xyz/xrpc/com.atproto.server.describeServer | jq -r .did`

---

## Symptom A: “postsCount=2, but only one post displays”
Observed in client profile UIs:
- the profile counter indicated 2 posts
- the feed displayed only 1 post

We confirmed the discrepancy directly against AppView:
- `app.bsky.actor.getProfile` returned an inflated `postsCount`
- `app.bsky.feed.getAuthorFeed` returned only one feed item

At the same time, the PDS showed two `app.bsky.feed.post` records via:
- `com.atproto.repo.listRecords`

This meant we had a repo record that:
- existed in the user’s repo
- was being counted somewhere in AppView
- but was being filtered/omitted from the author feed

---

## Root cause A: `createdAt` too far from the record-key (TID) timestamp
`app.bsky.feed.post` record keys (`rkey`) are typically a **TID**.

We found a post where:
- `rkey` implied a timestamp `T_rkey`
- the record’s `createdAt` field implied a timestamp `T_createdAt`
- and `|T_createdAt - T_rkey|` was roughly **28 hours**

Hypothesis:
- AppView applies a plausibility filter or ordering rule that effectively drops posts whose `createdAt` is too far from the TID-based record key timestamp (or treats them as invalid for feed display), while some counters still increment.

This explained:
- why relays/AppView could “see something happened”
- why counters could be wrong
- why clients didn’t display the item

### Fix A: Reject posts with large `createdAt`↔TID skew (guardrail)
We added a server-side guardrail for `app.bsky.feed.post` writes:
- if `createdAt` parses and `rkey` parses as a TID
- reject the write if the absolute skew exceeds **24 hours**
- only apply this when validation is on (optimistic/required), not when validation is explicitly disabled

Implementation: `ATProtoPDS/Sources/App/Services/PDSRecordService.m`

Why it works:
- It prevents writing repo states that are “locally valid JSON” but end up being “practically invalid” for AppView/client expectations.
- It moves the failure to a clear 400 error instead of a subtle cross-system inconsistency.

---

## Symptom B: `curl: (52) Empty reply from server` during `createRecord`
When running a normal posting script:
- session creation succeeded
- `com.atproto.repo.createRecord` caused the connection to drop (no HTTP response)

This strongly suggested a **server crash** (process termination) rather than an application-level 4xx/5xx.

---

## Root cause B: GNUstep crash in lexicon string validation (grapheme counting)
We mitigated first, then diagnosed:

### Mitigation: catch unhandled exceptions at the XRPC boundary
We wrapped XRPC handler dispatch in a `@try/@catch` so an uncaught `NSException`:
- is logged
- returns an HTTP 500 JSON error
- does not crash the entire PDS process

This changed the symptom from “connection reset” to “500 InternalServerError”, which made the system debuggable under production load.

Implementation: `ATProtoPDS/Sources/Network/XrpcHandler.m`  
Commit: `0eff41f6` (“Catch XRPC handler exceptions”)

### Diagnosis: stack mapping from production binary
After the exception was logged, we:
- captured the backtrace addresses from container logs
- copied the PDS binary out of the container
- used `addr2line` to map crash addresses to source functions

The top frame mapped into `ATProtoLexiconValidator` in string validation, specifically the code path enforcing grapheme constraints.

### Fix B: GNUstep-safe grapheme counting
The original code used:
- `enumerateSubstringsInRange:options:NSStringEnumerationByComposedCharacterSequences`

On GNUstep, this produced an `NSRangeException` (“Invalid location”) under some inputs.

We replaced it with a defensive loop using:
- `rangeOfComposedCharacterSequenceAtIndex:`

Implementation: `ATProtoPDS/Sources/Lexicon/ATProtoLexiconValidator.m`  
Commit: `29a476fd` (“Fix lexicon validation crash on GNUstep”)

Why it works:
- It avoids GNUstep’s crashing substring enumeration path while still counting composed-character sequences (graphemes).
- It preserves the semantic intent of lexicon constraints (`minGraphemes`, `maxGraphemes`) without risking process termination.

---

## Follow-on: unit test uncovered JSON serialization exception semantics
After changing validation code, the test suite surfaced an unrelated reliability problem:
- `NSJSONSerialization dataWithJSONObject:...` can raise an Objective-C exception for invalid objects, not just return `nil` with an `NSError`.

We updated `PDSEmailHTTPClient` to catch exceptions and convert them into an `NSError`, matching expected “error return” behavior.

Implementation: `ATProtoPDS/Sources/Email/PDSEmailHTTPClient.m`  
Commit: `29a476fd`

---

## Symptom C: post deleted, but AppView `postsCount` stayed wrong
Even after deleting the problematic record, AppView still reported `postsCount` higher than the author feed and the PDS repo contents.

Key insight:
- AppView updates from the **firehose stream** (subscribeRepos).
- If we delete a record **without** emitting a proper repo commit event over firehose (e.g., manual DB changes or out-of-band CLI paths), AppView may never learn about the deletion.

### Fix C: Re-issue the delete via `com.atproto.repo.applyWrites`
We sent an explicit delete op using:
- `com.atproto.repo.applyWrites` with `{action:"delete", collection:"app.bsky.feed.post", rkey:"..."}`.

Why it works:
- XRPC write paths in the PDS generate commit metadata and emit `PDSRecordDidChangeNotification`.
- `SubscribeReposHandler` listens for those notifications and broadcasts a `commit` event over `subscribeRepos`.
- AppView consumes that commit and can update counters and feed visibility.

After doing this, the author feed reflected the expected visible posts again, and counters began to converge.

---

## Deployment workflow (production)
Production deployment reminder (to avoid serving wrong identity):
- Always run production compose from `docker/pds/` (not repo root), per `AGENTS.md`.

On the VM:
```bash
cd DEPLOY_DIR/objpds
git pull --rebase
cd DEPLOY_DIR/objpds/docker/pds
docker compose build pds
docker compose down
docker compose up -d
```

Post-deploy verification:
```bash
curl -s http://localhost:2583/xrpc/com.atproto.server.describeServer | jq -r .did
# Expect: did:web:pds.garazyk.xyz
```

---

## Lessons learned
- **Interop guardrails matter**: “valid” records that violate ecosystem expectations create bugs that are invisible until AppView/client behavior diverges.
- **Crash containment is valuable**: catching exceptions at the request boundary prevents “connection reset” mysteries and buys time to locate the real bug.
- **If AppView is wrong, check the firehose**: counters and views depend on receiving correct commit ops; out-of-band DB edits can strand AppView state.
- **GNUstep ≠ Apple Foundation**: string/Unicode APIs can behave differently; avoid code paths that are known to be fragile on GNUstep when enforcing constraints.

