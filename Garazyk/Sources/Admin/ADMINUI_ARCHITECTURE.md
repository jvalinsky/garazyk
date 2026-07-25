# Admin UI Architecture

`garazyk-ui` is a separate HTTP service. It calls the PDS, PLC, relay, AppView,
Ozone, chat, and video APIs through `UIBackendClient`. It does not open their
databases.

## Source

```text
Garazyk/Sources/AdminUIServer/
  UIServerRuntime.m
  UIServerRuntime+StaticAssets.m
  UIServerRuntime+Renderers.m
  UIServerRuntime+Private.h
  UIAuthManager.m
  UIBackendClient.m
  UIServiceConfig.m
  Assets/
```

The runtime files implement one class with Objective-C categories. Add new
source files to both the `garazyk-ui` and `AllTests` CMake source lists.

## Request flow

`UIServerRuntime` serves the login page, admin shell, partial routes, and static
assets.

After login, `UIAuthManager` issues a session cookie and CSRF nonce. The shell
loads tab content from `/admin/partials/*`. Mutations pass through
`admin-ui.js`, which sends the nonce in `X-UI-Admin-Nonce`.

`UIBackendClient` converts UI actions into calls to the configured services.
Returned HTML is inserted into the relevant result container.

The `/lab` page is a small OAuth client used to exercise the PDS authorization
flow. Its OAuth session is separate from admin authentication.

## Rendering and assets

Renderers build HTML strings in Objective-C. Escape dynamic HTML values with
`UIEscaped()`.

The admin shell loads `Assets/css/system.css`. Its token and reset sections are
generated from:

- `Assets/css/tokens.css`
- `Assets/css/reset.css`

Regenerate the bundle after changing those files:

```sh
deno run -A scripts/admin-ui-build/generate_css_bundle.ts
```

Client behavior lives in `Assets/js/admin-ui.js`. `/lab` and the MST viewer have
separate scripts.

## Security

The UI uses:

- a session cookie managed by `UIAuthManager`
- a double-submit CSRF cookie and request header
- per-response CSP nonces
- `script-src-attr 'none'`
- HTML escaping for server-rendered values

Do not add inline event handlers. Use `data-ui-action` or `data-ui-form` with
the delegated handlers in `admin-ui.js`.

Keep backend tokens and passwords in the service environment or secret files.

## Accessibility

The shell uses ARIA tabs with roving `tabindex` and keyboard navigation. Labels
must reference their controls with `for` and `id`. Async result regions use
`aria-live` or `role="alert"`.

When adding a tab, preserve the existing tab and panel relationships and keep
the page heading order intact.

## Add a section

1. Add a renderer and declaration.
2. Register its partial route.
3. Add the tab and panel markup.
4. Add delegated JavaScript only when the shared behavior is insufficient.
5. Build `garazyk-ui` and `AllTests`.
6. Extend the browser smoke test or `UIServerRuntimeTests`.

```sh
cmake --build build --target garazyk-ui AllTests --parallel 4
```
