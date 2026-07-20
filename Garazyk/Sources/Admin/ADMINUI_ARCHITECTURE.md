# Admin UI Architecture

This describes the current, dedicated `garazyk-ui` service — `AdminUIServer` —
not the earlier `PDSAdminHandler`-embedded admin panel. Source of truth is
always `Garazyk/Sources/AdminUIServer/` and its tests; if this document and
the code disagree, the code wins and this document should be corrected.

## System overview

`garazyk-ui` is a standalone HTTP server that renders a browser-based admin
console for the AT Protocol services in this repo: PDS, PLC, Relay, AppView,
Ozone (moderation), Chat, and Video. It talks to those services as an admin
client over their own XRPC/HTTP APIs (via `UIBackendClient`) — it holds no
direct database access of its own. It also hosts `/lab`, a minimal AT Protocol
OAuth client used to exercise the real sign-in → consent → callback flow
end to end.

## Technology stack

- **Backend**: Objective-C, built as the `garazyk-ui` CMake target
  (`Garazyk/Binaries/garazyk-ui/main.m`).
- **HTML generation**: server-rendered `NSString` templates with manual
  escaping (`UIEscaped()`), not a template engine. Every partial is a plain
  Objective-C method that builds an HTML string.
- **Client interactivity**: [htmx](https://htmx.org) 1.9.12 (loaded from
  `unpkg.com`, pinned by [SRI](https://developer.mozilla.org/en-US/docs/Web/Security/Subresource_Integrity)
  hash) drives tab-content loading (`hx-get`/`hx-trigger`); a small vanilla-JS
  file (`Assets/js/admin-ui.js`) handles everything htmx doesn't — CSRF-aware
  fetch wrapper, form submission, tab keyboard navigation, DID-autofill.
- **Styling**: a single generated CSS bundle, `Assets/css/system.css` (see
  "CSS system" below).
- **Auth**: single shared admin password (`UIAuthManager`), session cookie +
  double-submit CSRF cookie/header pair.

## Source layout

```
Garazyk/Sources/AdminUIServer/
├── UIServerRuntime.h/.m           # Route registration/dispatch, auth,
│                                    login page, admin shell page
├── UIServerRuntime+Private.h      # Shared private @property list + the two
│                                    categories' method declarations
├── UIServerRuntime+StaticAssets.m # StaticAssets category: /css/*, /js/*,
│                                    /img/* serving
├── UIServerRuntime+Renderers.m    # Renderers category: 34 HTML-partial
│                                    render methods (one per tab/section)
├── UIAuthManager.h/.m             # Session tokens, CSRF nonces, cookies
├── UIBackendClient.h/.m           # Admin HTTP client for PDS/PLC/Relay/
│                                    AppView/Ozone/Chat/Video
├── UIServiceConfig.h/.m           # Backend URLs/tokens, host/port config
└── Assets/
    ├── css/                      # system.css (served) + its modular
    │                                sources (tokens/reset/components/
    │                                layout/utilities.css)
    └── js/
        ├── admin-ui.js           # Admin shell interactivity
        ├── lab.js                # /lab OAuth client
        └── mst-viewer/           # MST tree/stats explorer (its own JS module)
```

`UIServerRuntime.m`, `+StaticAssets.m`, and `+Renderers.m` are three files
implementing **one class** via Objective-C categories — not three separate
services. All three are listed explicitly in `CMakeLists.txt`, in both the
`garazyk-ui` executable target and the `AllTests` source list; a new file
split like this needs both updated.

## Data flow

### Login

```
GET /admin/login  →  loginPageHTML (UIServerRuntime.m)
POST /admin/login  →  UIAuthManager validates password
                    →  Set-Cookie: session token + CSRF nonce cookie
                    →  redirect to /admin
```

### Admin shell + tabs

```
GET /admin  →  adminShellHTML (UIServerRuntime.m): one <h1>, a 12-item
               role="tablist" nav, 12 role="tabpanel" <div>s (all but the
               active one `hidden`)
Tab click (admin-ui.js switchTab)
  →  toggles aria-selected / roving tabindex / .active / `hidden`
  →  htmx hx-get on the newly-visible pane's placeholder
  →  GET /admin/partials/<name>  →  a render*Partial method in
     UIServerRuntime+Renderers.m
  →  htmx swaps the returned HTML into the pane
```

Keyboard: `ArrowLeft/Right/Up/Down`/`Home`/`End` move focus and selection
between tabs (`admin-ui.js`, WAI-ARIA APG tabs pattern); the previously-
selected tab drops out of the Tab order (roving `tabindex`).

### Mutations

```
Form submit / button click (data-ui-form / data-ui-action)
  →  admin-ui.js reads the CSRF nonce from <meta name="csrf-nonce">
  →  POST with X-UI-Admin-Nonce header
  →  UIServerRuntime validates session cookie + CSRF nonce
     (UIAuthManager) before touching any backend
  →  UIBackendClient calls the real PDS/PLC/Relay/AppView/Ozone/Chat/
     Video admin API
  →  response HTML swapped into a `*-result` container
     (aria-live="polite", so screen readers hear the outcome)
```

### `/lab` OAuth flow

`/lab` is a separate, self-contained page (`labShellHTML`, `lab.js`) that
drives the real AT Protocol OAuth flow against the configured PDS: PAR →
`/oauth/authorize` (password or WebAuthn passkey sign-in) → consent →
`/lab/callback`. It exists to exercise `Garazyk/Sources/Auth/`'s OAuth
implementation end to end, independent of the admin shell's own
password+CSRF auth.

## CSS system

`Assets/css/system.css` is the one stylesheet the admin shell and login page
load (`<link rel="stylesheet" href="/css/system.css">`). It's not hand-authored
top to bottom:

- Its `tokens.css` and `reset.css` sections are **generated** from the
  standalone `Assets/css/tokens.css`/`reset.css` files —
  `scripts/admin-ui-build/generate_css_bundle.ts` (with a `deno test`
  drift check in `generate_css_bundle_test.ts`). Edit the standalone files
  and re-run the generator; don't hand-edit those two sections in
  `system.css` directly, or they'll drift again (as they had before
  2026-07-19 — see workstream 04 U6).
