# ADR 0006: Remove `kaszlak relay serve`

## Status

Accepted — 2026-07-17 (operator decision, phase 7 / workstream 02 A5)

## Context

`kaszlak relay serve` constructed upstream relay components and slept. It
never assembled a listening server, downstream handler, delegate chain, or
durable global cursor, and retry ownership was split across `RelayClient`
and `RelayUpstreamManager`. Workstream 02 A5 required choosing between
(1) building a real downstream Relay behind the command, (2) marking it
experimental, or (3) removing it until the service is funded.

Meanwhile `zuk` is the repository's real relay binary: it assembles the
listener, downstream handler, and durable cursor state, and the relay
component classes are exercised in production paths by `zuk`,
`PDSRelayService`, and `AppViewIngestEngine` — including account-event
forwarding added in `28641e671`/`a3f8d3c53`.

## Decision

Option 3: remove the command. `PDSCLIRelayCommand.h/.m` and
`PDSCLIRelayCommandTests.m` are deleted and `PDSCLIRegisterAll.m`/
`test_main.m` cleaned. `zuk` is the canonical relay binary.

The underlying relay components (`RelayClient`, `RelayUpstreamManager`,
`RelayDownstreamHandler`, firehose handlers) are deliberately untouched:
they have production callers and their E2E coverage (scenarios 96/97)
remains authoritative.

## Consequences

- No CLI surface advertises an unassembled relay service; the A5
  "half-built product" risk is closed by removal rather than completion.
- Reviving a `kaszlak`-hosted relay later means a new command built to
  A5 option-1 acceptance (upstream event reaches a downstream subscriber,
  restart resumes from persisted cursor, duplicates tolerated, gaps not,
  exactly one reconnect owner). Git history retains the deleted command.
- Operator manifests and docs must not reference `kaszlak relay serve`.
