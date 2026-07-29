# ADR 0031: Module Boundaries Are Enforced By a Link-Time Symbol Gate

**Status:** Accepted
**Date:** 2026-07-29

## Context

Workstream 08 found that the ten `ATProto*` static-library dependencies
declared in `CMakeLists.txt` are documentation, not enforcement:
`libATProtoCore.a` is declared to depend on nothing, but carries undefined
`_OBJC_CLASS_$_` references to classes defined in every layer declared above
it (Storage, Transport, Services). Static archives defer symbol resolution to
the final executable link, and every binary in the repository links the
whole archive set regardless of layering, so a class reference that violates
the declared graph has never once failed a build.

The existing `scripts/dev/check_module_boundaries.sh` (already a CI gate,
run three times in `.github/workflows/ci.yml`) checks a different thing:
source-level import statements and a small set of specific forbidden edges
(`Sync/` importing `App/`, `PLC/` importing App runtime types). It does not,
and structurally cannot, catch a class *reference* that survives without a
matching `#import`+link edge — the exact failure mode static-archive
deferral produces.

An initial pass at measuring the true leak surface, using `nm -u` on each
whole archive, undercounted badly: `nm` reports each `.o` member's own
symbol table, so a class used in one file of an archive and defined in
another file of the *same* archive shows as both undefined and defined in
the combined listing — an internal reference the final archive resolves on
its own, not a boundary violation. Correcting for this (undefined-minus-
defined within each archive, not naive `nm -u`) found the real surface is
far larger than initially estimated: 69 leaks across all ten modules, not
the handful first cited.

## Decision

1. **`scripts/check_module_boundaries.sh`** (new, distinct from the existing
   `scripts/dev/` one) computes, per `ATProto*` archive: the Objective-C
   classes it references but does not itself define (undefined-minus-defined
   within that archive, correcting for the internal-resolution artifact
   above), resolves each to whichever other `ATProto*` archive defines it (if
   any — Foundation/system/vendored classes are not ours to police and are
   dropped), and flags any resolution outside that archive's declared
   transitive `PUBLIC` dependency set (parsed directly from
   `CMakeLists.txt`, not hand-duplicated, so the check can't drift from the
   graph it's checking).
2. **`docs/module-boundary-baseline.txt`** records the 69 leaks
   present today. The script fails only on leaks *not* in this file — it is
   append-never in the growing direction. A genuinely new leak must be fixed
   in the same commit, or the baseline edited in that same commit so review
   sees the regression explicitly; it can never be introduced silently.
   The workstream 08 plan named this file's location as `docs/metadata/`;
   that whole directory is gitignored (generated artifacts like
   `docs/graph-data.json` live there), and git cannot re-include a file
   whose parent directory is itself excluded, so this baseline lives at
   `docs/module-boundary-baseline.txt` instead.
3. **Written for bash 3.2** (macOS's system default has no associative
   arrays) using per-module temp files instead, so it runs without requiring
   a newer bash on any contributor's machine or CI image.
4. Wired into `.github/workflows/ci.yml` as an additional step alongside the
   existing `scripts/dev/check_module_boundaries.sh` call — the two check
   different things and both stay.

## Consequences

- **This is a measurement gate, not a fix.** Landing it does not reduce the
  69 leaks; it stops the count from growing without review and gives later
  workstream 08 items (M2: make `ATProtoCore` standalone, M3: split
  `ATProtoTransport`, M4: resolve the remaining inversions) a concrete,
  shrinking number to work against instead of "review by inspection."
- **The baseline count (69) is real, not the workstream doc's earlier
  estimate.** That doc's original evidence ("six symbols" for
  `ATProtoCore`) undercounted for the reason in Context above; this ADR's
  count supersedes it. `ATProtoCore` alone carries roughly 30 of the 69.
- **CI cost.** The script requires a prior build (it reads `build/lib*.a`);
  it does not build anything itself. Runtime is a handful of `nm`/`comm`
  passes over already-built archives — sub-second in practice.
- **Ambiguous symbols are silently skipped, not flagged.** A class name
  defined in more than one of the ten archives (should not happen under
  correct layering, but the script doesn't assume it can't) is dropped from
  the ownership map rather than guessed at. If this ever hides a real leak,
  the fix is to make the map per-symbol-with-source-module instead of
  per-class-name, not to change the ratchet semantics.
- **Rollback.** Delete `scripts/check_module_boundaries.sh`, the
  `docs/module-boundary-baseline.txt` baseline, and the new CI
  step. Nothing else depends on this gate; `scripts/dev/check_module_boundaries.sh`
  and its existing CI wiring are untouched.
