# Meta: PDS parity backlog + scope policy

## Snapshot (as of 2026-02-12)

These numbers were generated from the repository state on 2026-02-12 using repo-native source parsing.

### Method/lexicon diff

- Code-registered XRPC methods: **97**
  - Source: `scripts/generate_xrpc_coverage_report.js` (source-parsed mode)
  - Registry file: `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - Mapping file: `ATProtoPDS/Sources/Network/XrpcHandler.m`
- Lexicon-defined XRPC methods (from `ATProtoPDS/Resources/lexicons/**.json`): **321**
- In-scope lexicon methods (`com.atproto.*` via scope file): **86**
- Missing in code (in scope): **12**
- Missing in code (out of scope): **223**
- Missing in lexicons (in scope): **10**
- Unknown registry entries: **0** (string-based registrations are now parsed)

Repro commands:

```bash
node scripts/generate_xrpc_coverage_report.js --source-only
node scripts/generate_xrpc_next_steps.js
```

Artifacts:
- `reports/xrpc_coverage.json`
- `reports/xrpc_coverage.md`
- `reports/xrpc_next_steps_plan.md`
- `reports/xrpc_issue_candidates.md`

### Stub scan (placeholder markers)

- `not_implemented`: 0
- `todo_fixme`: 0
- `stub_markers`: 0

This does **not** mean there is no missing functionality; it only means there are no TODO/FIXME/not-implemented markers per the stub scan patterns.

## Why this meta issue exists

The raw lexicon bundle includes many namespaces that are *not* required for a functional PDS (or are intentionally out-of-scope for this repo). Without an explicit scope policy, any automated “coverage” report will permanently show a giant backlog, making it hard to:

- track what we actually intend to ship,
- detect regressions in **in-scope** endpoints, and
- make work-item sized issues for missing functionality.

## What must be filed (in-scope backlog)

### com.atproto.* missing in code (12)

From `reports/xrpc_coverage.json` (`missing_in_code` list; scope `com.atproto.*`):

- `com.atproto.admin.searchAccounts`
- `com.atproto.admin.sendEmail`
- `com.atproto.admin.updateAccountEmail`
- `com.atproto.admin.updateAccountHandle`
- `com.atproto.admin.updateAccountPassword`
- `com.atproto.admin.updateAccountSigningKey`
- `com.atproto.temp.addReservedHandle`
- `com.atproto.temp.checkHandleAvailability`
- `com.atproto.temp.checkSignupQueue`
- `com.atproto.temp.dereferenceScope`
- `com.atproto.temp.fetchLabels`
- `com.atproto.temp.requestPhoneVerification`

### Code-registered methods missing in lexicons (10)

From `reports/xrpc_coverage.json` (`missing_in_lexicons` list; scope `com.atproto.*`):

- `com.atproto.admin.getAccountTakedown`
- `com.atproto.admin.moderateAccount`
- `com.atproto.admin.moderateRecord`
- `com.atproto.admin.takeDownAccount`
- `com.atproto.label.createLabel`
- `com.atproto.label.getLabels`
- `com.atproto.repo.deleteBlob`
- `com.atproto.repo.getBlob`
- `com.atproto.repo.updateRecord`
- `com.atproto.server.getAccount`

## Scope policy (decision needed)

The diff report contains large numbers of missing endpoints in non-`com.atproto.*` namespaces (e.g. `app.bsky.*`, `chat.bsky.*`, `tools.ozone.*`, etc). We need a written scope decision so:

- We don’t treat non-PDS namespaces as “missing” forever.
- The coverage report highlights only what we intend to ship.

Proposed policy (adjust as needed):

- **In-scope**: `com.atproto.*` needed for a functional PDS + any minimal `app.bsky.*` endpoints we explicitly choose to support.
- **Explicitly out-of-scope** (for now): `tools.ozone.*`, `chat.bsky.*`, `place.stream.*`, `social.grain.*`, `com.shinolabs.pinksea.*`, etc.
- For out-of-scope namespaces:
  - Either add ignore patterns to the diff tooling OR track them under a single “Out-of-scope namespaces” issue.

## Recommended priority order (so progress is measurable)

P0 (unblocks accurate progress tracking):
- Tooling improvements to remove `unknown` registrations and add scope filtering.

P0 (core PDS/admin parity):
- Remaining `com.atproto.admin.*` endpoints needed for moderation/admin parity.

P1 (developer ergonomics / ecosystem compatibility):
- `com.atproto.lexicon.resolveLexicon`.
- Decide/implement/de-scope `com.atproto.temp.*`.

P1 (cleanup / long-term maintainability):
- Reconcile code-registered endpoints missing lexicons (remove/rename/add lexicon).

## Suggested labels (for GitHub)

- `area:admin`
- `area:tooling`
- `area:lexicon`
- `area:linux`
- `prio:p0` / `prio:p1` / `prio:p2`

## Subtasks (this meta issue)

- [x] Confirm scope policy (which namespaces are “supported here”).
- [ ] Decide how vendor lexicons are treated in reports:
  - include only `ATProtoPDS/Resources/lexicons/**`, or
  - also include `lexicons/**` (e.g. `lexicons/whitewind/**`).
- [x] Land tooling support for `registerMethod:@"<nsid>"` so diffs have no `unknown`.
- [x] Add repo-local scope config for schema-sync/coverage (default include `com.atproto.*`).
- [x] Re-run diff report with scope config and attach updated snapshot numbers.
- [x] File/track the concrete issues that come out of this scope decision (admin/temp/lexicon/tooling/spec-alignment).
- [ ] (Optional) Update `tasks/project-tasks.md` to reference the new issues and remove duplicated text.

## Exit criteria (for this meta issue)

- [ ] Confirm scope (which namespaces are intentionally supported here).
- [ ] File one issue per **in-scope** missing endpoint group (or per endpoint).
- [ ] File one reconciliation issue for **code methods with no lexicon** (rename/remove/add vendor lexicon).
- [ ] File one tooling issue to parse `registerMethod:@"<nsid>"` and remove `unknown` noise.
- [ ] Update `/Users/jack/Software/objpds/tasks/project-tasks.md` (optional) to reference the new issues.
