# MST Sequential-Key Bug (Investigated — Not Reproducible)

## Summary

The MST (Merkle Search Tree) implementation in `MST.m` was suspected of losing
entries when keys are sequential or non-random (e.g., `poison0001`, `poison0002`).

## Investigation

A thorough stress test was written and run against the `addRecursive:` method:

| Key Pattern                 | Count | Insert | Verify | Delete Half | Verify Remain |
|-----------------------------|-------|--------|--------|-------------|---------------|
| `poison%04d`                | 100   | ✅     | ✅     | ✅          | ✅            |
| `key_%05d`                  | 100   | ✅     | ✅     | ✅          | ✅            |
| `test/data/record_%03d`     | 100   | ✅     | ✅     | ✅          | ✅            |
| `app.bsky.feed.post/seq%04d`| 100   | ✅     | ✅     | ✅          | ✅            |

All 4 patterns passed insertion, full-key verification, half-deletion, and
remaining-key verification with zero failures.

## Root Cause Analysis

The suspected bug was in `addRecursive:` — the hypothesis was that sequential
keys produce SHA-256 hashes sharing leading zero-bit patterns, causing tree-depth
collisions that lose entries during split/rebuild operations.

**This hypothesis is incorrect.** SHA-256 exhibits the avalanche effect: even
single-bit input changes produce completely different hashes. Sequential keys
produce uniformly distributed depths, identical to random TID keys.

A thorough code review of `addRecursive:` and `split:` found no edge case where
entries could be dropped. All code paths (CASE 1: `depth > node.level`, CASE 2:
key-exists update, CASE 3: `depth == node.level` insert, CASE 4: `depth < node.level`
recurse) preserve entry pointers through the split/rebuild/insert operations.

## Conclusion

- **Severity**: None — the bug does not exist.
- **Recommendation**: Close as not reproducible.
- **Tests**: `testSequentialKeysStress` in `MSTRebalancingTests.m` provides
  ongoing regression coverage for sequential key patterns.
