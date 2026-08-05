# ADR 0033: Admin UIs Are Embedded Per Service, Not Aggregated in One Process

**Status:** Accepted
**Date:** 2026-08-04

## Context

`garazyk-ui` is a single process that administers every service. It holds a
base URL and an admin credential for each backend (`GARAZYK_UI_PDS_TOKEN`,
`GARAZYK_UI_PLC_URL`, and so on), authenticates operators against one shared
`GARAZYK_UI_ADMIN_PASSWORD`, and presents twelve toolbar segments in one
shell.

Three properties of the current arrangement drove this decision.

**It concentrates credentials.** One process holds admin authority over the
PDS, PLC, relay, AppView, chat, and video services simultaneously. Compromise
of the UI process is compromise of the entire deployment. Nothing about the
operator's task requires that aggregation — an operator adjusting PLC
rotation keys has no need for the process to also hold a PDS admin token.

**It is not the "thin HTTP server" its own comment claims.**
`Garazyk/Sources/AdminUIServer/` belongs to no static library. Its 6,152 lines
compile directly into the `garazyk-ui` executable, which links
`ATProtoAppViewServer`, `ATProtoRuntime`, `ATProtoStorage`, `ATProtoServices`,
`ATProtoSync`, `ATProtoTransport`, and `ATProtoCore` — the whole set. Because
it is in no library, it is also invisible to the workstream 08 gates: the
link-time boundary gate (ADR 0031) and the namespace gate both enumerate ten
`ATProto*` archives, and `AdminUIServer/` is in none of them. Roughly fifteen
`UI*` classes have therefore never been subject to either gate.

**The aggregation is not real.** The code is already cut along service seams:
ten `UIBackendClient+<Service>` categories, eleven `UIServerRuntime+<Service>Routes`
categories, and per-service HTML partials. What holds it together is one
hardcoded registration sequence in `-[UIServerRuntime registerRoutes]` and one
49-declaration private header. Auditing which backend each category actually
calls shows the seams are cleaner than the tab count suggests: Ozone,
Security, Explorer, and MST all resolve against `pdsBaseURL`. They were never
separate services.

The alternative considered was one UI process per service
(`garazyk-ui-pds`, `garazyk-ui-relay`, …). It removes the credential
concentration but keeps the token plumbing, and it charges the operator N
processes, N configs, and N ports for a deployment that is most often a single
PDS.

## Decision

1. **Each service binary serves its own admin UI** on a dedicated HTTP
   listener, separate from the listener carrying protocol traffic and bound to
   loopback unless explicitly configured otherwise. `garazyk-ui` is deleted.

2. **A new `ATProtoAdminUI` static library** carries the shell, session and
   CSRF handling, the template engine, shared render primitives, HTTP
   transport primitives, and the CSS/JS bundle. It depends on
   `ATProtoTransport` and `ATProtoCore` only. It must not depend on
   `ATProtoStorage`, `ATProtoServices`, `ATProtoSync`, or `ATProtoRuntime` —
   that constraint is the enforceable form of "the UI does not open service
   databases."

3. **Route registration inverts.** `-[UIServerRuntime registerRoutes]`'s
   hardcoded call sequence is replaced by a `GZAdminUIPack` protocol. The host
   composes an array of packs supplied by its owner and has no compile-time
   knowledge of any service. A service owns its pack
   (`Garazyk/Sources/PLC/AdminUI/`), so the library never gains an edge to a
   service.

4. **The UI reaches its service over loopback HTTP**, not through in-process
   calls into service internals. `UIBackendClient`'s existing base-URL
   indirection is retained and pointed at `127.0.0.1`. See Consequences for
   the cost this accepts and the hazard it introduces.

5. **Credentials become in-process.** A service mints an internal token at
   startup and hands it to its pack directly. No `GARAZYK_UI_*_TOKEN`
   environment variable survives. Operator authentication moves to a
   per-service credential; a service with no admin credential today (PLC) must
   gain one and fail closed when it is unset.

6. **Cookie names are scoped to a service identity.** Cookies are not
   port-scoped, so two admin UIs on loopback share a cookie jar and the fixed
   `ui_admin_token` / `ui_admin_nonce` names collide. Each UI derives its
   cookie names from a service identifier.

   This is a correctness defect, not a privilege-escalation one, and the
   distinction matters for how it is prioritized. `UIAuthManager` stores
   sessions in a per-instance dictionary keyed by token hash, so a token
   minted by one manager is absent from another's and already rejected —
   cross-authorization is not possible today and is not what this fixes. What
   collides is the browser's storage: logging into the second UI overwrites
   the first UI's cookie, silently evicting that session. The CSRF nonce is
   worse, because it rotates on every accepted mutation, so two open UIs would
   continuously invalidate each other. Without this change two embedded UIs
   are unusable in one browser; with it they are independent.

7. **The cross-service Overview and Connections tabs are dropped**, along
   with `-[UIBackendClient serviceProbeSpecifications]`. Each service's UI
   home reports that service's own health. Sibling UIs are reachable through a
   peer switcher rendering plain configured links — no polling, no
   credentials, no health claims about processes it cannot see.

8. **The extraction renames `UI*` to `GZAdminUI*`** in the same movement.
   Moving these classes into a library brings them under the namespace gate
   for the first time; adding them unprefixed would grow
   `docs/namespace-baseline.txt`, which that gate exists to prevent.

## Consequences

**The credential blast radius shrinks to one service.** This is the primary
win. Compromising the PLC admin UI yields PLC authority, not the deployment.

**`kaszlak` absorbs six of the twelve tabs** — pds, ozone, security, explorer,
mst, and lab. The PDS admin surface does not shrink; only the fleet does. Any
expectation that this change makes the PDS UI smaller is mistaken.

**Loopback self-connection risks thread starvation.** `UIBackendClient`'s
transport primitives block the calling thread (documented in
`UIBackendClient_Internal.h`: "must not be called from a queue required to
deliver that completion"). `HttpServer` dispatches every request to the shared
global concurrent queue and waits on its concurrency semaphore *while already
holding a global worker*. Two listeners in one process, each admitting
`kMaxConcurrentRequests` (64), can demand more workers than the pool provides.
The concurrency limit therefore becomes a per-instance parameter and admin
listeners are constructed with a small limit (8), making pool monopolization
arithmetically impossible for a surface that serves one operator. This
constraint is load-bearing, not advisory: raising an admin listener's limit
toward the service listener's reintroduces the hazard.

**One local hop per UI request is accepted** (~100µs on loopback, immaterial
against the SQLite work behind it) in exchange for the UI depending only on
its service's public HTTP contract. A UI can therefore be extracted back into
its own process by changing a base URL.

**Video keeps one cross-service edge.** `UIBackendClient+Video` calls both
`videoBaseURL` and `pdsBaseURL`; `jelcz`'s pack retains a narrow PDS client
for exactly those calls. This is the only such edge in the tree.

**The Deno and container surface must follow.** Twenty-six files across
`packages/schemat` (including the `WebClientTopology` type and its
`buildPreset: "garazyk-ui"` member), `packages/hamownia`, `scripts/`, and
`docker/` name `garazyk-ui` or its environment variables. Retiring the binary
is a scenario-framework change, not only a CMake change.

**Rollback.** Each milestone is independently revertable, and the extraction
is validated by rebuilding `garazyk-ui` as the library's first consumer before
any service embeds anything. Rollback never restores an admin listener on a
public-facing port, and never restores a shared session cookie name across
services — those two properties are the security content of this decision.
