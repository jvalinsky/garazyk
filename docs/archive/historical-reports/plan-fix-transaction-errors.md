# Plan: Fix "cannot commit – no transaction is active" Errors

## Summary of Findings

| Area | Finding | Source |
|------|---------|--------|
| `ServiceDatabases.persistEvent:` | Delegates to `sequencerPool transactWithDid:block:` → `ActorStore.transactWithBlock:` | explore agent |
| `ActorStore.m:314-393` | Already uses `sqlite3_get_autocommit()` + SAVEPOINT for nesting — **correct** | explore + web search |
| `PDSDatabase.m:1937-1971` | `beginTransaction` / `commitTransaction` do **NOT** check autocommit — **bug** | web search agent |
| `PDSDatabase.m:1973-2016` | `transactWithBlock:error:` has no nested transaction protection | web search agent |
| `SubscribeReposHandler.m` | All 5 `persistEvent` call sites use `eventQueue` (serial) but no transaction context — **OK** because `ServiceDatabases` manages it | explore agent |
| Test setup | Uses real SQLite in temp dirs; `PDSController` creates databases; no transaction issues in test setup itself | test explore agent |

## Root Cause Hypothesis

The "cannot commit — no transaction is active" error is **not** from `ActorStore` (which is correct). It likely comes from:

1. **`PDSDatabase.m`** — used elsewhere in the test path (perhaps by `PDSController` or `PDSApplication` during init), where `commitTransaction` is called without a prior `BEGIN`, OR
2. **A shared database connection** that gets left in autocommit mode, and something tries to explicitly `COMMIT`, OR
3. **The `transactWithBlock:` in `ActorStore` has an edge case** — e.g., `sqlite3_get_autocommit()` returns wrong value for a freshly-opened connection, or the `RELEASE sp_transact` failure path (line ~368) doesn't clean up properly.

---

## Phase 1: Identify Exact Error Source

### Task 1.1 — Add logging to capture where "cannot commit" originates
- Edit `ActorStore.m` `transactWithBlock:error:` to log the backtrace when `COMMIT`/`RELEASE` fails
- Edit `PDSDatabase.m` `commitTransactionWithError:` to do the same
- Run tests, capture which path triggers the error

### Task 1.2 — Search for all `COMMIT`, `ROLLBACK`, `BEGIN` exec calls in the codebase
- Use grep to find every `sqlite3_exec` with transaction keywords
- Identify any direct SQLite transaction calls outside `ActorStore` and `PDSDatabase`

---

## Phase 2: Fix `PDSDatabase.m` Transaction Methods

### Task 2.1 — Add autocommit check to `beginTransactionWithError:` and `commitTransactionWithError:`
```objc
// In PDSDatabase.m - (BOOL)commitTransactionWithError:(NSError **)error
int autocommit = sqlite3_get_autocommit(_db);
if (autocommit) {
    // Already in autocommit mode — no active transaction, skip or log
    return YES; // or handle as appropriate
}
```

### Task 2.2 — Add nested transaction support (SAVEPOINT) to `PDSDatabase.m` matching `ActorStore` pattern
- Use `sqlite3_get_autocommit()` to decide BEGIN vs SAVEPOINT
- Match the pattern already used in `ActorStore.m:314-393`

### Task 2.3 — Fix `transactWithBlock:error:` in `PDSDatabase.m` to handle nesting
- Wrap in autocommit check + savepoint logic

---

## Phase 3: Fix Potential `ActorStore.m` Edge Cases

### Task 3.1 — Fix the incomplete cleanup in the `RELEASE sp_transact` failure path (line ~368)
- After `ROLLBACK TO sp_transact`, also issue `RELEASE sp_transact` to clean up the savepoint

### Task 3.2 — Add a guard at the start of `transactWithBlock:error:` to ensure the db is open and autocommit state is sensible

---

## Phase 4: Fix Test Infrastructure

### Task 4.1 — Ensure `PDSController` init doesn't leave shared DB in a bad state
- Check if `PDSApplication` init triggers any transactions that might not be properly committed

### Task 4.2 — Add `resetSharedDispatcher` pattern to other singletons if needed
- Check `PDSMetrics`, `ATProtoLexiconRegistry` for similar state leakage

### Task 4.3 — Add explicit teardown in `SubscribeReposHandlerTests.m` to clean up event queues
- Ensure `eventQueue` is drained before tearDown

---

## Phase 5: Verification

### Task 5.1 — Build
```
xcodegen generate && xcodebuild -scheme AllTests build
```

### Task 5.2 — Run tests
```
xcodebuild test -scheme AllTests
```

### Task 5.3 — Verify "cannot commit" errors are gone from output

### Task 5.4 — Update `deciduous` graph with outcomes

---

## Subagent Delegation Plan

| Task | Subagent | Skill |
|------|----------|-------|
| 1.1 + 1.2 (identify error source) | `explore` | `objc-architecture-audit` |
| 2.1–2.3 (fix PDSDatabase.m) | `general` + direct edits | `better-code-objc` |
| 3.1–3.2 (fix ActorStore.m) | `general` + direct edits | `better-code-objc` |
| 4.1–4.3 (test infra) | `explore` then edits | `objc-architecture-audit` |
| 5.1–5.4 (verify + graph) | `general` + `deciduous` | — |

---

## Relevant Files

- `/Users/jack/Software/garazyk/Garazyk/Sources/Database/PDSDatabase.m` — lines 1937–2016 (transaction methods)
- `/Users/jack/Software/garazyk/Garazyk/Sources/Database/ActorStore/ActorStore.m` — lines 314–393 (transactWithBlock)
- `/Users/jack/Software/garazyk/Garazyk/Sources/Database/ServiceDatabases.m` — lines 727–742 (persistEvent)
- `/Users/jack/Software/garazyk/Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m` — persistEvent call sites
- `/Users/jack/Software/garazyk/Garazyk/Tests/Sync/SubscribeReposHandlerTests.m` — test setup/teardown
- `/Users/jack/Software/garazyk/docs/graph-data.json` — deciduous decision graph
