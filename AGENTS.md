# Operational Guidance for AI Assistants

This repository contains a suite of Deno packages designed for orchestrating
local AT Protocol (Bluesky) networks and running automated End-to-End (E2E)
testing scenarios.

## Framework Overview

The project uses a standard Deno monorepo workspace structured in the
`packages/` directory, managed via `deno.json`.

### Key Packages

- **`packages/laweta`**: Generic Docker interaction primitives.
- **`packages/gruszka`**: Strongly typed XRPC clients derived from local
  lexicons.
- **`packages/schemat`**: Zod schemas mapping out PDS/AppView/BGS Docker
  topologies.
- **`packages/hamownia`**: The testing framework and assertion library.
- **`packages/narzedzia`**: Repository tooling for checks, docs, and operational
  commands.
- **`packages/dashboard`**: Local-only Fresh and terminal dashboard workspace
  package; not part of the JSR publish set.

### Execution Scripts

The `scripts/` directory contains CLI wrappers for testing and network
management.

- **`scripts/run_scenarios.ts`**: The main entry point for running the test
  suite.

## Development Rules

When working in this repository, assistants MUST adhere to the following
principles:

1. **Strict TypeScript Compliance**: All code must pass
   `deno check packages/*/mod.ts`. Ensure strong typing; avoid `any` or
   `unknown` where possible.
2. **JSR Publishing Constraints**: If modifying public APIs (exports) inside
   `packages/`, ensure all exports have explicit return types. `schemat` is an
   exception for exported Zod schemas.
3. **No Direct `../` Imports Across Packages**: Code inside `packages/laweta`
   must NOT import directly from `../hamownia`. Use workspace package imports
   such as `@garazyk/hamownia`; Deno resolves them from the package names in the
   workspace.
4. **Code Generation**: The XRPC methods in `@garazyk/gruszka/lexicons.ts` are
   generated from the `lexicons/` directory. If lexicons are updated, run
   `deno run -A packages/gruszka/scripts/generate.ts` to rebuild the types.

## Available Skills

Skills are located in `.agents/skills/`. The LLM loads them on-demand via the
`skill` tool when a task matches their description.

_Note: Many legacy skills related to Objective-C, GNUstep, and SQLite schema
architecture have been deprecated in this Deno transition._

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:7510c1e2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
