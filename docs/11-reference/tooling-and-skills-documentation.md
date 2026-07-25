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

## Repository skills

Task instructions live under `.agents/skills/`. `AGENTS.md` lists the project
roles and required workflows. Load the skill that matches the current task
before changing code.
