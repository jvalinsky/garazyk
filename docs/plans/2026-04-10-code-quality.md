---
title: "Phase 7: Code Quality & Maintenance Plan"
---

# Phase 7: Code Quality & Maintenance

> **Status:** Minor issues remaining
> **Priority:** P3 (Ongoing)
> **Generated:** 2026-04-10

## Executive Summary

The codebase has minimal technical debt. Only one TODO marker was found in source files. This plan covers fixing remaining issues and establishing ongoing maintenance practices.

---

## Current Issues

### TODO/FIXME Markers Found

| Location | Issue | Priority |
|----------|-------|----------|
| `Garazyk/Sources/App/Explore/Assets/static/style.css:84` | "TODO: this is not accessible" | Low |

**Note:** This is in Explore UI assets, not core PDS code.

### Fallback Behavior (Acceptable with Warnings)

| Location | Type | Notes |
|----------|------|-------|
| `OAuth2.m:479-517` | JWT signing key fallback | Logs warning, OK for dev/test |
| `PDSController.m:353-396` | JWT key fallback | Logs warning, OK for dev/test |
| `PDSApplication.m:279-315` | JWT key fallback | Logs warning, OK for dev/test |

These fallbacks are acceptable but should log warnings in production to alert operators.

---

## Tasks

### Task 7.1: Fix CSS Accessibility TODO

**Goal:** Address accessibility issue in Explore UI

**Files:**
- File: `Garazyk/Sources/App/Explore/Assets/static/style.css:84`

**Current code:**
```css
/* OLLIE: TODO -- this is not accessible */
```

**Steps:**
1. Read the CSS around line 84 to understand what element lacks accessibility
2. Fix the accessibility issue (add proper ARIA attributes, keyboard navigation, etc.)
3. Remove the TODO comment

**Common fixes:**
- Add `role` attribute where needed
- Add `aria-label` for icon-only buttons
- Ensure color contrast meets WCAG AA
- Add focus states for interactive elements
- Add skip links for keyboard navigation

---

### Task 7.2: Review Production Fallback Warnings

**Goal:** Ensure fallback behavior logs appropriate warnings in production

**Files:**
- `Garazyk/Sources/Auth/OAuth2.m:479-517`
- `Garazyk/Sources/App/PDSController.m:353-396`
- `Garazyk/Sources/App/PDSApplication.m:279-315`

**Steps:**
1. Verify each fallback logs at WARNING level (not DEBUG)
2. Ensure message clearly states what's wrong and how to fix
3. Add to production readiness checklist

**Expected log format:**
```
PDS_LOG_AUTH_WARN(@"Using in-memory JWT signing key fallback because key manager provisioning failed. 
    Please configure PDS_JWT_SIGNING_KEY_PATH in environment.");
```

---

### Task 7.3: Establish Ongoing Quality Gates

**Goal:** Prevent new TODOs from being introduced

**Steps:**
1. Add to pre-commit hook:
   ```bash
   # Check for TODO/FIXME in source files (exclude test files, docs)
   rg "TODO|FIXME" Garazyk/Sources --type objc | grep -v "^Garazyk/Sources/App/Explore/Assets"
   ```

2. Add to CI (optional):
   ```yaml
   - name: Check for TODO markers
     run: |
       rg "TODO|FIXME" Garazyk/Sources --type objc > todos.txt
       if [ -s todos.txt ]; then
         echo "TODO/FIXME found:"
         cat todos.txt
         exit 1
       fi
   ```

3. Document in AGENTS.md that new TODO markers require PR review

---

### Task 7.4: Run Full Test Suite

**Goal:** Verify no regressions from any changes

**Steps:**
```bash
# Full test suite
./build/tests/AllTests

# If tests are not built, build first
xcodebuild -scheme AllTests build
./build/tests/AllTests
```

**Expected:** 0 failures

---

### Task 7.5: Update Documentation

**Goal:** Keep compliance documentation current

**Steps:**
1. Re-run XRPC coverage report:
   ```bash
   node scripts/generate_xrpc_coverage_report.js --source-only
   node scripts/generate_xrpc_next_steps.js
   ```

2. Update compliance status in `docs/plans/README.md`

3. Add new plan files to index

---

## Verification Checklist

- [ ] CSS accessibility fix applied
- [ ] Fallback warnings verified in code
- [ ] Pre-commit hook updated (if applicable)
- [ ] Full test suite passes
- [ ] Documentation updated

---

## Dependencies

- `Garazyk/Sources/App/Explore/Assets/static/style.css`
- `Garazyk/Sources/Auth/OAuth2.m`
- `Garazyk/Sources/App/PDSController.m`
- `Garazyk/Sources/App/PDSApplication.m`

---

## Related Plans

- [Phase 1: OAuth 2.0/DPoP Compliance](2026-04-10-oauth-dpop-compliance.md)
- [Phase 5: Database Query Methods](2026-04-10-database-query-methods.md)
- [Production Readiness](production-readiness.md)

---

## Conclusion

Phase 7 represents ongoing maintenance rather than critical work. The codebase is in good shape with only minor issues to address.