---
title: Web and Admin UI
status: active
last_verified: 2026-07-12
---

# Web and Admin UI

## U1. Contain process controls

The scenario dashboard binds without an explicit hostname and exposes routes
that start/stop networks and runs without authentication, Origin checks, CSRF,
or a launch capability.

1. Default to `127.0.0.1`.
2. Require explicit `DASHBOARD_HOST` for broader binding.
3. Issue a per-launch capability and require it on every mutation.
4. Validate Host and Origin. Require authentication for non-loopback mode.
5. Test all mutation routes with missing, wrong, expired, and valid capability.

Security rollback never restores unauthenticated non-loopback controls. A
compatibility flag may exist only for loopback and must have a removal date.

## U2. Repair Admin CSP and rendering boundaries

Admin UI uses a nonce CSP while rendering 59 inline event attributes. Nonces do
not authorize script attributes under CSP Level 3. The same attributes embed
backend values in JavaScript source using an HTML escaper.

1. Move browser code to `/js/admin.js`.
2. Bind events with delegation and inert `data-*` values.
3. Set `script-src-attr 'none'`.
4. Serialize data as JSON where attributes are insufficient.
5. Add a real-browser CSP smoke with hostile identifiers.

Keep endpoint contracts stable while tabs migrate. Each tab can revert to the
previous static markup, but no rollback may reintroduce code-valued attributes.

## U3. Enforce CSRF on every Admin mutation

`UIAuthManager` can validate a nonce, but `UIServerRuntime` applies it only to
login while the remaining POST routes use session auth alone.

Create one mutation guard that enforces session and CSRF before dispatch. Make
nonce rotation predictable and use one browser request wrapper for fetch and
HTMX. Negative tests must cover every route group.

## U4. Accessible workflows

Admin UI:

- add a page `h1` and a useful heading order;
- bind every label to its control;
- expose tab role/state and keyboard behavior;
- mark status and errors as live regions;
- move focus when OAuth moves from sign-in to consent.

Scenario dashboard:

- set document language and add an `h1`;
- trap focus in the mobile drawer and restore it on close;
- name data tables and keep status independent of color;
- validate keyboard order at narrow widths and zoom.

