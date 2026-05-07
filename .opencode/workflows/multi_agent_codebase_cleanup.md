# Multi-Agent Codebase Investigation & Cleanup Template

## Context
You are the **Lead Orchestrator** (manager mode only). Your job is decomposition, delegation, synthesis, and verification. You do NOT edit code directly.

## Research-Backed Coordination Principles

### What Worked ✅
1. **Git Worktrees** — Critical infrastructure. Each agent gets its own worktree: `git worktree add ../cleanup-agentN-scope -b cleanup/agentN-scope`
2. **File-Ownership Model** — "One file, one owner" rule prevents conflicts. Partition by subsystem, never assign same file to two agents.
3. **5-Agent Ceiling** — Research shows 3-5 concurrent agents is the practical limit before review bottleneck eliminates productivity gains.
4. **Phase-Based Approach** — Research → Synthesis → Execution → Review → Integration. Never skip synthesis.
5. **Deciduous Graph** — Track `goal → options → decision → actions → outcomes` for accountability.
6. **Independent Review** — Separate review agents (not the exec agents) verify work. Different reviewers for different subsystems.
7. **Atomic Commits** — <500 lines per commit, one fix type per commit (`fix(P0):`, `fix(P1):`, `chore:`).

### What Didn't Work ❌
1. **Agent Context Loss** — Exec-1 claimed fixes but didn't persist them to branch. **Fix**: Always verify branch has commits with `git log --oneline -10`.
2. **Parallel Git Merges** — Causes `.git/index.lock` conflicts. **Fix**: Serialize merges: `merge exec-1 && merge exec-2 && merge exec-3...`
3. **Pre-existing Build Failures** — secp256k1 submodule not initialized caused false alarms. **Fix**: Check `git submodule status` before builds.
4. **Over-Delegating Comprehension** — Don't delegate understanding, delegate action. Synthesize findings yourself.

---

## Phase 1: Research & Discovery (Parallel)

