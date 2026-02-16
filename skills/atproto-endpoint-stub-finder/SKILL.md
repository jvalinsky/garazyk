---
name: atproto-endpoint-stub-finder
description: Find stubbed or not_implemented ATProto/XRPC endpoints and placeholder logic in handlers/controllers; use when auditing endpoint coverage, mapping stubs to lexicons, or generating follow-up issues.
---

# ATProto Endpoint Stub Finder

Use this skill to detect placeholder logic and map it against registered XRPC methods.

## Quick start
1) Run repo-native stub + coverage checks (preferred):
```bash
./scripts/stub_find.sh .
node scripts/generate_xrpc_coverage_report.js --source-only --fail-on-duplicates
node scripts/generate_xrpc_next_steps.js
```
2) For parser-level fallback, run this skill’s `scripts/run_all.sh`.

## Workflow
- Collect stub markers (`not_implemented`, `TODO/FIXME`, placeholder/stub markers).
- Map endpoint registrations from `XrpcMethodRegistry.m`, including:
  - typed registrations (e.g. `registerComAtproto...`)
  - string registrations (`registerMethod:@"com.atproto..."`).
- Correlate stub hits with in-scope XRPC reports and produce actionable follow-up issues.

## Outputs
- `stubs.json` (marker scan)
- `methods.json` (endpoint mapping)
- optional repo-native coverage artifacts when available

## Usage example
```bash
# Preferred
./scripts/stub_find.sh .
node scripts/generate_xrpc_coverage_report.js --source-only --fail-on-duplicates

# Skill fallback flow
/Users/jack/.codex/skills/atproto-endpoint-stub-finder/scripts/run_all.sh . --output-dir /tmp/stub-audit
```

## References
- `references/endpoint_map.md`
- `references/lexicon_paths.md`
- `references/known_exceptions.txt`
- `references/report_schema.md`