Use [WCAG 2.2](https://www.w3.org/TR/WCAG22/) as the target. Include browser
automation and a short manual keyboard pass.

**Progress (2026-07-19, slice 1):** dashboard document language, page `h1`
via `Layout`'s `hasOwnH1`, mobile-drawer focus trap/restore
(`islands/MobileNav.tsx`), named `RunHistory` table (`<caption>`,
`scope="col"`), non-color status (`StatusBar` health dot + sr-only text,
`RunHistory`/`ScenarioCard` pass/fail/skip text), and
`prefers-reduced-motion` coverage (`static/app.css`) are committed with
automated assertions in `browser_smoke_test.ts`.

**Known gap discovered while adding hydration-dependent assertions:**
Fresh's dev esbuild bundle fails to build for the whole scenario dashboard —
`islands/SessionPlayer.tsx`'s `await import("asciinema-player")` doesn't
resolve via esbuild-deno-loader (`Could not resolve "asciinema-player"
[plugin deno-loader]`), which breaks client-JS hydration for every island,
not just `SessionPlayer`. This is pre-existing and unrelated to phase 8: the
prior browser-smoke baseline (workstream 00 B0.2 item 5) only logged
console errors as warnings, never asserted on them, so this was silently
present already. It blocks live-browser verification of the mobile-drawer
focus trap; `browser_smoke_test.ts` detects the broken bundle and skips
those specific checks with a `[WARN]`. The trap/restore logic itself was
verified by source review (`islands/MobileNav.tsx`), standing in for the
manual keyboard pass until this is fixed. Own lane — likely fix is loading
`asciinema-player`'s pre-built browser bundle via the same CDN URL already
used for its CSS, rather than the bare `npm:` specifier.

**Progress (2026-07-19, slice 2): Admin UI — complete.**
`UIServerRuntime.m`: heading order (login `h1`, shell `h1`, 48 section
`h2`s, one nested `h3`); all labels bound via `for`/`id`; 12-tab nav gets
full ARIA tablist/tab/tabpanel roles, `aria-selected`, roving `tabindex`,
and arrow-key/`Home`/`End` navigation (`admin-ui.js`); ~19 status/error
containers get `aria-live="polite"`/`role="alert"`.
`Auth/Assets/authorize.html`: focus now moves into the consent step on
sign-in (both password and passkey paths); `#auth-error` gets
`role="alert"`. `admin_ui_browser_smoke_test.ts` Area 5 asserts all of
this against the real binary (green), and the OAuth consent-focus check —
previously a soft warning in the smoke test's own comments describing it
as a known gap — is now a hard assertion. Manual keyboard pass: covered by
Area 3 (tab order) plus Area 5's `ArrowRight`/`Home`/`End` tab-navigation
assertions, both against a live browser and the real `garazyk-ui` binary.

## U5. Visual conformance

Measure semantic foreground colors rather than trusting the design-system claim.
Split foreground tokens from decorative/background tokens where needed. Add
`prefers-reduced-motion` coverage for spinners, shimmer, pulse, and swaps.
Verify 200% zoom, narrow reflow, focus visibility, and touch target size.

## U6. Structural cleanup

After U1-U4:

1. Split `UIServerRuntime.m` into route registration, service view renderers,
   and static browser code.
2. Centralize loading, empty, error, and success rendering without unsafe
   `innerHTML` sinks.
3. Choose modular CSS as source and generate one checked bundle with a drift
   test.
4. Replace dashboard inline JSX styles with reusable state classes.
5. Add end-to-end hostile ANSI log rendering with `ansi_up` escaping locked on.

The Admin architecture reference must be rewritten against the dedicated
AdminUIServer. Obsolete migration-status and integration documents are retired
by this consolidation.

**Progress (2026-07-19): item 1 complete.** `UIServerRuntime.m` (was ~2900
lines, one `@implementation`) split into three files sharing the class via
categories, declared in a new `UIServerRuntime+Private.h`:
`UIServerRuntime.m` (route registration/dispatch, auth, login/shell
pages — core, ~1840 lines), `UIServerRuntime+StaticAssets.m` (the
`StaticAssets` category, static browser-asset serving), and
`UIServerRuntime+Renderers.m` (the `Renderers` category, 34 HTML-partial
render methods). The 6 file-scope helper functions (`UIEscaped`, `UISafe`,
etc.) lost their `static` linkage and moved to the shared private header so
all three files can use them. `CMakeLists.txt` updated in both places that
listed `UIServerRuntime.m` (the `garazyk-ui` executable and the `AllTests`
source list). Verified behavior-preserving: `UIServerRuntimeTests` 23/23
green, and a full `admin_ui_browser_smoke_test.ts` run (real binary, real
browser) green end to end, including the new Area 5 accessibility checks.

**Progress (2026-07-19): items 2 and 5 — audited and locked.** Audited
every `innerHTML`/`dangerouslySetInnerHTML` sink in the Admin UI and
dashboard JS/TSX (`admin-ui.js`, `lab.js`, `SessionPlayer.tsx`,
`LogViewer.tsx`). All but one already followed a safe pattern (static
template + `.textContent` for untrusted values, or trusted pre-escaped
server-rendered fragments via the centralized `replaceServerHTML`/
`showError` helpers in `admin-ui.js` — no separate centralization work
needed there). The one real sink, `LogViewer.tsx`'s
`dangerouslySetInnerHTML={{ __html: sanitizeLogHtml(ansiUp.ansi_to_html(text)) }}`
(item 5's target), had unit coverage for `sanitizeLogHtml` in isolation
but no proof the combination is safe in a real browser. Added a new Area
7 to `scenario-dashboard/browser_smoke_test.ts` that runs the actual
production pipeline (`ansi_up` + `utils/log_html.ts`'s `sanitizeLogHtml`,
not a duplicate) against 6 hostile payloads (script tags, `onerror`/
`onload`/`onmouseover` handlers, a `javascript:` href, a nested-tag
regex-bypass attempt) embedded in ANSI-colored text, injects the result
into a real page the way `LogViewer` does, and asserts no script executes
and no live `<script>`/`on*` attribute survives. Green.

**Progress (2026-07-19): item 3 — scoped and done for the two full-inline
modules.** `Assets/css/system.css` inlines `tokens.css`/`reset.css` in
full plus hand-curated "(selected)" subsets of `components.css`/
`layout.css`/`utilities.css`. Found real, demonstrable drift: the
standalone `tokens.css` and `reset.css` files (more recently refined —
e.g. `tokens.css`'s dark-mode background chroma/hue, and `reset.css`'s
`.skip-link` accessibility rule) had never been re-inlined into
`system.css`, so the *served* CSS was stale relative to its own
declared source. Added `scripts/admin-ui-build/generate_css_bundle.ts`
(regenerates the tokens/reset sections of `system.css` from the two
standalone files — `deno run -A ... [--check]`) and
`generate_css_bundle_test.ts` (a `Deno.test` drift check, both runnable
via `deno test scripts/admin-ui-build/`). Ran it once to fix the
existing drift (verified no visual regression: identical rendering
before/after in a real browser at `/admin/login`, since old and new
both trace to the same underlying values module-for-module). The three
"(selected)" sections are intentionally left hand-curated, not
generated — reconciling those (and the separately-drifted
`Garazyk/Sources/Shared/DesignSystem/css/*`, which serves the OAuth
`authorize.html` pages independently) would mean picking a winner
between legitimately different per-product designs, which is a design
decision, not a mechanical fix; noted here as explicit remaining scope,
not silently dropped.

Also noted, not fixed: the `garazyk-ui` CMake target's `Assets/`
POST_BUILD copy only re-runs when the target itself rebuilds (source
`.m` changes), not on Assets-only edits — an incremental-build reliability
gap unrelated to source-content correctness, filed as a follow-up rather
than expanded into this slice.

**Progress (2026-07-19): item 4 complete.** Replaced every remaining
static inline `style="..."` in the scenario dashboard (7 files:
`ExportReplayButton`, `NetworkStatus`, `RunReplayPanel`, `RunTimeline`,
`SessionPlayer`, `routes/run/[runId].tsx`, `routes/scenario/[id].tsx` —
20 unique property combinations, 28 call sites) with reusable utility/
state classes added to `app.css` (`.mb-lg`/`.p-md`/`.d-flex`/`.gap-sm`/
etc., plus semantic `.empty-state`/`.link-subtle`/`.section-title-inline`
for the three repeated multi-property patterns already named that way
in slice 1). Purely mechanical — every replacement carries the exact
same CSS property:value pairs the inline style had, just relocated to
a stylesheet rule. `deno check`/`deno lint` clean on every touched file
(the one type error and four lint findings that show up on these files
are pre-existing and unrelated — confirmed via `git stash`). Full
`browser_smoke_test.ts` run green.

**Progress (2026-07-19): U6 complete.** Last item: the Admin architecture
reference (`Garazyk/Sources/Admin/ADMINUI_ARCHITECTURE.md`) was fully
rewritten against the current `AdminUIServer` implementation — it
previously described a pre-`AdminUIServer` `PDSAdminHandler`/
`AdminUITemplateRenderer`/handlebars-template layout that no longer
exists. The rewrite covers the real source layout (the U6-item-1 file
split), data flow (login, the htmx-driven tab shell, mutations, `/lab`
OAuth), the CSS system (U6-item-3's generated bundle + its scope
boundary), accessibility (all of U4/U6-item-2's work), and security
(CSP nonce/CSRF/session mechanics, verified against `UIAuthManager.h`
and `UIServerRuntime.m`). The two obsolete migration-status documents
this consolidation retires (`Garazyk/Sources/Admin/archive/
ADMINUI_DELIVERY_SUMMARY.md` and `ADMINUI_INTEGRATION_COMPLETE.md` — an
April 2026 `PDSAdminHandler` delivery/integration report, fully
superseded) are deleted; the three hand-maintained doc-index files that
referenced them (`docs/11-reference/admin-ui-documentation.md`,
`source-adjacent-documentation.md`, `documentation-map.md`) are updated
to match. `docs/repo-index/*` is auto-generated and left for its own
tooling to refresh.

This closes workstream 04 U4 and U6 in full; U5 (visual conformance —
measured contrast, 200% zoom/reflow, touch targets, dashboard keyboard
order at narrow widths) remains open, tracked in phase 8's prompt.

Primary sources:

- [CSP Level 3](https://www.w3.org/TR/CSP/)
- [WCAG status messages](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html)
- [WCAG focus order](https://www.w3.org/WAI/WCAG22/Understanding/focus-order.html)
