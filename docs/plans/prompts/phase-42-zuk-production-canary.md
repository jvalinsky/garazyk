---
phase: 42
title: Zuk production resource canary and closeout
status: pending
agent: worker
depends_on: [37, 38, 39, 40, 41]
last_updated: 2026-08-13
---

# Phase 42: Zuk production resource canary and closeout

## Mission

Deploy the fully bounded relay to `bingus`, prove cursor correctness and a
large sustained resource reduction under real traffic, rehearse rollback, and
close workstream 17 with dated evidence. No source-only or short smoke result
can complete this phase.

## Read first

- all of [workstream 17](../workstreams/17-zuk-relay-resource-bounds.md)
- [incident evidence and baseline contract](../workstreams/17-zuk-relay-resource-bounds/incident-evidence.md)
- phases 37–41 completion evidence and rollback notes
- Zuk NixOS module and operator runbook produced by Phase 41
- `.agents/skills/garazyk-release-ops/SKILL.md`
- deployment-specific repository guide and current `bingus` configuration

## Authority and safety

Production deployment is authorized only when the operator has approved the
exact revision/configuration or this phase is being executed under an existing
deployment instruction. Never print credentials, private key material, auth
headers, raw records, complete DID documents, or replay payloads.

Do not delete replay data, restore a database, terminate the unidentified
loopback client, or modify reverse-proxy policy beyond the documented change
without explicit scope and a resolved target.

## Checkpoint 1 — Establish the release

Record:

- host and systemd unit (`bingus`, `zuk`);
- deployment mode and exact candidate revision/binary hash;
- previous known-good revision and binary/config rollback location;
- NixOS generation or service unit source;
- service config path and credential sources by name only;
- relay state/replay directory and filesystem capacity;
- reverse proxy and the current `requestCrawl` exposure;
- expected upstream count and required downstream clients;
- whether phases 37–41 were deployed incrementally already.

Stop if the running binary/revision cannot be identified or no rollback binary
can be staged.

## Checkpoint 2 — Local and cross-platform release gates

From a clean candidate revision run:

```bash
deno task check
deno task lint
deno task test
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests --gated=run
./scripts/dev/check_module_boundaries.sh .
./scripts/check_module_boundaries.sh build
./scripts/check_namespace.sh build
./scripts/check-recursive-setters.sh
./scripts/check_no_host_process_exit.sh
deno run -A scripts/generate_nsid_constants.ts --check
deno run -A scripts/dev/generate_skill_index.ts --check
deno run --allow-read packages/narzedzia/nsid_registration_literal_check.ts .
deno run -A scripts/dev/check_codex_agent_roles.ts
deno run -A scripts/docs/repo_docs.ts sync
deno run -A scripts/docs/repo_docs.ts validate --internal-strict --orphans
```

Also run the Linux/GNUstep Zuk/Sync tests, NixOS module smoke, Relay Admin UI
smokes, and structured scenarios from phases 37–41. Record every command,
revision, date, pass/fail, and artifact location. A known unrelated failure
requires an explicit disposition; do not relabel it green.

## Checkpoint 3 — Baseline and backup

Capture the incident baseline contract immediately before cutover, including
cgroup memory/swap/events, queue and replay metrics, sockets, upstream set,
validation reason counts, logs/minute, unit network/I/O, and health/Admin
snapshots.

Create and verify a backup of relay state and durable replay metadata using the
project's supported mechanism or a quiesced filesystem procedure documented by
Phase 39. Record path, size, checksum/verification result, and restore command
outside the repository. Do not back up credentials into the artifact.

## Checkpoint 4 — Deploy with explicit stop conditions

Validate configuration before restart. Apply internal resource limits and
feature flags first. Apply the selected `MemoryHigh`; introduce `MemoryMax` and
`MemorySwapMax` only at the values justified by preflight measurements.

Tail startup logs and stop/roll back immediately on:

- persistence recovery or sequence-integrity failure;
- crash/restart loop;
- failure to connect required upstreams;
- inability of owned downstreams to resume from cursor;
- sustained ingress rejection with no pause/recovery;
- memory crossing the hard ceiling during ordinary startup;
- validation policy dropping unexplained majority-valid traffic;
- health/Admin endpoint unavailable.

## Checkpoint 5 — Thirty-minute adversarial smoke

Exercise concurrently:

1. no-cursor live subscriber and 25 reconnects;
2. retained-cursor replay crossing to live;
3. deliberately slow subscriber until controlled drop;
4. required AppView/Beskid/owned consumers reconnecting from saved cursors;
5. upstream pause/resume using a safe bounded load source;
6. crawl requests up to and one beyond each configured quota;
7. admin polling and health state changes;
8. service restart with sequence/replay recovery.

Acceptance:

- no omitted-cursor retained replay;
- no sequence gap/reuse from restart or crossover;
- every queue remains within count and byte caps;
- slow subscriber drops once and replay stops;
- quota rejection allocates no new upstream;
- no credential/user-data leakage;
- RSS remains below 1.5 GiB after warmup unless a dated adjustment was approved
  in workstream 17.

## Checkpoint 6 — Six-hour observation

Compare 15-minute windows for:

- RSS, peak RSS, swap current, memory pressure/OOM events;
- ingress/subscriber/replay counts and bytes;
- pause duration and worker/resolver latency;
- input/output network bytes and replay bytes by reason;
- logs per severity/category;
- reconnects/drops and upstream authoritative set;
- replay disk size, rotation, GC, append/sync failures;
- validation attempts/results by curve/reason;
- health state duration.

RSS growth from the first to final window must be under 128 MiB. Investigate
any monotonic queue, cache, segment-reader, or connection count before
continuing.

## Checkpoint 7 — Twenty-four-hour canary

Required success criteria:

| Signal | Gate |
| --- | --- |
| RSS | Below 2.0 GiB throughout ordinary operation |
| Service swap | No more than 128 MiB added after warmup |
| Restarts/OOM | Zero unexpected restarts and zero OOM kills |
| Queue bounds | No configured count/byte limit exceeded |
| No-cursor semantics | Zero retained-window replays |
| Sequence | No reuse, unexplained gap, or crossover duplicate |
| Disk replay | Within time and 5 GiB starting caps; GC healthy |
| Logs | Fewer than 10 repeated pressure/signature records per minute per source after transition |
| Traffic | Output/input ratio explained by current subscribers, not reconnect catch-up loop |
| Upstreams | Admin/health gauge equals authoritative manager state |
| Validation | Failure distribution explained; strict policy only if its promotion threshold passed |

Record actual numbers, not only pass/fail labels. If a starting threshold was
adjusted, record the before/after value and evidence.

## Rollback rehearsal

Before closeout, prove the documented rollback in a non-production or bounded
maintenance window:

1. retain replay segments and metadata;
2. select the previous binary/config/NixOS generation;
3. restart and verify the prior health contract;
4. state the reduced replay guarantee while the old binary runs;
5. roll forward again and prove sequence recovery from retained data.

Do not restore the backup unless corruption or an incompatible migration
requires it. Prefer forward repair for additive replay metadata.

## On completion

- Add the dated canary table, structured scenario IDs, revision, configuration
  budget, and rollback evidence to workstream 17.
- Update mega-plan item 17 and phases 37–42 to complete.
- Update the Relay Admin brief and operator guide with final values.
- Archive/delete completed prompt detail according to plan governance only
  after durable evidence is captured.
- Add a deciduous outcome under goal 416 with the deployed revision and mark
  the goal complete.

If any 24-hour gate fails, keep this phase `in-progress` or name a concrete
blocker. A service that merely stayed alive is not a successful canary.
