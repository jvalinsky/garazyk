# Operational Guidance for AI Assistants

How to work in this repository: where things live, which gates must pass, and how
planned work is picked up and recorded.

`CLAUDE.md` is the companion to this file and covers the *codebase*: build and
test commands, architecture, and the conventions that will bite you (absolute
imports, two-step test registration, generated NSID constants, SPDX headers,
per-file style). Read it first for anything that touches `Garazyk/`. This file
covers the *process* around that work and does not repeat it.

## Where things live

| Path | Holds |
| --- | --- |
| `docs/plans/` | The only repository-wide backlog: mega plan, workstreams, phase prompts |
| `docs/adr/` | Durable design decisions (34 accepted). Check before "fixing" surprising behavior |
| `.agents/skills/` | 62 domain skills, indexed in [`.agents/skills/INDEX.md`](.agents/skills/INDEX.md) |
| `.agents/agents/` | Subagent role manifests for Claude Code and opencode |
| `.codex/agents/` | The same roles as Codex `*.toml` definitions |
| `.claude/skills/` | Claude-specific compatibility skills; `.claude/worktrees/` holds local worktrees |
| `scripts/` | Human- and agent-invoked runners, generators, and CI gates |
| `nix/`, `nixos/` | Linux GNUstep toolchain + flake packages; NixOS service modules and example. Deploy guide: [`docs/20-explanation/guides/NIXOS.md`](docs/20-explanation/guides/NIXOS.md) |
| deciduous graph | Decision and outcome history. Not a backlog — `docs/plans/` owns that |

Nothing outside `docs/plans/` is an active plan. If you find a roadmap,
next-steps file, or remediation plan elsewhere, it is stale by definition;
fold anything useful into a workstream rather than reviving it.

## Plan governance

Four rules govern every plan change. They exist because each was violated once
and cost a session's work.

1. **The workstream wins.** When a `docs/plans/prompts/phase-*.md` file and its
   workstream disagree, the workstream is authoritative and the prompt gets
   corrected. Prompts are derived execution text, not a second backlog.
2. **Plan state lands in the same change as the code.** A commit that finishes a
   slice also updates the workstream entry and the phase frontmatter. A code
   commit followed by a "docs: record …" commit is acceptable; a code commit with
   no plan update at all leaves the next session reading a lie.
3. **Evidence is dated and current.** A failing scenario counts only from a
   current structured `hamownia agent` run. Dated failure snapshots are history,
   not backlog. Update `last_verified` when you recheck source or test evidence.
4. **Decide, don't drift.** An item that cannot proceed gets a recorded decision
   — complete, closed-not-pursued with a rationale, or blocked with a named
   input under a `## Blocked on` heading — rather than sitting "partial"
   indefinitely.

To see what is left, invoke the client-neutral `plan-tasks` skill. It re-reads
the plan files fresh every time; do not answer "what's next" from memory or
from an earlier table in the same conversation.

### Phase loop

`docs/plans/prompts/README.md` holds the full protocol. In short: take the
lowest-numbered phase whose `status` is `pending`/`in-progress` and whose
`depends_on` phases are all `complete`; set `in-progress` together with a body
note saying what started; run the phase's acceptance gate plus the global gates;
record evidence and set `complete`. A `blocked` dependency does not satisfy
`depends_on`.

## Quality gates

These mirror CI. Run the applicable ones before pushing.

```bash
deno task check && deno task lint && deno task test
```

```bash
cmake --build build --target AllTests --parallel 4 && ./build/tests/AllTests --gated=run
```

`--gated=run` matters: socket and integration classes are skipped by default, so
a green default run is not a green run. Keep `--parallel` at 4 — unbounded builds
exhaust memory on 16 GB machines. Run `xcodegen generate` before macOS Xcode
builds, and the Linux Docker gate for Compat, Network, or binary entrypoint
changes.

Repository-specific gates (also enforced in CI):

```bash
./scripts/dev/check_module_boundaries.sh .
./scripts/check_module_boundaries.sh build
./scripts/check_namespace.sh build
./scripts/check-recursive-setters.sh
./scripts/check_no_host_process_exit.sh
deno run -A scripts/generate_nsid_constants.ts --check
deno run -A scripts/dev/generate_skill_index.ts --check
deno run --allow-read packages/narzedzia/nsid_registration_literal_check.ts .
deno run -A scripts/dev/check_codex_agent_roles.ts
```