- Its `components.css`/`layout.css`/`utilities.css` sections are
  hand-curated **subsets** of the correspondingly-named standalone files
  (marked `(selected)` in the section comments) — deliberately not a full
  mirror, and not currently generated.

Colors are OKLCH custom properties (`--color-bg-primary`, `--color-accent`,
etc.) with a `@media (prefers-color-scheme: dark)` override block; spacing is
a `--space-{xs,sm,md,lg,xl,2xl,3xl,4xl}` scale. Both are defined once in
`tokens.css`.

`Garazyk/Sources/Shared/DesignSystem/css/` is a **separate**, independently-
maintained copy of the same modular file set that serves the OAuth
`authorize.html`/`/lab` pages via `OAuth2Handler.m`'s `sharedCSSPath`. It has
its own drift from `AdminUIServer/Assets/css/` — reconciling the two would
mean picking a winner between legitimately different per-product designs
and is out of scope here; see workstream 04 U6 for the current state.

## Accessibility

- One `<h1>` per page (login, shell); `admin-section-title` headings are
  `<h2>`, with one nested `<h3>` for MST node detail — no skipped levels.
- Every `<label>` is bound to its control via `for`/`id`, including the
  per-service Connections form (label text is static, `for`/`id` are
  interpolated with the service ID).
- The tab nav is a full WAI-ARIA APG tabs pattern:
  `role="tablist"`/`"tab"`/`"tabpanel"`, `aria-selected`,
  `aria-controls`/`aria-labelledby`, roving `tabindex`, arrow-key/`Home`/`End`
  navigation.
- ~19 status/error containers (`*-result` divs, the connection test-result
  span, the login error `<p>`) are `aria-live="polite"` or `role="alert"` so
  async outcomes are announced.
- OAuth sign-in → consent (`authorize.html`) moves focus into the consent
  step's heading on both the password and passkey paths, instead of
  stranding focus on the now-hidden sign-in button.

Automated coverage: `scripts/admin_ui_browser_smoke_test.ts` drives the real
binary through a real headless browser (CSP, CSRF, keyboard order, the ARIA
tab structure, label binding, the `/lab` OAuth flow) — see its own header
comment for the full checklist.

## Security

- **CSP**: a per-request nonce (`UIGenerateNonce`) on `<script>`/`<style>`,
  `script-src-attr 'none'` (blocks inline event-handler attributes
  entirely — this is why every interactive element uses `data-ui-action`/
  `data-ui-form` plus a delegated listener in `admin-ui.js`, never
  `onclick="..."`), `default-src 'self'`.
- **CSRF**: double-submit cookie pattern — a `ui_admin_nonce` cookie plus a
  required `X-UI-Admin-Nonce` request header that must match; nonce rotates
  on each authenticated response (`X-UI-Admin-Nonce` in the response,
  read by `admin-ui.js`'s `refreshCSRFNonce`).
- **Session**: a random token, SHA-256-hashed before being held in memory
  (`UIAuthManager`), 8-hour default TTL, `Secure`/`HttpOnly` cookie
  attributes.
- **XSS**: all server-rendered dynamic values go through `UIEscaped()`;
  verified against a real hostile identifier (an email containing a raw
  `<script>` tag) in `admin_ui_browser_smoke_test.ts`'s Area 1.

## Extending the admin shell

1. Add a render method to `UIServerRuntime+Renderers.m`, declare it in
   `UIServerRuntime+Private.h`'s `Renderers` category.
2. Register its route (`/admin/partials/<name>`) alongside the others in
   `UIServerRuntime.m`.
3. Add the tab button + pane to `adminShellHTML` — copy an existing tab's
   `role="tab"`/`role="tabpanel"`/`aria-*` attributes exactly (see
   "Accessibility" above); `admin-ui.js`'s `switchTab` and the keyboard
   handler work off the `.service-segment`/`.tab-pane` classes generically,
   no per-tab JS needed.
4. If the section needs new labeled form controls, bind every `<label>`
   via `for`/`id` from the start.
5. Reconfigure and rebuild (`cmake --build build --target garazyk-ui
   AllTests --parallel 4`) — CMake's source list is explicit, not a glob.
6. Extend `admin_ui_browser_smoke_test.ts` (or add a `UIServerRuntimeTests`
   case) rather than relying on manual verification alone.
