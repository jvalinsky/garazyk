---
name: objc-gnustep-regression-audit
description: "Audit Objective-C code for GNUstep and Linux portability regressions, including macOS-only API usage, missing TARGET_OS_LINUX guards, and compat-layer bypasses. Use when reviewing cross-platform changes or Linux build breakages."
---

# Objective-C GNUstep Regression Audit

Use this skill to catch macOS-only assumptions before they break Linux/GNUstep builds.

## Quick start
1. Run:
```bash
./skills/objc-gnustep-regression-audit/scripts/scan_gnustep_regressions.sh . /tmp/objc-gnustep-regression-audit
```
2. Read `/tmp/objc-gnustep-regression-audit/summary.md`.
3. Validate candidates with `references/gnustep-compat-checklist.md`.

## Workflow
1. Find platform-sensitive imports and APIs.
2. Check for `TARGET_OS_LINUX` guards where needed.
3. Verify compat-layer headers are used consistently.
4. Confirm fallback behavior exists for Linux runtime differences.

## Triage priorities
- P0: macOS-only API in runtime path without guard/fallback.
- P1: missing compile guard causing Linux build failure.
- P2: behavioral mismatch between macOS and GNUstep path.
- P3: low-confidence portability smell.

## Fix patterns
- Route sensitive APIs through existing compat wrappers.
- Add compile-time guards around platform-specific code.
- Keep Linux and macOS code paths behaviorally aligned.
- Add regression tests for Linux-specific flows.

## Resources
- Script: `scripts/scan_gnustep_regressions.sh`
- Reference: `references/gnustep-compat-checklist.md`
