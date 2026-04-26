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


## Decision Graph Workflow

**THIS IS MANDATORY. Log decisions IN REAL-TIME, not retroactively.**

### Available Slash Commands

| Command | Purpose |
|---------|---------|
| `/decision` | Manage decision graph - add nodes, link edges, sync |
| `/recover` | Recover context from decision graph on session start |
| `/work` | Start a work transaction - creates goal node before implementation |
| `/document` | Generate comprehensive documentation for a file or directory |
| `/build-test` | Build the project and run the test suite |
| `/serve-ui` | Start the decision graph web viewer |
| `/sync-graph` | Export decision graph to GitHub Pages |
| `/decision-graph` | Build a decision graph from commit history |
| `/sync` | Multi-user sync - pull events, rebuild, push |

### Available Skills

| Skill | Purpose |
|-------|---------|
| `/pulse` | Map current design as decisions (Now mode) |
| `/narratives` | Understand how the system evolved (History mode) |
| `/archaeology` | Transform narratives into queryable graph |

### The Node Flow Rule - CRITICAL

The canonical flow through the decision graph is:

```
goal -> options -> decision -> actions -> outcomes
```

- **Goals** lead to **options** (possible approaches to explore)
- **Options** lead to a **decision** (choosing which option to pursue)
- **Decisions** lead to **actions** (implementing the chosen approach)
- **Actions** lead to **outcomes** (results of the implementation)
- **Observations** attach anywhere relevant
- Goals do NOT lead directly to decisions -- there must be options first
- Options do NOT come after decisions -- options come BEFORE decisions

### The Core Rule

```
BEFORE you do something -> Log what you're ABOUT to do
AFTER it succeeds/fails -> Log the outcome
CONNECT immediately -> Link every node to its parent
AUDIT regularly -> Check for missing connections
```

### Behavioral Triggers - MUST LOG WHEN:

| Trigger | Log Type | Example |
|---------|----------|---------|
| User asks for a new feature | `goal` **with -p** | "Add dark mode" |
| Exploring possible approaches | `option` | "Use Redux for state" |
| Choosing between approaches | `decision` | "Choose state management" |
| About to write/edit code | `action` | "Implementing Redux store" |
| Something worked or failed | `outcome` | "Redux integration successful" |
| Notice something interesting | `observation` | "Existing code uses hooks" |

### Document Attachments

Attach files (images, PDFs, diagrams, specs, screenshots) to decision graph nodes for rich context.

```bash
# Attach a file to a node
deciduous doc attach <node_id> <file_path>
deciduous doc attach <node_id> <file_path> -d "Architecture diagram"
deciduous doc attach <node_id> <file_path> --ai-describe

# List documents
deciduous doc list              # All documents
deciduous doc list <node_id>    # Documents for a specific node

# Manage documents
deciduous doc show <doc_id>     # Show document details
deciduous doc open <doc_id>     # Open in default application
deciduous doc detach <doc_id>   # Soft-delete (recoverable)
```

### CRITICAL: Capture VERBATIM User Prompts

**Prompts must be the EXACT user message, not a summary.**

```bash
# Use --prompt-stdin for multi-line prompts
deciduous add goal "Add auth" -c 90 --prompt-stdin << 'EOF'
The full verbatim user request goes here...
EOF

# Or use the prompt command to update existing nodes
deciduous prompt 42 << 'EOF'
The full verbatim user message goes here...
EOF
```

### CRITICAL: Maintain Connections

| When you create... | IMMEDIATELY link to... |
|-------------------|------------------------|
| `outcome` | The action that produced it |
| `action` | The decision that spawned it |
| `decision` | The option(s) it chose between |
| `option` | Its parent goal |
| `observation` | Related goal/action |
| `revisit` | The decision/outcome being reconsidered |

**Root `goal` nodes are the ONLY valid orphans.**

### Quick Commands

```bash
deciduous add goal "Title" -c 90 -p "User's original request"
deciduous add action "Title" -c 85
deciduous link FROM TO -r "reason"
deciduous serve   # View live graph
deciduous sync    # Export for static hosting
```

### Node Types

| Type | Purpose |
|------|---------|
| `goal` | High-level objectives |
| `option` | Approaches considered (come from goals) |
| `decision` | Choosing an option (come from options) |
| `action` | What was implemented (come from decisions) |
| `outcome` | What happened (come from actions) |
| `observation` | Technical insights (attach anywhere) |
| `revisit` | Reconsidering a decision |

### Multi-User Sync

Sync decisions with teammates via event logs:

```bash
# Check sync status
deciduous events status

# Apply teammate events (after git pull)
deciduous events rebuild

# Compact old events periodically
deciduous events checkpoint --clear-events
```

Events auto-emit on add/link/status commands. Git merges event files automatically.

### Session Start Checklist

```bash
deciduous check-update    # Update needed? Run 'deciduous update' if yes
deciduous nodes           # What decisions exist?
deciduous edges           # How are they connected?
deciduous doc list        # Any attached documents to review?
git status                # Current state
```
