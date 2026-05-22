# MST Sequential-Key Bug

## Summary

The MST (Merkle Search Tree) implementation in `MST.m` loses entries when keys are
sequential or non-random (e.g., `poison0001`, `poison0002`, etc.). The bug does not
manifest with random TID keys, which is the only key pattern used in production.

## Root Cause

The bug is in `addRecursive:` — when multiple keys hash to similar depths, the tree
restructuring logic in the `depth > node.level` branch and the `depth == node.level`
branch has edge cases where entries can be lost during split/rebuild operations.

Specifically, when keys have sequential prefixes, their SHA-256 hashes tend to share
leading zero-bit patterns, causing them to land at identical tree depths. The MST's
split logic (`split:left:right:`) and subsequent rebuild don't always preserve all
entries when multiple keys compete for the same structural position.

## Impact

- **Production**: None. ATProto uses random TIDs (base32-encoded 13-char timestamps),
  which produce uniformly distributed SHA-256 hashes. The existing
  `testLargeScaleRebalancing` test (1000 random TIDs) passes consistently.
- **Testing**: Tests that use hardcoded/sequential keys (e.g., `poison%04d` or
  `a00001`/`b00001`) will fail when verifying `allEntries.count` or individual `get:`.

## Status

- **Severity**: Low (no production impact)
- **Fix**: Would require auditing the `addRecursive:` split/rebalance paths for
  edge cases where entries can be dropped. Not a priority since random TIDs are
  the only key source in real ATProto usage.
- **Workaround**: Generate random TIDs for any MST test that needs to verify
  entry count or roundtrip integrity.
