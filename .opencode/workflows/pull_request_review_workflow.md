# Pull Request Review Workflow

This workflow defines how the Orchestrator reviews a branch or PR. It is the canonical WAT delegation pattern for this repo: the Orchestrator never reads the full diff itself; it delegates to the `pr-reviewer` subagent (see `.opencode/agents.toml`).

## Steps

1. **Fetch and scope the diff**
   ```bash
   git fetch origin
   git diff --name-only origin/main...HEAD
   git diff origin/main...HEAD
   ```
   Identify the set of changed files and group them by subsystem (Core, AdminUI, AppView, Lexicons, etc.).

2. **Delegate to the `pr-reviewer` subagent**
   Spawn it with the diff range and the subsystem grouping as scoped context. The subagent loads only the files it needs; the Orchestrator keeps the diff *out* of its own context window.

3. **Spawn audit subagents in parallel where applicable**
   - Touched `Sources/Core/Storage/**` or crypto paths → `security-auditor`.
   - Touched threading/queue code → `concurrency-auditor`.
   - Touched `Lexicons/**` or XRPC handlers → `atproto-coverage-auditor`.
   - Touched `AdminUI/**` → `web-ui-auditor`.
   Launch them in a single Orchestrator message (parallel Task calls).

4. **Run quality gates**
   Execute [quality_gates.md](./quality_gates.md). Failures are blocking findings, not advisory notes.

5. **Collect and synthesize**
   Merge subagent findings into a single review with sections: **Blocking**, **Should-fix**, **Nits**. Each finding names `file:line` and the specific change requested.

6. **Post the review**
   - Local branch review: print to stdout or write to `reports/review-<branch>.md`.
   - GitHub PR: `gh pr review <PR> --comment --body-file <path>`.

## Exit Criteria
- Every changed file appears in at least one subagent's coverage.
- Quality-gate result is recorded in the review body.
- No subagent returned `in_progress`.
