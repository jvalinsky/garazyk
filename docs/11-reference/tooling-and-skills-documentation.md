---
title: Tooling & Skills Documentation
---

# Tooling & Skills Documentation

## Scripts

| File | Description |
|---|---|
| `scripts/API_README.md` | Scripts API overview |
| `scripts/docs/README.md` | Documentation tooling overview |
| `scripts/docs/configs/README.md` | Doc tooling configuration |
| `scripts/docs/lib/README-content-updater.md` | Content updater library |
| `scripts/docs/lib/README-git-operations.md` | Git operations library |
| `scripts/docs/lib/README-link-parser.md` | Link parser library |
| `scripts/docs/lib/README-migration-mapping.md` | Migration mapping library |
| `scripts/docs/lib/README-path-resolver.md` | Path resolver library |
| `scripts/plc/README.md` | PLC test utilities |
| `scripts/REVIEW-e2e-harness.md` | E2E harness review |
| `scripts/scenarios/README.md` | Scenario runner overview |
| `scripts/scenarios/SCENARIO_STANDARDS.md` | Scenario authoring standards |
| `scripts/scenarios/topologies/README.md` | Topology definitions |

## Deno Tasks

| Task | Description |
|---|---|
| `deno task test` | Run all package tests |
| `deno task check` | Typecheck all packages |
| `deno task hamownia` | Run scenario suite |
| `deno task narzedzia` | Run boundary check |
| `deno task dashboard:tui` | Launch scenario dashboard TUI |

## Deno Packages

| Package | Tests | JSR | Description |
|---|---|---|---|
| `gruszka` | 35 | ✅ | XRPC client generation |
| `schemat` | 67 | ✅ | Topology schema & compilation |
| `laweta` | 63 | ✅ | Docker orchestration |
| `hamownia` | 73 | ❌ | Scenario runner |
| `narzedzia` | 11 | ❌ | Developer tooling |
| `tui` | 227 | ❌ | Terminal UI framework |

## AI Agent Skills

Skills are located in `.agents/skills/`. See `AGENTS.md` for the full subagent delegation table and
`AGENTS_QUICKREF.md` for quick reference. Key documentation-related skills:

| Skill | Purpose |
|---|---|
| `technical-writer` | API docs, READMEs, ADRs |
| `rewriting-code-comments` | ObjC HeaderDoc conventions |
| `deslop` | Remove AI writing patterns |
| `slop-detector` | Detect low-effort generated code |
| `expand_md_topic` | Expand markdown outlines |
