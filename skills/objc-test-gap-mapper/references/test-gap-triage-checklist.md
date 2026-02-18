# Test Gap Triage Checklist

Use this checklist while reviewing `map_test_gaps.sh` output.

## Risk-first prioritization
- Prioritize auth, security, database, network, and parser modules.
- Prioritize files with recent bug history or frequent changes.
- Prioritize files with complex branching and error handling.

## Coverage depth checks
- Verify happy path and failure path coverage both exist.
- Verify boundary conditions and malformed input cases are covered.
- Verify concurrency and ordering-sensitive paths have deterministic tests.

## Action planning
- Add minimal high-value tests first (invariants and regressions).
- Add integration tests where unit seams are weak.
- Track uncovered file count trends over time.
