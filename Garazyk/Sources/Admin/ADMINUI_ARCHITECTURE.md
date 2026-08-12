# Admin UI Architecture

`ATProtoAdminUI` is the reusable, server-rendered admin UI library. It depends
only on `ATProtoTransport` and `ATProtoCore`; it does not open service
databases or embed a service runtime. Each service binary embeds
`GZAdminUIHost` on a dedicated loopback listener (for example `kaszlak` on
`127.0.0.1:2590`) and composes the packs it owns.

## Source

```text
Garazyk/Sources/AdminUIServer/
  GZAdminUIHost.m
  GZAdminUIHost+Private.h
  UIAuthManager.m                 (GZAdminUIAuthManager)
  GZAdminUIBackendClient.m
  UIServiceConfig.m               (GZAdminUIServiceConfig)
  UITemplateEngine.m              (GZAdminUITemplateEngine)
  UITileDataProtocol.m
  UITileExecutionPolicy.m
  Packs/
```

The host and shared UI primitives are compiled into `ATProtoAdminUI`. Service
and feature route composition lives in `Packs/`, where each pack is linked into
the same library. Add new library sources to the `ATProtoAdminUI` target.
Service binaries supply only a small bootstrap that builds config, selects
packs, and starts the host.

## Request flow

`GZAdminUIHost` serves the login page, admin shell, partial routes, and static
assets.

After login, `GZAdminUIAuthManager` issues a session cookie and CSRF nonce. The shell
loads tab content from `/admin/partials/*`. Mutations pass through
`admin-ui.js`, which sends the nonce in `X-UI-Admin-Nonce`.

`GZAdminUIBackendClient` converts UI actions into calls to the configured services.
Returned HTML is inserted into the relevant result container.

The `/lab` page is a small OAuth client used to exercise the PDS authorization
flow. Its OAuth session is separate from admin authentication.

Single-surface shells render a peer switcher of plain configured links
(`GARAZYK_ADMIN_UI_PEERS` / `PDS_ADMIN_UI_PEERS` as `Name=URL` entries). Links
are presentation-only: no polling, credentials, or health claims.

## Rendering and assets

Renderers build HTML strings in Objective-C. Escape dynamic HTML values with
`GZAdminUIEscaped()` and keep the tile protocol/policy helpers additive to the
existing `/lab` flow.

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

- a session cookie managed by `GZAdminUIAuthManager`
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
5. Build the owning service binary and `AllTests`.
6. Extend the browser smoke test or `UIServerRuntimeTests`.

```sh
cmake --build build --target kaszlak AllTests --parallel 4
```
