---
title: Per-Service Admin UI Execution Briefs
status: active
last_verified: 2026-08-12
---

# Per-service Admin UI execution briefs

These briefs decompose [workstream 11](../11-per-service-admin-uis.md). They are
not a second backlog: workstream 11 owns scope, milestone status, and rollout
order, and wins if a brief disagrees with it. The durable hosting and security
decisions are in [ADR 0033](../../../adr/0033-per-service-embedded-admin-uis.md).

The [Relay brief](relay.md) records the operating reference already running in
`zuk`. The remaining briefs adapt that information model to each service while
moving every surface onto the shared `ATProtoAdminUI` host.

## Service matrix

| Service | Binary | Surface | Current UI evidence | Brief |
| --- | --- | --- | --- | --- |
| Relay | `zuk` | Firehose aggregation, upstream crawl and delivery | Authenticated dashboard with overall and per-upstream statistics | [Relay](relay.md) |
| PLC directory | `campagnola` | DID operations, audit, primary/replica sync | Existing PLC pack and metrics; first embedded pilot | [PLC](plc.md) |
| AppView | `syrena` | Relay ingestion, indexes, backfill, hooks | Existing AppView pack and JSON admin routes | [AppView](appview.md) |
| Link index | `mikrus` | Backlinks, many-to-many indexes, record lookup | Health route only; no admin pack | [Mikrus](mikrus.md) |
| Edge cache | `beskid` | Record and identity read-through caches | Health route only; no admin pack | [Beskid](beskid.md) |
| Chat | `syrena-chat` | Conversations, messages, groups, moderation | Embedded pack with privacy-safe overview; NixOS module + deploy example | [Chat](chat.md) |
| E2EE mailbox | `germ` | Ephemeral and rendezvous mailboxes | Full embedded pack with aggregate counters, `/admin/metrics`, NixOS module + deploy example | [Germ](germ.md) |
| Video | `jelcz` | Uploads, transcoding, CA VOD / MUXL distribution | Embedded pack with Overview / Jobs / Distribution / Capacity; CA-aware DTO allowlist | [Video](video.md) |
| PDS | `kaszlak` | Accounts, repositories, blobs, moderation and labs | Embedded listener + six packs on `main` (`bbc84dd4`); crimson `ui.garazyk.xyz` cutover; M4 hardening still open | [PDS](pds.md) |

the former monolithic admin UI is a compatibility host to retire under workstream 11 M5, not a
service and therefore has no service brief. Scenario Dashboard and Skylab are
operator products rather than ATProto service binaries and remain out of this
program.

## Shared operator contract

Every service follows the same contract, even when its cards and actions are
different.

### Authentication and request flow

1. The service starts a dedicated admin listener with a maximum concurrency of
   8. It binds to `127.0.0.1` by default and does not share the protocol port.
2. The listener starts only when an operator password is configured. On NixOS,
   the password comes from a root-readable file through a systemd credential;
   it is never placed in the Nix store or a world-readable environment file.
3. Login creates an opaque, HttpOnly, SameSite session cookie scoped to the
   service identifier. The browser uses `credentials: same-origin`; it does not
   store or attach a bearer token to each request.
4. Every mutation requires both the authenticated session and a rotating CSRF
   nonce. Read-only partials require the session. Logout invalidates server-side
   session state.
5. If the UI calls the service's protocol listener, the service mints a narrow
   internal token at startup and supplies it to the pack in-process. That token
   may traverse loopback HTTP only; it never reaches HTML, JavaScript, logs,
   configuration files, cookies, or API responses.
6. A reverse proxy may publish the listener only with TLS and an explicit
   access policy. The service itself remains fail-closed and loopback-first.

### Information architecture

Each home page answers four questions in order:

1. Is the service healthy now?
2. Is it keeping up with its inputs and queues?
3. What is its overall workload, and which bounded unit explains a problem?
4. What safe operator action can change that state?

