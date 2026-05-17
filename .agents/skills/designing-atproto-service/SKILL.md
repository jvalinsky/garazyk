---
name: designing-atproto-service
description: "Design or integrate an AT Protocol service into the Garazyk Deno scenario harness. Covers topology entries, Docker service wiring, XRPC client usage, scenario coverage, and package boundaries."
---

# Designing an AT Protocol Service

Use this skill when adding a service to the local ATProto test network or wiring scenarios against a new service. The current repository is a Deno workspace; service orchestration is represented through packages and scenario topology files rather than Objective-C binaries.

## Relevant Surfaces

```text
packages/atproto-topology/        Topology schemas, presets, manifests, and compiler
packages/atproto-client/          Typed XRPC clients generated from lexicons
packages/docker-client/           Docker and Docker Compose primitives
packages/scenario-runner/         Scenario execution, reports, timing, assertions
scripts/scenarios/topologies/     JSON topology files used by scenario runs
scripts/scenarios/scenarios/      E2E scenario files
scripts/run_scenarios.ts          Main scenario runner entry point
```

## Workflow

1. Define the service's role in the topology: PDS, AppView, Relay/BGS, PLC, labeler, feed generator, chat, or custom service.
2. Add or update topology schemas and presets in `packages/atproto-topology` if the service needs new configuration fields.
3. Add Docker Compose rendering or Docker client support through `packages/docker-client` and topology compiler code.
4. Add typed client methods in `packages/atproto-client` only through lexicon generation when lexicons change.
5. Add a scenario under `scripts/scenarios/scenarios/` that proves the service participates in the expected workflow.
6. Run package checks and a targeted scenario run.

## Topology Rules

- Keep service configuration validated by Zod schemas in `packages/atproto-topology`.
- Preserve explicit port, image, health check, and dependency fields where the topology compiler needs deterministic output.
- Prefer adding named topology presets when a service is reusable across scenarios.
- Keep topology JSON files under `scripts/scenarios/topologies/` declarative. Put logic in the TypeScript compiler/package layer.

## Client And Lexicon Rules

The XRPC client in `packages/atproto-client/lexicons.ts` is generated from `lexicons/`.

After lexicon changes, regenerate:

```bash
deno run -A packages/atproto-client/scripts/generate.ts
```

Then verify:

```bash
deno check packages/*/mod.ts scripts/*.ts
```

Do not hand-edit generated XRPC methods unless the generator itself is being fixed.

## Scenario Coverage

For a new service, add at least one scenario that:

- creates any required accounts or service records,
- waits for service health through scenario-runner helpers,
- exercises the XRPC or HTTP surface through typed clients where available,
- records meaningful `ScenarioResult` steps with `timedCall`,
- fails with enough context to diagnose service startup or protocol issues.

Use the `adding-scenario` skill for scenario file structure and assertions.

## Quality Gates

Run:

```bash
deno task check
deno task test
deno task lint
deno fmt --check packages/ scripts/
```

If the change touches Docker orchestration, also run the smallest scenario or topology compile command that exercises the new service.
