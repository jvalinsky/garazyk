---
title: PDS Admin UI Brief
status: in-progress
last_verified: 2026-08-12
---

# PDS (`kaszlak`)

**Authority:** [workstream 11](../11-per-service-admin-uis.md), the
[shared contract](README.md), and [ADR 0033](../../../adr/0033-per-service-embedded-admin-uis.md).
PDS dependencies are visible in [PLC](plc.md), [Beskid](beskid.md),
[Chat](chat.md), and [Video](video.md), but the PDS UI reports only local state.

## Outcome and evidence

Embed the largest admin surface last. `kaszlak` owns the existing PDS, Ozone,
Security, Data Explorer, MST, and Lab packs. Current routes cover accounts,
invites, blobs, server statistics, audit logs, reports, moderation/security
operations, repository exploration, and protocol labs. The existing PDS pack
also renders fleet-wide Overview and Connections; those cross-service panels
are deleted under workstream 11 M5 rather than embedded.

### Embed status (2026-08-12)

`kaszlak serve` starts `GZAdminUIHost` when an operator password is configured
(`PDS_ADMIN_PASSWORD` / `PDS_ADMIN_PASSWORD_FILE`, or the UI-specific
`PDS_ADMIN_UI_*` variants). Defaults: `127.0.0.1:2590`, six packs, backend
client pointed at `http://127.0.0.1:<protocol-port>` with the same password for
`/admin/login`. Missing password leaves the protocol listener unchanged and
skips the admin listener. `PDS_ADMIN_UI_PUBLIC_URL` (or `PDS_UI_SERVER_URL`)
is linked from the public protocol `GET /` landing page as the admin sign-in
target; protocol `/` never redirects into the admin UI.

Composition evidence: `KaszlakAdminUICompositionTests` and
`ATProtoHttpServerBuilderTests/testAdminRoutesRedirectToUIServerAndRootIsPlainText`.
Service-scoped shells (`serviceIdentifier = pds`) omit fleet Overview/Connections
tabs and title as `PDS`; the backend client allows loopback HTTP to the local
protocol listener.

Landed on `main` as `bbc84dd4` (2026-08-12). Live cutover on crimson-comet:
nginx `ui.garazyk.xyz` → `127.0.0.1:2590`, password-file drop-in, operator
login verified.

### Operator UX hardening (2026-08-12, same commit)

Verified against the live crimson listener after hard-refresh / asset cache
bust (`?v=json-mst-2`):

- **Ozone overview** is server-composed (reports / events / statuses / config
  in one response) so nested HTMX placeholders no longer 404 or spam.
- **MST** ships tree JSON in a hidden `<pre>` (HTMX `innerHTML` empties
  `<script>` bodies) and renders an SVG pan/zoom diagram including leaf
  record nodes; accounts list uses `load once`.
- **Data Explorer** describe layout tops JSON labels; DID documents use the
  shared JSON tree/raw/copy viewer; list-records fills Collection/Rkey from
  `at://` URIs when the XRPC payload omits them.
- Login CSRF rotates after failed attempts; invite render no longer assumes
  `uses` is a string on GNUstep.

### Still open for full M4 acceptance

1. Full `PDSAdminSnapshot` (sequencer/pool/WAL/sessions) beyond server-stats
   key mapping — **partial 2026-08-12:** `renderServerStatsPartial` now reads
   allowlisted `*_total` / lexicon camelCase keys (Accounts/Repos/Records/Blobs/
   blob bytes/open reports).
2. ~~NixOS/container secret-file, bind/port, and reverse-proxy module examples~~
   **Done 2026-08-12:** `nixos/modules/kaszlak.nix`, `nixos/examples/kaszlak.nix`,
   `flake.nix` `nixosModules.kaszlak` (parse + type check).
3. Checked-in browser/visual smoke already target `:2590`; re-run evidence /
   optional CI job still open (scripts exist).
4. ~~Lab OAuth scenario retarget~~ **Done 2026-08-12:**
   `11_lab_oauth_login.ts` prefers `SERVICE_URLS.ui`, uses
   `gz_admin_pds_*` cookies, and polls `/admin/partials/pds-stats`. Lab remains
   `/lab`-only (no sidebar tab) by design.
5. ~~Slice 3 DTO allowlists~~ **Done 2026-08-12:** shared
   `GZAdminUIDTOProjection` covers Security sessions/app-passwords, PDS
   accounts/invites/detail/blobs/stats/audit/reports, and Data Explorer
   describe/list/getRecord (`value` omitted from list rows). Evidence:
   `GZAdminUIDTOProjectionTests`.

## Dashboard shape

