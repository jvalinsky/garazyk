# GNUstep Compatibility Checklist

Use this checklist while validating candidates from `scan_gnustep_regressions.sh`.

## Compile-time compatibility
- Verify platform-sensitive APIs are guarded with Linux/macOS conditions.
- Verify imports resolve to compat headers on Linux builds.
- Verify no macOS-only type leaks into Linux-only structs or interfaces.

## Runtime compatibility
- Verify Linux fallback behavior exists where system APIs differ.
- Verify error handling semantics are equivalent across platforms.
- Verify threading and networking assumptions hold on GNUstep.

## Regression safety
- Add Linux-targeted unit/integration tests for touched modules.
- Add explicit guard tests for known portability hotspots.
- Keep compat wrappers minimal and documented.
