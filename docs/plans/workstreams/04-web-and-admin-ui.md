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

Primary sources:

- [CSP Level 3](https://www.w3.org/TR/CSP/)
- [WCAG status messages](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html)
- [WCAG focus order](https://www.w3.org/WAI/WCAG22/Understanding/focus-order.html)