Documentation metadata is generated. In a fresh worktree, synchronize before
validating it:

```bash
deno run -A scripts/docs/repo_docs.ts sync
deno run -A scripts/docs/repo_docs.ts validate --internal-strict --orphans
```

## Subagent delegation

Delegate independent work through the client's built-in subagent tools. Codex
loads roles from `.codex/agents/*.toml`; the Markdown manifests in
`.agents/agents/` describe the equivalent roles for other clients. Use one skill
per subagent invocation.

| Codex agent | Compatibility manifest | Responsibility |
| --- | --- | --- |
| `security_auditor` | `security-auditor` | Auth, crypto, storage, secrets, and logging |
| `concurrency_auditor` | `concurrency-auditor` | Threading, queues, and locks |
| `architecture_auditor` | `architecture-auditor` | XRPC handlers, service boundaries, platform compatibility |
| `web_ui_auditor` | `web-ui-auditor` | Admin UI and web assets |
| `atproto_coverage_auditor` | `atproto-coverage-auditor` | Lexicons and XRPC registration |
| `sqlite_perf_auditor` | `sqlite-perf-auditor` | SQLite schema/query changes, migrations, index and PRAGMA fit |
| `scenario_runner` | `scenario-runner` | Structured hamownia scenario runs; dated evidence for gates |
| `pr_reviewer` | `pr-reviewer` | Branch and pull request reviews |

## Skills

[`.agents/skills/INDEX.md`](.agents/skills/INDEX.md) is generated from each
skill's frontmatter and lists all 62 by category. Regenerate it after adding or
renaming a skill:

```bash
deno run -A scripts/dev/generate_skill_index.ts
```

The generator is also the gate: `--check` fails when the index is stale, when a
`SKILL.md` has no `description:` (nothing can match it to a task), or when a
directory name and its frontmatter `name` disagree.

Worth knowing by name, because they carry constraints you will otherwise
rediscover the hard way:

| Skill | Why |
| --- | --- |
| `garazyk-testing` | Test registration is two steps; a missed one silently runs zero tests |
| `garazyk-database` | Connection pooling, WAL config, and migration atomicity rules |
| `gnustep-compat` | Linux is a supported platform; macOS-only assumptions break it |
| `sqlite-sql-best-practices` | Load before any schema, query, or index change |
| `sqlite-performance-optimization` | Query-plan analysis before optimizing anything |
| `using-deciduous` | The decision-graph workflow below |

## Decision graph

Record goals, decisions, and outcomes in the deciduous graph as you work. Load
`.agents/skills/using-deciduous` for the full workflow.

The standard flow is `goal → options → decision → actions → outcomes`. Use the
exact user message when creating a goal node:

```bash
deciduous add goal "Title" -c 90 --prompt-stdin << 'EOF'
[User Message]
EOF
```

| Action | Command |
| --- | --- |
| Orient on current state, gaps, and health | `deciduous pulse` |
| Inspect one node | `deciduous show <id>` |
| Update a node's status | `deciduous status <id> <state>` |
| Export the graph | `deciduous graph` / `deciduous sync` |

Close nodes as they land. A `pending` node whose work has actually shipped is
worse than no node — `pulse` is an orientation tool, and stale entries make it
point the wrong way. When work is superseded rather than finished, record that
explicitly instead of leaving the node open.

## Concurrent sessions

Multiple agents and worktrees run against this repository at once
(`.claude/worktrees/` currently holds several). Before starting any mutating
work:

- run `git status` and `git log --oneline -5`; uncommitted changes from another
  phase mean you should commit, stash, or coordinate — never fold two phases into
  one commit;
- run mutating phases in separate worktrees, never two in the same one;
- expect the deciduous graph and plan files to move underneath you, and re-read
  rather than trusting a snapshot from earlier in the session.

## Development rules

1. Use out-of-source builds (`build/`).
2. Run `xcodegen generate` before macOS Xcode builds.
3. Match the style of the file you are editing; do not run `clang-format` over
   existing files (see `CLAUDE.md`).
4. Record decisions and outcomes in the deciduous graph.
5. Keep communication direct and factual. Report what was verified, name what was
   skipped, and do not describe unrun gates as passing.