The first screen therefore contains health, uptime/version, input or queue
state, throughput, error rate, storage pressure, and the age of the last
successful operation. A service-specific table then supports overall and
per-unit views: upstream for Relay and AppView, DID for PLC, index family for
Mikrus, cache family for Beskid, queue state for Video, and bounded resource
views for PDS, Chat, and Germ.

### Telemetry contract

- Service code owns a thread-safe snapshot object. UI polling reads that
  snapshot; it does not run an unbounded `COUNT(*)`, scan a queue, or open a
  service database on every refresh.
- Monotonic counters include request successes/failures, work accepted,
  completed, retried, and rejected. Gauges include queue depth, active workers,
  connection state, cursor/sequence, and storage bytes where cheaply available.
- Timestamps are UTC ISO 8601. Durations and ages include units. Rates are
  derived from monotonic counters and display the sample window.
- List endpoints are cursor-paginated, capped server-side, stable-sorted, and
  support a small allowlist of filters. Empty, loading, stale, partial, and
  error states are distinct.
- Responses never include passwords, tokens, signing material, cookies, raw
  database paths, message ciphertext, or unrestricted record bodies. Service
  briefs add stricter allowlists where their data is sensitive.
- Every mutation has a typed service method, validation, an audit event, a
  confirmation for destructive actions, and an idempotent or explicitly
  non-idempotent response. The UI never issues raw SQL.

### Shared implementation slices

1. **Snapshot seam:** define the bounded service-owned status model and tests
   before rendering it.
2. **Pack ownership:** move or create the service pack under the service module;
   keep `ATProtoAdminUI` free of service dependencies.
3. **Embedded listener:** compose `GZAdminUIHost` into the service lifecycle,
   mint any loopback credential in memory, and stop both listeners cleanly.
4. **Session-gated UX:** render overview, drill-downs, stale/error states, and
   safe actions from shared assets and patterns.
5. **Packaging:** expose admin bind/port and password-file options in the
   relevant NixOS module/container manifest. Defaults remain loopback and off
   without a password.
6. **Compatibility:** serve the same pack from the former monolithic admin UI until M5, then
   remove compatibility routes and fleet-wide credentials.

## Dependency order

The PLC pilot proves a safe embedded listener. Relay then converges its live
dashboard onto the shared pack. Beskid and Mikrus prove new-pack creation;
AppView establishes the complex ingestion/backfill pattern; Chat and Germ
establish privacy-preserving messaging operations; Video proves worker/queue
operations; PDS lands last because it composes six packs and has the largest
mutation surface.

```text
ATProtoAdminUI extraction and gates
  -> PLC pilot
  -> Relay convergence
  -> Beskid + Mikrus
  -> AppView
  -> Chat -> Germ
  -> Video
  -> PDS
  -> the former monolithic admin UI retirement
```

Parallel work is allowed only after the PLC acceptance gate, in separate
worktrees, with distinct service-owned files. AppView and Mikrus may share a
snapshot vocabulary for `AppViewIngestEngine`, but must not share mutable
dashboard state or database access. Chat and Germ share privacy rules, not
mailbox or conversation data.

## Program acceptance

- Each service has its own authenticated, loopback-first admin listener and no
  browser request requires a manually supplied auth token.
- Overall and bounded per-unit statistics are accurate under concurrent work,
  survive empty/degraded states, and do not create polling-shaped database
  load.
- All mutations reject missing session or CSRF state and are covered by audit
  and negative tests.
- Shared UI browser, visual, accessibility, design-system, asset-sync, module
  boundary, namespace, native gated, GNUstep/Linux binary, and applicable Deno
  topology/scenario gates pass before M5.
- NixOS/container smoke tests prove secret-file loading, default loopback bind,
  disabled-without-password behavior, login, one read, one mutation rejection,
  and clean shutdown for every packaged service.
- the former monolithic admin UI and `GARAZYK_ADMIN_UI_*` are removed only after every individual brief
  meets its acceptance gate.

## Rollback rule

Rollback is per service: stop its embedded admin listener and continue serving
the same pack through the compatibility host. Never roll back to a public
admin bind, browser-visible bearer token, shared cookie name, or a UI process
holding credentials for multiple services.
