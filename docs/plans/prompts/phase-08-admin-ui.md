---
phase: 8
title: Admin UI accessibility and structural cleanup
status: in-progress
agent: worker
depends_on: [1]
last_updated: 2026-07-19
---

## Progress

Started 2026-07-19.

**Slice 1 complete (2026-07-19): U4 dashboard + part of U5.** Document
language (`lang="en"`), `Layout`'s `hasOwnH1` so every route has exactly
one `h1`, mobile-drawer focus trap/restore (`islands/MobileNav.tsx`), named
`RunHistory` table (`<caption>`, `scope="col"` headers), status not
color-only (`StatusBar` health dot paired with sr-only text; `RunHistory`/
`ScenarioCard` pass/fail/skip rendered as text, not bare glyphs/color), and
`prefers-reduced-motion` coverage (U5) in `static/app.css`. Automated
assertions added to `browser_smoke_test.ts` (document lang, h1 presence,
table semantics, non-color status, reduced-motion, mobile-drawer focus
trap/restore) — all green except the drawer trap/restore check, which the
test detects and skips with a `[WARN]` because of a pre-existing,
unrelated bug: `islands/SessionPlayer.tsx`'s `import("asciinema-player")`
breaks Fresh's dev esbuild bundle for every island (see workstream 04 U4
for detail). Manual verification of the trap/restore logic was done by
source review of `MobileNav.tsx` in lieu of a live browser pass, pending
that bug's fix.

**Slice 2 complete (2026-07-19): U4 Admin UI (ObjC AdminUIServer).**
`Garazyk/Sources/AdminUIServer/UIServerRuntime.m`: page heading order
fixed (login page `<h2>`→`<h1>`; shell header `<div>`→`<h1>`; all 48
`admin-section-title` `<h3>`→`<h2>`; the one nested MST-node `<h4>`→`<h3>`
to stay one level below); all 23 `<label>` elements (21 bare + 2 already
correct) bound via `for`/`id`, including the 12 originally missed in the
per-service Connections form (caught by a new automated check — see
below); the 12-tab nav gets `role="tablist"`/`role="tab"`/
`role="tabpanel"`, `aria-selected`, `aria-controls`/`aria-labelledby`, and
roving `tabindex`, with `ArrowLeft/Right/Up/Down/Home/End` keyboard
navigation added to `Assets/js/admin-ui.js` per the WAI-ARIA APG tabs
pattern; ~19 status/error containers (`*-result(s)` divs, the connection
test-result span, the login error `<p>`) get `aria-live="polite"` or
`role="alert"`. `Garazyk/Sources/Auth/Assets/authorize.html`: focus now
moves to the consent step's heading on both the password and passkey
sign-in paths (previously stranded focus on the now-hidden sign-in
button); `#auth-error` gets `role="alert"`.

`scripts/admin_ui_browser_smoke_test.ts` gets a new Area 5 asserting all
of the above against the real built `garazyk-ui` binary (heading count/
order, tablist roles, `aria-selected` + roving `tabindex` after
`ArrowRight`, unbound-label count), and the pre-existing OAuth
consent-focus check is promoted from a soft `warn()` to a hard `fail()`
now that it's fixed. Full run green (`✅ Admin UI browser smoke
completed`), including a real catch: the first pass at label binding
missed the 12 per-service Connections-form labels (they use
`class="form-label"`, not a bare `<label>`) — the new Area 5 check caught
it before commit.

`cmake --build build --target AllTests --parallel 4` succeeds cleanly.
`./build/tests/AllTests --gated=run` surfaces 12 failing suites (~68
failures), none in files this slice touches — see workstream 01 S5's
"Regression discovered 2026-07-19" note for the full breakdown and root
causes (a DID-format/fixture mismatch predating this session, plus a
separate `MSTPreorderTests` bug from phase 7's Sync 1.1 work). Confirmed
unrelated by code-area review and, for the deterministic `MSTPreorderTests`
failure, three isolated re-runs.

Remaining: the rest of U5 (measured contrast, 200% zoom/reflow, touch
targets, dashboard keyboard order at narrow widths), and U6 (gated behind
U4 landing in full — U4 now lands with this slice).

**Slice 3 in progress (2026-07-22): U5 reduced motion.** Both independently
served Admin UI stylesheets, `system.css` and `utilities.css`, now honor
`prefers-reduced-motion: reduce` by suppressing animation and transition
durations while retaining the state changes. `scripts/admin-ui-build/
reduced_motion_test.ts` verifies the rule and required declarations in both
files. The remaining U5 work is measured contrast, 200% zoom/reflow, focus
visibility, touch targets, and dashboard keyboard order at narrow widths.

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
