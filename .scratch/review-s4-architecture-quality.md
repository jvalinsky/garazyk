# S4: Architecture & Quality Synthesis

## Architectural Patterns
The codebase is broadly organized into layered subsystems — core repository logic, blob storage, auth/crypto, network/XRPC, sync/firehose, and AppView services — and that separation is visible in the file layout and naming. That layering is a real strength: the project has clear domain-specific components, reusable helpers, and a lot of localized logic instead of one monolithic service blob.

What works well:
- There is a consistent attempt to place validation near boundaries: DIDs, handles, AT URIs, CIDs, JWTs, PKCE, TOTP, and WebAuthn all have dedicated helpers or verifier paths.
- Some subsystems already use the right architectural instincts, such as server-side auth helpers, replay/backpressure concepts in sync, and provider abstractions for blobs.
- The code often separates transport concerns from business logic, which makes the larger system understandable.

What does not work well:
- The boundary discipline is uneven. Several layers accept data in one form and silently reinterpret it in another, which erodes the value of the architecture.
- The system frequently has dual paths for the same responsibility: legacy vs modern WebSocket paths, local vs remote token verification, client vs server firehose event handling, and PDS-style vs AppView-style persistence. Those dual paths increase complexity and create places where one path is fixed while the other rots.
- There is a recurring pattern of “plumbing exists, but the safety check is in the wrong place or missing entirely.” That shows up in auth gates, proxy routing, refresh-token handling, and sync/event sequencing.

## Schema & Boundary Issues
This is the most systemic problem across the reports. The project has many places where data crosses a boundary, but the receiving side does not fully enforce the contract.

Cross-layer mismatches and boundary violations:
- AppView services are wired to a database whose schema does not match the SQL those services issue. That is not just a bug; it suggests the service layer and schema layer have drifted apart enough that they no longer share a stable contract.
- Blob validation and blob retrieval disagree on acceptable size limits. Upload succeeds, but reads fail for blobs the validator explicitly allows. That is a classic split-brain API contract.
- Refresh-token expiry is written to storage but ignored on lookup in the repository layer, so the persistence schema says one thing and the retrieval logic says another.
- AT URI parsing accepts extra path segments and skips component validation, which means a boundary object is being normalized without being fully checked.
- RepoCommit and MST persistence accept malformed or non-canonical structures rather than rejecting them at the boundary, weakening downstream assumptions.
- Remote issuer JWT verification fetches JWKS but does not actually use it to verify signatures, which is a severe trust-boundary break.
- The XRPC proxy trusts client-supplied proxy headers and can route requests across trust boundaries, including to attacker-controlled or internal targets.
- Ozone admin handlers treat the presence of an Authorization header as enough, even if parsing and verification failed earlier. That is a broken security boundary because the response and the decision diverge.

Schema drift is especially visible in AppView:
- Services reference tables and columns that are not present in `AppViewDatabase`.
- Indexers write rows using schemas that do not exist.
- Some services appear to have been copied from PDS assumptions into AppView without a full schema redesign.

The recurring theme is that contracts are documented or implied, but not consistently enforced where data enters or crosses modules.

## Code Quality Patterns
The codebase shows a mix of careful defensive programming and brittle ad hoc checks.

Patterns worth noting:
- Good: there is substantial validation infrastructure already present, and many code paths explicitly check format constraints rather than blindly trusting input.
- Good: some crypto and WebAuthn implementations use standard primitives and check important invariants like sign counts and format details.
- Good: a number of subsystems already know about backpressure, replay windows, and cursor semantics, which means the architecture is at least thinking in the right direction.

Common code quality problems:
- Error handling is often incomplete. Many functions validate one or two fields, then continue even when a core invariant is missing.
- Fail-open behavior appears repeatedly: missing admin secrets, missing replay checkers, permissive client ID schemes, and proxy header handling all trend toward continuing rather than stopping.
- Input validation is inconsistent. Some values are checked rigorously, while adjacent fields are ignored or only partially parsed.
- Several implementations use ad hoc parsing or serialization where structured helpers should exist. The kernel JSON encoder, AT URI parsing, and some CID/MST handling are all examples of code that would benefit from stricter, centralized primitives.
- Defensive programming is present, but it is often local instead of systemic. Individual checks exist, yet the enclosing API still allows the wrong object, wrong epoch, wrong token type, or wrong trust source to proceed.