Dispatch 4-5 research agents with **lean-context delegation** (they read findings into deciduous, you don't feed them details):

```
Task: research-N
Prompt: |
  Use skill tool to load "[SKILL_NAME]" skill. 
  Follow skill instructions to scan /path/to/codebase for [SPECIFIC_ISSUE].
  Write findings to deciduous graph as:
    - goal node: "Audit [subsystem] for [issue]"
    - decision node: "Found [count] issues"
    - action nodes: per finding
  Return structured report with file paths, line numbers, severity (P0-P3).
Subagent: explore
```

**Recommended Research Skills** (adapt to your codebase):
- `slop-detector` — LLM-generated patterns, dead code
- `objc-architecture-audit` — XRPC contracts, service boundaries
- `objc-concurrency-audit` — Threading, queues, locks
- `objc-security-audit` — SQL injection, secrets, crypto
- `rewriting-code-comments` — LLM-isms in comments

---

## Phase 2: Synthesis (Lead Only)

Read all research agent findings from deciduous graph. Create prioritized cleanup plan:

```
P0 — Crash/security risks (fix first)
P1 — Architecture/concurrency violations
P2 — Code quality/slop patterns
P3 — Style/low-confidence warnings
```

**Critical**: Define verification criteria for each task BEFORE delegating (contract-first decomposition from Google DeepMind framework).

---

## Phase 3: Execution (Parallel, File-Ownership Model)

### Create Worktrees
```bash
git worktree add ../cleanup-exec1-auth -b cleanup/exec1-auth
git worktree add ../cleanup-exec2-network -b cleanup/exec2-network
# ... max 5 worktrees
```

### Dispatch Exec Agents
```
Task: exec-N
Prompt: |
  You are exec-N working in /path/to/cleanup-execN-scope
  Branch: cleanup/execN-scope
  
  ## P0 Fixes (Do First)
  1. [FILE:LINE] — [ISSUE]
     Fix: [SPECIFIC_ACTION]
  2. [FILE:LINE] — [ISSUE]
     Fix: [SPECIFIC_ACTION]
  
  ## P1 Fixes
  ...
  
  ## Quality Gates (Run After Each Subsystem)
  ```bash
  cd /path/to/cleanup-execN-scope
  # lint
  # typecheck
  # build — if fails, check git submodule status first
  # tests
  ```
  
  ## Commit Strategy
  - Atomic commits per fix type: `fix(P0): [description]`
  - Keep diffs under 500 lines per commit
  - Verify commits with `git log --oneline -10`
  
  Return: concise summary of all changes made + list of committed SHAs.
Subagent: general
```

**Partitioning by Subsystem** (example from our run):
| Agent | Subsystems | P0 Count |
|-------|------------|----------|
| exec-1 | `Auth/`, `Core/`, `Identity/` | 13 |
| exec-2 | `Network/`, `Sync/`, `Repository/` | 14 |
| exec-3 | `Database/`, `Services/`, `Blob/` | 10 |

---

## Phase 4: Independent Review (Parallel)

**Key**: Different agents than exec agents. They verify work, not re-do it.

```
Task: review-N
Prompt: |
  You are review-N. Verify cleanup work done by exec-N and exec-M.
  
  ## Your Tasks
  1. Check branch: `cd /path/to/cleanup-execN && git log --oneline -10 && git diff main...cleanup-execN --stat`
  2. Verify each fix was applied (check specific line numbers)
  3. Run quality gates
  4. Check for regressions (new deps, large diffs, missing P0 fixes)
  
  ## Return
  - List of verified fixes
  - Any issues found
  - Recommendation: APPROVE or REQUEST CHANGES
Subagent: general
```

Also dispatch cross-cutting reviewer:
```
Task: review-crosscut
Prompt: |
  Run atproto-coverage-audit skill for XRPC contract verification.
  Check deciduous graph: `deciduous graph`, `deciduous opencode status`
  Verify: no new deps, commit style, SQL injection fixes consistent, PDS_LOG_* used
Subagent: general
```

---

## Phase 5: Integration (Lead Only, Serialized)

**Critical**: Never merge parallel. Git lock conflicts will occur.

```bash
# Remove any stale locks
rm -f /path/to/repo/.git/index.lock

# Serialize merges
cd /path/to/main
git checkout main
git merge cleanup/exec1-auth --no-edit
git merge cleanup/exec2-network --no-edit  
git merge cleanup/exec3-database --no-edit
# ... one at a time

# Clean up
git worktree remove /path/to/cleanup-exec1-auth
git branch -d cleanup/exec1-auth
# ... remove all worktrees and branches

# Push
git push origin main
```

---

## Quality Gates (Per Agent)

1. **lint** — `codex --strict` or project linter
2. **typecheck** — build system check
3. **build** — `xcodebuild` or `cmake && make` (check submodules first!)
4. **tests** — `xcodebuild test` or `ctest`
5. **no new deps** — verify project.yml/CMakeLists.txt unchanged
6. **diff < 500 lines/commit** — atomic commits

---

## Deciduous Graph Updates (Continuous)

After each phase, update graph:
```bash
deciduous add goal "[PHASE] title" -c 90 --prompt-stdin << 'EOF'
[User message or summary]
EOF

deciduous add decision "Decision title" --prompt-stdin << 'EOF'
[Decision details]
EOF

deciduous add action "Action taken" --prompt-stdin << 'EOF'
[What was done]
EOF

deciduous add outcome "Result" --prompt-stdin << 'EOF'
[Outcome summary with commit SHAs]
EOF
```

---

## Red Flags to Watch For

1. **Agent claims fixes but no commits** — Always verify with `git log --oneline -10`
2. **Git lock conflicts** — Serialize merges, remove `.git/index.lock`
3. **Build failures** — Check `git submodule status`, may be pre-existing
4. **Undefined variables** — Review-3 caught `validatedDIDs` bug in our run
5. **Overlapping file ownership** — Breaks "one file, one owner" rule

---

## Post-Cleanup

```bash
# Generate final report
deciduous opencode status
deciduous graph

# Verify XRPC contracts intact
# Run atproto-scenario-testing for end-to-end validation
```

---

**Remember**: "Parallelism is your superpower, but only when tasks are truly independent" (from Claude Code coordinator mode research).
