---
name: atproto-coverage-audit
description: "Audit ATProto/XRPC endpoint coverage and schema synchronization. Detects stubbed methods, missing endpoints, and mismatched input/output shapes compared to lexicons."
---

# ATProto Coverage Audit

This master skill consolidates endpoint stub detection and schema synchronization for ATProto/XRPC.

## Quick Start

1. **Run the repo-native coverage checks** (Preferred):
   ```bash
   ./scripts/stub_find.sh .
   node scripts/generate_xrpc_coverage_report.js --source-only --fail-on-duplicates
   node scripts/generate_xrpc_next_steps.js
   ```
2. **Review the generated reports**:
   - `reports/xrpc_coverage.md`
   - `reports/xrpc_next_steps_plan.md`

## Audit Domains

### 1. Endpoint Stub Detection
- **Goal**: Find `not_implemented`, `TODO`, and placeholder logic in handlers.
- **Tools**: `scripts/stub_find.sh` and `atproto-coverage-audit/scripts/find_stubs.sh`.

### 2. Schema Synchronization
- **Goal**: Compare implemented XRPC methods against lexicon schemas.
- **Tools**: `node scripts/generate_xrpc_coverage_report.js`.

### 3. Coverage Analysis
- **Goal**: Correlate stubs with registrations and identify priority gaps.
- **Tools**: `node scripts/generate_xrpc_next_steps.js`.

## Resources
- **Scripts**: Combined in `atproto-coverage-audit/scripts/`
- **References**: Consolidated in `atproto-coverage-audit/references/`