A particularly important quality issue is silent corruption:
- The firehose sequence bug means events can be emitted with incorrect sequence numbers.
- Float serialization in the kernel can emit the wrong value.
- Several event handlers construct objects and then fail to dispatch them.
- Some paths accept malformed content instead of rejecting it, which shifts failure downstream and makes bugs harder to diagnose.

## Technical Debt
The technical debt here is not just about old code; it is about repeated architectural shortcuts that are now causing correctness and security faults.

Main debt areas:
- Legacy and modern code paths coexist for too long. This is especially visible in WebSocket handling, firehose event models, and OAuth/session flows.
- There is duplicated logic across layers where a shared abstraction should exist: auth gate checks, validation routines, event formatting, and schema alignment helpers.
- The code frequently relies on implicit assumptions about encoding, length units, or time epochs. These assumptions work until they do not, and then the failure is deep and non-obvious.
- Multiple components appear to be independently enforcing parts of the same contract. That usually means the contract itself is not centralized and the system is vulnerable to skew.
- Some subsystems are structurally underbuilt for their current responsibilities: relay buffering and search are O(n) in paths that need to scale, and the WebSocket stack has more layers than its current responsibilities justify.
- AppView in particular looks like it needs a schema/service boundary cleanup. Right now, it reads like a partially migrated subsystem where service code and database design were not updated together.

## Positive Patterns
Several patterns are worth preserving because they give the codebase a solid foundation to build on:

- The project is already modularized by domain, which makes it possible to tighten boundaries without a full rewrite.
- There is a clear understanding of security-relevant concepts: token verification, PKCE, DPoP, replay windows, DID/handle validation, CID parsing, and WebAuthn state checks all exist as explicit concerns.
- Some newer paths are clearly better designed than older ones, especially where they enforce PKCE correctly or include better validation semantics.
- The codebase already uses helper abstractions and provider patterns in a few places, which makes it feasible to move toward stronger primitives.
- The sync and relay subsystems already model important protocol concerns like cursors, sequences, and backpressure, even if some implementations are still buggy.
- Several reviewers found that the code often chooses the right high-level approach but misses details at the boundaries. That is a good sign: the architecture is not fundamentally off, but it needs stricter execution.

## Priority Recommendations
1. **Fix security boundary failures first**
   - Re-enable real JWT signature verification for remote issuers.
   - Make refresh tokens truly distinct and revocable.
   - Enforce DPoP replay checking.
   - Reject unauthenticated admin access when secrets are missing.
   - Stop honoring client-controlled proxy targets from untrusted requests.
   These are the highest-risk issues because they can lead directly to token forgery, auth bypass, SSRF, or privilege escalation.

2. **Align service layers with actual schemas and contracts**
   - Repair AppView service SQL so it matches `AppViewDatabase`.
   - Fix indexer/table mismatches.
   - Make blob size/read behavior consistent with validation rules.
   - Enforce expired-token checks at the repository layer.
   This will eliminate large classes of runtime failures and reduce cross-layer drift.

3. **Centralize boundary validation and parsing**
   - Tighten AT URI, CID, MST, repo commit, and kernel JSON handling.
   - Move toward shared validators instead of scattered ad hoc checks.
   The goal is to reject malformed input once, early, and consistently.

4. **Repair sync/firehose correctness and flow control**
   - Assign sequence numbers correctly.
   - Dispatch all event kinds, including account, sync, and info events.
   - Fix heartbeat epoch handling.
   - Apply backpressure consistently and remove redundant or legacy paths.
   Sync bugs are especially damaging because they produce silent protocol breakage and hard-to-debug gaps.

5. **Refactor for changeability after the correctness gaps are closed**
   - Reduce dual-path implementations.
   - Simplify over-layered protocol stacks where they are not adding clear value.
   - Replace linear scans and repeated object creation in hot paths.
   Once the contracts are trustworthy, the code will be easier to optimize and maintain.
