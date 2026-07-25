---
title: Deno Scenario Framework
---

# Deno Scenario Framework

Hamownia runs integration scenarios against local AT Protocol services. It can
start a Docker or binary topology, run selected scenarios, and write reports.

The implementation is in `packages/hamownia/`. Scenario files and topology
definitions are under `scripts/scenarios/`.

## Install

```sh
deno install
```

Docker must be running when Hamownia manages a container topology.

## Common commands

```sh
# List scenarios
deno task hamownia run --list

# Run one scenario and start its services
deno task hamownia run --setup 01_account_lifecycle

# Run against services that are already running
deno task hamownia run --no-setup 01_account_lifecycle

# Leave the services running after the run
deno task hamownia run --setup --keep-running 01_account_lifecycle

# Stop managed services
deno task hamownia run --teardown-only
```

Run `deno task hamownia help <command>` for current options.

## Commands

| Command        | Use                                                     |
| -------------- | ------------------------------------------------------- |
| `run`          | Run scenarios and manage setup or teardown              |
| `agent list`   | List scenarios as JSON                                  |
| `agent run`    | Run scenarios with NDJSON events on stdout              |
| `agent triage` | Read existing reports and summarize failures            |
| `service`      | Start, stop, inspect, or reseed local services          |
| `demo`         | Start a seeded local topology                           |
| `smoke`        | Check basic account and record operations against a PDS |
| `fuzz`         | List or run native fuzz targets                         |
| `test`         | Run package tests                                       |

Global `--verbose` and `--quiet` flags control human-readable logging.

## Topologies

`@garazyk/schemat` defines topology manifests. `@garazyk/laweta` controls
Docker. `@garazyk/gruszka` provides typed XRPC clients.

Topology presets live in `scripts/scenarios/topologies/`. A scenario manifest
declares the roles and capabilities a scenario needs. Hamownia uses that data to
decide whether a topology can run the scenario.

The manifest fields are:

| Field          | Meaning                            |
| -------------- | ---------------------------------- |
| `requires`     | Required role and capability pairs |
| `optional`     | Optional role and capability pairs |
| `needsPds2`    | Whether a second PDS is required   |
| `browserFlows` | Supported browser test modes       |
| `timeout`      | Per-scenario timeout               |
| `parameters`   | Named scenario inputs and defaults |

Manifest entries are defined in `packages/hamownia/scenario_metadata.ts`. Their
keys match the two-digit scenario IDs.

## Agent output

`agent run` writes one JSON object per line to stdout. Human-readable logs go to
stderr. Consumers should ignore event types they do not recognize.

Common event types are:

| Event               | Meaning                    |
| ------------------- | -------------------------- |
| `run_start`         | A run began                |
| `scenario_start`    | A scenario began           |
| `scenario_complete` | A scenario ended           |
| `service_failure`   | A managed service failed   |
| `run_progress`      | Aggregate progress changed |
| `run_finished`      | The run ended              |

The scenario dashboard maps these records to its internal run events in
`scripts/scenario-dashboard/services/run_manager.ts`.

## Reports and triage

Runs write JSON reports unless `--no-json` is used. Choose a report directory
with `--reports-dir` and a stable identifier with `--run-id`.

```sh
deno task hamownia agent triage
deno task hamownia agent triage --run-id RUN_ID
```

## Authoring

Read these files before adding a scenario:

- `scripts/scenarios/README.md`
- `scripts/scenarios/SCENARIO_STANDARDS.md`
- `scripts/scenarios/topologies/README.md`

Add the scenario file, register any manifest requirements, and run it against
the smallest compatible topology.