- **Overview:** health, uptime, accounts/repos/records/blobs, sequencer head and
  age, call/error rate, active sessions, moderation backlog, storage pressure,
  database pool/WAL health, and service dependency status only where the PDS
  itself already depends on it.
- **Accounts and invites:** bounded search/detail, account state, invite usage,
  and explicitly confirmed disable/takedown/delete operations.
- **Repositories and blobs:** safe repository summary, collection/cardinality,
  blob count/bytes, missing/orphan audit state, sequencer events, MST inspection,
  and cursor pagination. No raw SQL or unrestricted record dumps.
- **Moderation and security:** reports, audit history, OAuth/security diagnostics,
  and narrow actions with reason, subject, actor, result, and request ID.
- **Lab:** protocol diagnostics remain clearly separated from production
  mutations and inherit the same session and CSRF boundary.

## Slices and acceptance

1. Define one cheap PDS overview snapshot from existing health, sequencer,
   metrics, pool, moderation, and storage components; headline polling must not
   scan actor stores or blob directories. **Open.**
2. Move all six packs and clients under PDS ownership, remove Overview and
   Connections, and keep the host service-agnostic. **Partial:** service-scoped
   shell omits Overview/Connections; packs still live under `AdminUIServer/`
   until M5 retires the compatibility host.
3. Replace broad backend dictionaries with per-view DTO allowlists, especially
   for account email, tokens, audit payloads, repository records, and security
   material. **Done 2026-08-12** (`GZAdminUIDTOProjection` + pack wiring;
   `GZAdminUIDTOProjectionTests`).
4. Embed the listener and internal token in `kaszlak`; migrate its admin
   credential to operator login without exposing backend tokens to the browser.
   **Done 2026-08-12** (`bbc84dd4`; password-gated; public URL link; crimson
   cutover).
5. Add NixOS/container secret-file, bind/port, backup-aware, and reverse-proxy
   examples; move the Lab OAuth scenario to the PDS listener.
   **Done 2026-08-12** (`nixos/modules/kaszlak.nix` + example; Lab scenario
   retargeted to embedded UI cookies/partials).
6. Test each pack, dangerous-action confirmation, audit, auth/CSRF, pagination,
   empty/large stores, pool starvation, concurrent repository writes, 200% zoom,
   and scenario/topology compatibility. **Partial:** composition + focused
   unit tests + existing browser/visual scripts; CI wiring of those smokes still
   open. Security/PDS/explorer DTO allowlists landed.

Acceptance requires all six local packs to work without fleet credentials,
bounded polling under a representative multi-actor database, no protocol-write
regression, and clean Deno topology/scenario gates. Rollback returns the packs
to the compatibility host while leaving the PDS protocol listener unchanged;
it never restores fleet-wide Overview or Connections credentials.

## Crimson / production cutover checklist

Nginx already proxies `ui.garazyk.xyz` → `127.0.0.1:2590`. After shipping this
embed:

1. Deploy a `kaszlak` build that includes `PDSAdminUIBootstrap.m` and synced
   `Assets/` next to the binary (`add_admin_ui_assets(kaszlak)`).
2. Set `PDS_ADMIN_PASSWORD` or `PDS_ADMIN_PASSWORD_FILE` on the service (UI is
   disabled without it). Prefer a root-readable file via systemd credentials.
3. Set `PDS_ADMIN_UI_HOST=127.0.0.1`, `PDS_ADMIN_UI_PORT=2590`, and
   `PDS_ADMIN_UI_PUBLIC_URL=https://ui.garazyk.xyz/admin` so the public
   `GET /` landing can link to the published admin UI.
4. Restart `kaszlak`, confirm `ss -ltnp | grep 2590`, then open
   `https://pds.garazyk.xyz/` (public status) and
   `https://ui.garazyk.xyz/admin` (operator sign-in).
5. Keep a current `index.html` in the service working directory (or rely on
   the embedded fallback landing in `ATProtoHttpServerBuilder`).

Rollback: unset the admin password (or stop exposing 2590 in nginx). The
protocol listener on 2583 is unchanged.

## Operator env (embed)

| Variable | Role |
| --- | --- |
| `PDS_ADMIN_PASSWORD` / `_FILE` | Enables UI + protocol `/admin/login` |
| `PDS_ADMIN_UI_PASSWORD` / `_FILE` | Optional UI-only override |
| `PDS_ADMIN_UI_HOST` / `PORT` | Bind (default `127.0.0.1` / `2590`) |
| `PDS_ADMIN_UI_PUBLIC_URL` | Admin sign-in link on public `GET /` |
| `GARAZYK_ADMIN_UI_ASSETS_DIR` | Optional Assets override |

