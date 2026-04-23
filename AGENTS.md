# AGENTS.md

This file provides the canonical operational guidance for AI assistants working with this repository. It serves as the project's "Global Constitution," defining non-negotiable rules and pointing to specific operational workflows.

## Quick Reference

This project uses the **WAT (Workflows, Agents, Tools)** framework for orchestration.
- **Workflows**: Multi-step procedures in `.opencode/workflows/`.
- **Agents**: Orchestrator + named subagents defined as Markdown files in `.agents/agents/`. The Orchestrator delegates scoped tasks to subagents via the `Task` tool.
- **Tools**: Two layers.
  - `scripts/` — human-invoked runners (freeform stdout).
  - `.opencode/tools/` — AI-invoked wrappers that emit structured JSON over those runners.
- **Skills**: Reusable domain knowledge in `.agents/skills/` (loaded by subagents as context; orthogonal to WAT).

## Tool Compatibility

The repo works with **Claude Code**, **opencode**, and **Codex CLI**. All three read `AGENTS.md` (this file) as the source of rules. The agent/skill rosters are discovered differently per tool:

| Tool | Agents | Skills |
|---|---|---|
| opencode | `.agents/agents/*.md` (auto) | `.agents/skills/*/SKILL.md` (auto) |
| Claude Code | `.claude/agents/` → symlink → `.agents/agents/` | `.claude/skills/` → symlink → `.agents/skills/` |
| Codex CLI | enumerated in `.codex/config.toml` | enumerated in `.codex/config.toml` |

Canonical home is `.agents/`. Do not edit the `.claude/` symlinks or duplicate content — update `.agents/` and Codex's `.codex/config.toml` together.

## Operational Workflows

For detailed procedures, follow the appropriate workflow:
- [Quality Gates](.opencode/workflows/quality_gates.md) - Mandatory pre-push checks.
- [Production Deployment](.opencode/workflows/production_deployment.md) - Procedures for `pds.garazyk.xyz`.
- [Session Completion](.opencode/workflows/session_completion.md) - Mandatory steps for ending a work session.
- [Feature Implementation](.opencode/workflows/feature_implementation_workflow.md) - Deciduous-tracked implementation loop.
- [Pull Request Review](.opencode/workflows/pull_request_review_workflow.md) - Delegation pattern for diff review.

## Agents

The Orchestrator MUST delegate scoped work to the subagents defined in [`.agents/agents/`](.agents/agents/). Delegation rule: **one skill per subagent invocation.** If a task crosses domains, spawn multiple subagents in parallel instead of widening any one of them.

| Subagent | When to spawn |
|---|---|
| `security-auditor` | Changes to auth, crypto, storage, secrets, or log-emitting code. |
| `concurrency-auditor` | Changes to threading, queues, locks, or anywhere `dispatch_*` appears. |
| `architecture-auditor` | Changes to XRPC handlers, service boundaries, SQLite usage, or Linux/GNUstep paths. |
| `web-ui-auditor` | Changes under `AdminUI/` or any HTML/JS asset. |
| `atproto-coverage-auditor` | Changes to `Lexicons/` or XRPC registration. |
| `pr-reviewer` | Any branch/PR review — the Orchestrator never reads the full diff itself. |

## Critical Mandates

1. **Always use out-of-source builds** - Never run `cmake` in repo root.
2. **Use XcodeGen on macOS** - Run `xcodegen generate` before building.
3. **Decision Tracking** - Every significant action MUST be recorded in the `deciduous` graph.
4. **Subagent Delegation** - Delegate complex analysis or audits to subagents to keep the Orchestrator context window clean.
5. **No Chitchat** - Stay professional, concise, and direct.

## Repository Skills (Audits)

Consolidated audit workflows are located in `.agents/skills/`.
- `objc-security-audit` - Deep security review (SQLi, Crypto, Secrets).
- `objc-concurrency-audit` - Thread-safety and race condition analysis.
- `objc-architecture-audit` - Structural integrity and platform compatibility.
- `web-ui-audit` - Accessibility and pattern review.
- `atproto-coverage-audit` - Lexicon and endpoint coverage.

## Utility Scripts

- `scripts/run-tests.sh` - Run all tests.
- `scripts/stub_find.sh .` - Scan for TODO/FIXME markers.
- `scripts/wipe_and_rebuild.sh` - Clean rebuild from scratch.
- `scripts/backup_pds.sh` - SQLite-safe production backup.
