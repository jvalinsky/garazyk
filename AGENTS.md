# Operational Guidance for AI Assistants

This file defines the rules and workflows for AI assistants working in this repository.

## Framework Overview

The project uses the **WAT (Workflows, Agents, Tools)** framework:

- **Workflows**: Procedures located in `.opencode/workflows/`.
- **Agents**: Orchestrator and subagents defined in `.agents/agents/`. The orchestrator uses the
  `Task` tool to delegate work.
- **Tools**: Human-invoked runners in `scripts/` and AI-invoked wrappers in `.opencode/tools/`.
- **Skills**: Domain knowledge in `.agents/skills/`.

### Tool Configuration

The repository supports **Claude Code**, **opencode**, and **Codex CLI**. Configuration and skill
files are located in `.agents/`. Do not edit the `.claude/` symlinks directly.

## Standard Workflows

Follow these workflows for specific tasks (see `.opencode/workflows/`):

- **Quality Gates**: Pre-push checks.
- **Production Deployment**: Deployment to `pds.garazyk.xyz`.
- **Session Completion**: Steps for ending a work session.
- **Feature Implementation**: Implementation loop.
- **Pull Request Review**: Diff review delegation.

## Subagent Delegation

The orchestrator delegates work to the subagents in `.agents/agents/`. Use one skill per subagent
invocation.

| Subagent                   | Responsibility                                                 |
| -------------------------- | -------------------------------------------------------------- |
| `security-auditor`         | Auth, crypto, storage, secrets, and logging.                   |
| `concurrency-auditor`      | Threading, queues, and locks.                                  |
| `architecture-auditor`     | XRPC handlers, service boundaries, and platform compatibility. |
| `web-ui-auditor`           | `AdminUI/` and web assets.                                     |
| `atproto-coverage-auditor` | `Lexicons/` and XRPC registration.                             |
| `pr-reviewer`              | Branch and pull request reviews.                               |

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
| `using-deciduous`             | Track goals/decisions in the deciduous decision graph                    |
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

| Command       | Purpose                                          |
| ------------- | ------------------------------------------------ |
| `/decision`   | Manage the decision graph.                       |
| `/recover`    | Restore session context.                         |
| `/work`       | Start a tracked work transaction.                |
| `/document`   | Generate documentation for files or directories. |
| `/build-test` | Run build and tests with tracking.               |
| `/sync`       | Sync data across environments.                   |

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
