# Mega Plan Deep Dives

## XRPC ownership and contract truth

Evidence: duplicate graph routes, cross-pack labeler ownership, silent last-wins
registration, name-only coverage, and an unsafe empty-root generator default.

Boundary: one canonical lexicon inventory, one owner per endpoint, and separate
static, dynamic, schema, behavior, and extension coverage.

Tests: duplicate fixtures, zero-input generation, endpoint-kind fixtures, schema
drift, required input/output checks, and dynamic route inventory. Stage schema
enforcement report-only. Roll back one owner at a time.

Confidence: high.

## Browser mutation boundaries

Evidence: unauthenticated dashboard process controls, Admin nonce CSP with
inline handlers, CSRF only at login, and HTML escaping reused in JS contexts.

Boundary: loopback-default dashboard guard, one Admin mutation guard, and one
external browser module.

Tests: negative mutation matrix, hostile identifiers, browser CSP, focus, and
keyboard smoke. Security rollback cannot reopen non-loopback mutations.

Confidence: high.

## AppView and PLC migrations

Evidence: incomplete version metadata, multi-statement upgrades outside one
transaction, and fresh-database-only tests.

Boundary: migration runner plus file-backed legacy fixtures, without changing
connection architecture.

Tests: migrate/reopen every version, inject failure, assert rollback/version,
and preserve data/indexes. Production rollback restores a backup.

Confidence: high.

## Deno repository split

Evidence: clean external repos and a deletion branch exist, but current package
code differs and all scenarios still use wrappers.

Boundary: versioned releases. Synchronize forward, publish TUI, publish testing
packages, pin in Garazyk, then regenerate deletion.

Tests: format/lint/check/test in all repos, dashboard build/capture, scenario
discovery, and Garazyk launcher smoke. Rollback pins the last good package.

Confidence: high on design, medium on publishing because no remotes were found.

## Relay

Evidence: the CLI constructs upstream objects then sleeps; no listener,
downstream handler, durable cursor, or single retry owner.

Boundary decision: build, mark experimental, or remove. A real service requires
socket E2E, persisted cursor, and one retry scheduler.

Confidence: high on incompleteness; direction undecided.

## WASM runtime

Evidence: capability documents contradict each other and no built kernel was
available. Generate the capability matrix from one reproducible test command
before choosing features.

Confidence: high on documentation drift, low on current runtime gaps.
