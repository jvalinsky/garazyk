---
name: garazyk-admin-ui
description: Build, modify, or review Garazyk Admin UI work. Covers HTMX/server-rendered UI conventions, design-system usage, accessibility, auth/session boundaries, frontend security, static assets, and UI tests.
---

# Garazyk Admin UI

Use this skill for `Garazyk/Sources/AdminUIServer/`, Admin UI assets, HTMX-style interactions, operator dashboards, and UI security/accessibility reviews.

## Key files

- Runtime/server: `Garazyk/Sources/AdminUIServer/UIServerRuntime.{h,m}`
- Auth/session: `Garazyk/Sources/AdminUIServer/UIAuthManager.{h,m}`
- Backend calls: `Garazyk/Sources/AdminUIServer/UIBackendClient.{h,m}`
- Config: `Garazyk/Sources/AdminUIServer/UIServiceConfig.{h,m}`
- Assets: `Garazyk/Sources/AdminUIServer/Assets/`
- Design docs: `Garazyk/Sources/AdminUIServer/Assets/DESIGN_SYSTEM.md`, `Garazyk/Sources/AdminUIServer/Assets/QUICK_REFERENCE.md`, `Garazyk/Sources/AdminUIServer/Assets/README.md`
- CSS: `Garazyk/Sources/AdminUIServer/Assets/css/*.css`
- JS: `Garazyk/Sources/AdminUIServer/Assets/js/`
- Static tests: `scripts/test/check_ui_design_system.sh`, `scripts/test/test_static_files.sh`, `scripts/test/test_page_load.sh`

## UI principles

- Treat the Admin UI as an operator tool for sensitive ATProto infrastructure.
- Prefer server-rendered HTML and small progressive-enhancement JS.
- Follow the existing AppKit-native design system; do not introduce a second visual language.
- Maintain keyboard, screen-reader, and reduced-motion behavior.
- Keep authentication and authorization checks server-side.

## Design-system workflow

Before adding markup or styles:

1. Read `Garazyk/Sources/AdminUIServer/Assets/QUICK_REFERENCE.md` for component names and classes.
2. Check `Garazyk/Sources/AdminUIServer/Assets/DESIGN_SYSTEM.md` for tokens, spacing, colors, and accessibility rules.
3. Reuse existing components before adding CSS.
4. If adding a new primitive, document it in the design docs and demo page.

Avoid:

- inline styles except for unavoidable dynamic values
- hardcoded colors outside tokens
- inconsistent spacing not on the 4pt grid
- one-off button/table/form variants
- client-side-only critical controls

## HTMX/server-rendered conventions

When adding an interaction:

- Define the server route and response fragment first.
- Return HTML fragments that are valid when inserted alone.
- Include empty/error/loading states.
- Make the non-JS fallback acceptable for critical flows.
- Keep state-changing operations behind POST with CSRF/session validation where applicable.
- Use explicit IDs and stable selectors only where needed.

For dynamic tables/lists:

- include pagination or limits
- preserve filters in forms/links
- handle zero results
- avoid leaking sensitive fields in row data attributes

## Auth and session boundaries

Admin UI work must answer:

- Who can access this route?
- Is the check in `UIAuthManager`/middleware/server path, not only in JS?
- Does the backend API require a separate token or admin password?
- Are cookies/session values secure, httpOnly, SameSite, and scoped appropriately?
- Do redirects avoid open redirect behavior?
- Are logout/session expiry paths tested?

Never expose bearer tokens, admin password material, phone/email secrets, or raw database paths to the browser.

## Frontend security checklist

- Escape all untrusted strings before rendering HTML.
- Prefer text nodes/escaped helpers over string concatenation.
- Avoid `innerHTML` in JS unless input is trusted/static and documented.
- Sanitize URLs; block `javascript:` and unexpected schemes.
- Use POST for mutations and include server-side authorization.
- Redact secrets in UI logs and diagnostic panels.
- Validate IDs/DIDs/handles again on the server.
- Do not trust hidden inputs for authorization decisions.

## Accessibility checklist

- Every input has a label.
- Buttons have accessible text and are reachable by keyboard.
- Focus order follows visual order.
- Dialogs/modals trap and restore focus if implemented.
- Status updates use appropriate live regions where needed.
- Color is not the only signal for success/warning/error.
- Text and controls meet contrast targets in light and dark modes.
- Tables have headers and meaningful empty states.

## Static asset testing

Run targeted UI checks after changes:

```bash
scripts/test/check_ui_design_system.sh
scripts/test/test_static_files.sh
scripts/test/test_page_load.sh
```

For full validation, use:

```bash
garazyk_build_test
```

If a test depends on a running service, use `garazyk_service_control` or the scenario runner to start the stack.

## Review workflow

When reviewing Admin UI changes, report:

1. affected routes/assets
2. auth boundary and whether it is server-side
3. design-system conformance
4. accessibility issues
5. frontend injection/secret risks
6. tests run or missing

## Definition of done

- Uses existing design tokens/components.
- Server-side auth boundary is explicit.
- Untrusted data is escaped.
- Keyboard/screen-reader behavior is considered.
- Static asset/page/design-system tests pass or skipped with reason.
- Sensitive operational data is not exposed to the browser.
