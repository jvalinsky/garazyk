---
title: Tooling and Skills
---

# Tooling and Skills

## Deno tasks

| Task                      | Purpose                |
| ------------------------- | ---------------------- |
| `deno task check`         | Type-check packages    |
| `deno task lint`          | Lint packages          |
| `deno task test`          | Test packages          |
| `deno task hamownia`      | Run scenario tooling   |
| `deno task narzedzia`     | Run repository tools   |
| `deno task dashboard:tui` | Start the scenario TUI |

Task definitions live in `deno.json`.

### Relay firehose tools

The relay tools connect to `com.atproto.sync.subscribeRepos` and accept an
HTTP(S) relay base URL, converting it to the corresponding WebSocket endpoint:

- `scripts/monitor_relay_firehose.ts` runs continuously by default, reconnects
  with the highest observed cursor, prints compact events, and emits rolling
  throughput/type/action/collection statistics.
- `scripts/relay_stream_report.ts` records a bounded window and renders a
  tabular summary.
- `scripts/dump_relay_firehose.ts` prints decoded header/body JSON for a bounded
  number of binary frames.

Run the live monitor with:

```sh
deno run -A scripts/monitor_relay_firehose.ts \
  --relay-url https://relay.example.com \
  --stats-interval 5
```

The monitor treats event payloads as protocol data: binary frames are decoded by
`@garazyk/gruszka`, while byte-bearing fields are summarized rather than dumped
as unbounded base64. Use `--cursor` to start after a known sequence and
`--no-color` for log collection.

## Scripts

| Path                 | Purpose                               |
| -------------------- | ------------------------------------- |
| `scripts/dev/`       | Development checks and local commands |
| `scripts/test/`      | Test runners                          |
| `scripts/scenarios/` | Integration scenarios                 |
| `scripts/docs/`      | Documentation indexing and validation |
| `scripts/ops/`       | Backup and production operations      |
| `scripts/plc/`       | PLC utilities                         |
| `scripts/fuzzing/`   | Fuzzer helpers                        |
| `scripts/monitor_relay_firehose.ts` | Live relay firehose monitor |
| `scripts/relay_stream_report.ts` | Fixed-window firehose report |
| `scripts/dump_relay_firehose.ts` | Decoded firehose frame dump |

## Repository skills

Task instructions live under `.agents/skills/`. `AGENTS.md` lists the project
roles and required workflows. Load the skill that matches the current task
before changing code.
