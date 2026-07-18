---
phase: 8
title: Admin UI accessibility and structural cleanup
status: pending
agent: worker
depends_on: [1]
---

# Phase 8: Admin UI accessibility and structural cleanup

## Mission

Complete workstream 04's remaining items: WCAG 2.2 accessibility for Admin
UI and the scenario dashboard (U4), visual conformance (U5), and the
structural cleanup (U6) that is explicitly gated behind U1-U4. Reuses the
browser-smoke infrastructure from phase 1.

## Read first

- `docs/plans/workstreams/04-web-and-admin-ui.md` (U4-U6 authoritative;
  U1-U3 first slices are complete — do not redo them)
- Phase 1's browser smoke and its findings (accessibility evidence was
  explicitly deferred to this phase):
  `scripts/admin_ui_browser_smoke_test.ts` and
  `scripts/scenario-dashboard/browser_smoke_test.ts`, both passing as of
  2026-07-17. The Admin smoke recorded two leads: an intermittent PDS DPoP
  verification warning (workstream 01 follow-up) and the consent-step
  focus-move gap (U4 owns it).
- https://www.w3.org/TR/WCAG22/

## Scope

1. **U4 Admin UI**: page `h1` + heading order; labels bound to controls;
   tab role/state/keyboard behavior; live regions for status and errors;
   focus moves on OAuth sign-in → consent.
2. **U4 dashboard**: document language + `h1`; focus trap/restore in the
   mobile drawer; named data tables; status not color-only; keyboard order
   at narrow widths and zoom.
3. **U5**: measure semantic foreground contrast (don't trust the token
   claim); split foreground vs decorative tokens where needed;
   `prefers-reduced-motion` coverage; 200% zoom, reflow, focus visibility,
   touch targets.
4. **U6 (only after U4 lands)**: split `UIServerRuntime.m` into route
   registration / renderers / static browser code; centralize
   loading/empty/error/success rendering with no unsafe `innerHTML`; one
   generated CSS bundle with a drift test; dashboard state classes replace
   inline JSX styles; hostile-ANSI log rendering E2E with `ansi_up`
   escaping locked. Rewrite the Admin architecture reference against
   AdminUIServer.

## Constraints

- Keep endpoint contracts stable while tabs migrate; no rollback may
  reintroduce code-valued attributes (workstream 04 invariant).
- Browser automation plus a short manual keyboard pass per U4.

## Acceptance gate

- Automated a11y checks green; manual keyboard pass documented.
- CSP smoke still green after every structural slice.
- CSS drift test in CI; global gates pass.

## On completion

Update workstream 04, mega-plan Phase 4 item 4; set `status: complete`
here.
