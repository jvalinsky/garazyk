---
name: xrpc-schema-sync
description: Compare implemented XRPC methods against lexicon schemas and detect missing endpoints or mismatched input/output shapes; use for schema sync, coverage checks, and regression audits.
---

# XRPC Schema Sync

Use this skill when validating XRPC coverage drift and registration quality.

## Quick start
1) Run the repo-native report flow (preferred):
```bash
node scripts/generate_xrpc_coverage_report.js --source-only --fail-on-duplicates
node scripts/generate_xrpc_next_steps.js
```
2) Review:
- `reports/xrpc_coverage.md`
- `reports/xrpc_coverage.json`
- `reports/xrpc_next_steps_plan.md`
- `reports/xrpc_issue_candidates.md`

## Workflow
- Use repo scope config (`scripts/xrpc_coverage_scope.txt`) to avoid out-of-scope noise.
- Treat `duplicate_registry_registrations_cross_scope` as actionable duplicate signal.
- Treat `duplicate_registry_registrations_cross_scope_expected` as expected overlap.
- For parser-level debugging, run `scripts/run_all.sh` in this skill directory (fallback mode).

## Script behavior
`./skills/xrpc-schema-sync/scripts/run_all.sh`:
- Detects repo-native generators and uses them first.
- Falls back to local parser scripts (`list_xrpc_methods.py`, `parse_lexicons.py`, `diff_methods.py`) if repo generators are unavailable.

## Usage example
```bash
# Preferred (from repo root)
node scripts/generate_xrpc_coverage_report.js --source-only --fail-on-duplicates
node scripts/generate_xrpc_next_steps.js

# Fallback parser flow
./skills/xrpc-schema-sync/scripts/run_all.sh . --output-dir /tmp/xrpc-audit
```

## References
- `references/lexicon_schema_notes.md`
- `references/xrpc_registry_layout.md`
- `references/known_exceptions.txt`
- `references/report_schema.md`
