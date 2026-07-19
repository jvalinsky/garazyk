# Operational Guidance for AI Assistants

This file defines the rules and workflows for AI assistants working in this repository.

## Framework Overview

The project uses the **WAT (Workflows, Agents, Tools)** framework:

- **Workflows**: The plan-governance loop in `docs/plans/` (mega plan, workstreams, and
  `docs/plans/prompts/` execution prompts). The former `.opencode/workflows/` procedures were
  removed in `25e72b5a1`.
- **Agents**: Codex custom agents are defined in `.codex/agents/`; compatibility manifests for
  Claude Code and opencode remain in `.agents/agents/`.
- **Tools**: Human-invoked runners in `scripts/` and AI-invoked wrappers in `.opencode/tools/`.
- **Skills**: Domain knowledge in `.agents/skills/`.

### Tool Configuration

The repository supports **Claude Code**, **opencode**, and **Codex CLI**. Shared skills live in
`.agents/skills/`; Codex project configuration lives in `.codex/`. The `.claude/` directory holds
only local settings and worktrees now (its old symlinks and commands were removed in `25e72b5a1`).

## Standard Workflows

The old `.opencode/workflows/` files are removed. Current sources of truth:

- **Quality Gates** (pre-push): `deno task check && deno task lint && deno task test`, then
  `cmake --build build --target AllTests --parallel 4 && ./build/tests/AllTests --gated=run`.
  Run `xcodegen generate` before macOS Xcode builds.
- **Planned work**: pick up phases via `docs/plans/prompts/README.md` (loop protocol); the
  mega plan and workstreams in `docs/plans/` stay authoritative.
- **Pull Request Review**: delegate to the Codex `pr_reviewer` agent (or the compatibility
  `pr-reviewer` role in another client; see below).

## Subagent Delegation

The primary agent delegates independent work through the client's built-in subagent tools. Codex
loads the project roles from `.codex/agents/*.toml`; the Markdown manifests under
`.agents/agents/` describe the equivalent roles for other supported clients. Use one skill per
subagent invocation.

| Codex agent                 | Compatibility manifest        | Responsibility                                                 |
| --------------------------- | ----------------------------- | -------------------------------------------------------------- |
| `security_auditor`          | `security-auditor`            | Auth, crypto, storage, secrets, and logging.                   |
| `concurrency_auditor`       | `concurrency-auditor`         | Threading, queues, and locks.                                  |
| `architecture_auditor`      | `architecture-auditor`        | XRPC handlers, service boundaries, and platform compatibility. |
| `web_ui_auditor`            | `web-ui-auditor`              | `AdminUI/` and web assets.                                     |
| `atproto_coverage_auditor`  | `atproto-coverage-auditor`    | `Lexicons/` and XRPC registration.                             |
| `sqlite_perf_auditor`       | `sqlite-perf-auditor`         | SQLite schema/query changes, migrations, index and PRAGMA fit. |
| `scenario_runner`           | `scenario-runner`             | Structured hamownia scenario runs; dated evidence for gates.   |
| `pr_reviewer`               | `pr-reviewer`                 | Branch and pull request reviews.                               |

## Project Skills

Skills are located in `.agents/skills/`. The LLM loads them on-demand via the `skill` tool when a
task matches their description.

| Skill                         | When to Use                                                              |
| ----------------------------- | ------------------------------------------------------------------------ |
| `gnustep-compat`              | Platform detection, GNUstep bugs/workarounds, compat shims, Docker build |
| `tui-capture-replay`          | Record TUI interactions as asciicast + export HTML playback via VirtualTuiHarness |
| `garazyk-testing`             | Test infrastructure, mock patterns, environment gating, registration     |
| `garazyk-database`            | SQLite connection pooling, WAL config, migrations, actor store           |
| `atproto-coverage-audit`      | XRPC endpoint stub detection, schema sync against lexicons               |
| `atproto-scenario-testing`    | Narrative-driven scenarios against local ATProto services                |
| `better-code-objc`            | ARC, nullability, generics, GCD, NSError patterns                        |
| `better-code-opencode`        | Correctness, Clarity, Changeability, Primitives over Features            |
| `better-code-security-design` | Sink prevention, source-to-sink tracing, safe primitives                 |
| `debugging-objc-crashes`      | Systematic macOS ObjC crash diagnosis                                    |
| `deslop`                      | Remove AI writing patterns from prose                                    |
| `objc-architecture-audit`     | Portability, XRPC contracts, service boundaries, parser hardening        |
| `objc-concurrency-audit`      | Data races, deadlocks, re-entrancy, queue contracts                      |
| `objc-security-audit`         | SQL injection, crypto, secrets, log redaction                            |
| `professional-bash-scripting` | Maintainable, secure bash scripts                                        |
| `rewriting-code-comments`     | HeaderDoc standards, remove AI-isms                                      |
| `slop-detector`               | Low-effort LLM code patterns, boilerplate, fragile code                  |
| `sqlite-sql-best-practices`   | SQLite correctness, query perf, index design, migrations                 |
| `sqlite-performance-optimization` | Query-plan analysis, indexing strategy, PRAGMA tuning, write batching |
| `using-deciduous`             | Track goals/decisions in the deciduous decision graph                    |
| `deciduous-viz`               | Generate interactive HTML from the deciduous decision graph              |
| `web-ui-audit`                | Accessibility (WCAG), JS patterns, frontend security                     |
| `expand_md_topic`             | Expand markdown outlines into documentation                              |

## Development Rules

1. **Builds**: Use out-of-source builds.
2. **macOS**: Run `xcodegen generate` before building.
3. **Tracking**: Record actions in the `deciduous` graph.
4. **Style**: Maintain professional and direct communication.

## Decision Graph Workflow

Log decisions in the `deciduous` graph during development.

### Commands

The old `/decision`, `/recover`, `/work`, `/document`, `/build-test`, and `/sync` slash commands
were removed in `25e72b5a1`. Use the `deciduous` CLI directly; load
`.agents/skills/using-deciduous` for the workflow.

### Decision Flow

The standard flow through the graph is: `goal -> options -> decision -> actions -> outcomes`

- **Goals**: Define objectives.
- **Options**: Approaches considered for a goal.
- **Decisions**: Selected approach from the options.
- **Actions**: Implementation of the decision.
- **Outcomes**: Results of the actions.

### Prompt Capture

Use the exact user message when creating goal nodes. Use `--prompt-stdin` for multi-line input.

```bash
deciduous add goal "Title" -c 90 --prompt-stdin << 'EOF'
[User Message]
EOF
```

### Quick Commands

| Action       | Command                     |
| ------------ | --------------------------- |
| View Graph   | `deciduous graph`           |
| Sync Graph   | `deciduous sync`            |
| Check Status | `deciduous opencode status` |
