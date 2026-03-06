---
title: Objective-J UI Migration - Phase 1 Parity Matrix
---

# Objective-J UI Migration - Phase 1 Parity Matrix

## Baseline
This matrix is the canonical inventory of legacy web UI behavior to migrate.

Locked migration gate: **full parity required** for Explore + Admin + MST Viewer + OAuth Demo.

Acceptance-check convention (locked): the `Expected UI state transition` column is the per-row acceptance check used for verification.

## Status Model (Locked)
- `unmapped`: no Objective-J behavior exists yet for this action.
- `mapped`: action is planned and bound to a contract, but not implemented.
- `contract-validated`: contract verified against current backend/runtime behavior.
- `implemented`: behavior exists in Objective-J but not fully verified.
- `verified`: behavior implemented and validated by acceptance tests.

## Severity Model (Locked)
- `P0`: cutover blocker.
- `P1`: must-fix before default switch.
- `P2`: deferrable only with explicit approval.

## Explore Surface
| ID | User-visible action | Entry route / trigger | Contract ID(s) | Backend call(s) | Auth | Response dependency (fields consumed) | Expected UI state transition | Status | Severity |
|---|---|---|---|---|---|---|---|---|---|
| `E-00` | Open About menu item | Apple menu -> `About Kaszlak` | `LOCAL-01` | none | none | none | Menu action is non-mutating (no route/API call, no state change) | `unmapped` | `P2` |
| `E-01` | Load legacy desktop shell | `GET /` | `ROUTE-01` | none (shell HTML + static assets) | none | Main desktop windows/menus render | Desktop shown, `did-doc` section active, accounts load starts | `unmapped` | `P0` |
| `E-02` | Open Accounts window | `#menu-accounts` | `LOCAL-01` | none | none | none | `#win-accounts` becomes visible | `unmapped` | `P1` |
| `E-03` | Lookup DID/handle | enter in `#lookup-input` | `EXP-02` | `GET /api/pds/lookup` | none | `did`, `handle` or `error` | Selected DID context updates, DID view opened | `implemented` | `P0` |
| `E-04` | Load account list | init / refresh | `EXP-01` | `GET /api/pds/accounts` | none | `accounts[].did`, `accounts[].handle` | Account list populated, empty state on none | `implemented` | `P0` |
| `E-05` | Select account and load primary data | click account row | `EXP-03`, `EXP-04`, `EXP-05` | Parallel `GET /api/pds/did`, `/api/pds/plc-log`, `/api/pds/describe` | none | DID document JSON, PLC ops array, `collections[]` | Content panes switch from loading to rendered data | `implemented` | `P0` |
| `E-06` | View DID document section | `View -> DID Document` | `LOCAL-01`, `EXP-03` | none immediately; data from prior call | none | DID fields: `id`, `alsoKnownAs`, `verificationMethod`, `service` | DID pane active with summary + full JSON | `implemented` | `P1` |
| `E-07` | View PLC operations section | `View -> PLC Operations` | `LOCAL-01`, `EXP-04` | none immediately; data from prior call | none | PLC entries: `op`, `cid`, `createdAt` | PLC pane active with timeline | `implemented` | `P1` |
| `E-08` | View repo collections section | `View -> Repo Collections` | `LOCAL-01`, `EXP-05` | none immediately; data from prior call | none | `collections[]` | Collections pane active with collection table | `implemented` | `P1` |
| `E-09` | Browse records in collection | click `View Records` | `EXP-06` | `GET /api/pds/records` | none | `records[]` (`uri`,`rkey`,`cid`,`value`), `cursor` | Records section opens with collection-scoped rows | `implemented` | `P0` |
| `E-10` | Open record detail | click `View Detail` | `EXP-07` | `GET /api/pds/record` | none | Record payload + `$type` branch fields | Record detail section opens with typed renderer | `implemented` | `P0` |
| `E-11` | Toggle rendered/JSON in record views | per-record toggle buttons | `LOCAL-02` | none | none | local rendered payload already loaded | Rendered panel and JSON panel swap | `implemented` | `P2` |
| `E-12` | View feed posts | `View -> Feed Posts` | `LOCAL-01`, `EXP-10` | `GET /api/pds/feed-posts` | none | `posts[].author`, `posts[].record`, `count` | Feed posts pane active and populated | `implemented` | `P1` |
| `E-13` | View feed likes | `View -> Feed Likes` | `LOCAL-01`, `EXP-11` | `GET /api/pds/feed-likes` | none | `likes[].subject.uri`, `likes[].createdAt` | Feed likes pane active and populated | `implemented` | `P1` |
| `E-14` | View feed reposts | `View -> Feed Reposts` | `LOCAL-01`, `EXP-12` | `GET /api/pds/feed-reposts` | none | `reposts[].subject`, `reposts[].createdAt` | Feed reposts pane active and populated | `implemented` | `P1` |
| `E-15` | View social graph follows | `View -> Social Graph` | `LOCAL-01`, `EXP-13` | `GET /api/pds/graph-follows` | none | `actors[].did`, `actors[].handle`, `actors[].displayName` | Social graph pane active and populated | `implemented` | `P1` |
| `E-16` | View actor profile | `View -> Actor Profile` | `LOCAL-01`, `EXP-14` | `GET /api/pds/actor-profile` | none | `handle`, `displayName`, `description`, follow/post counts | Actor profile pane active and populated | `implemented` | `P1` |
| `E-17` | Toggle rendered/JSON for feed/profile cards | per-card toggle buttons | `LOCAL-02` | none | none | local loaded JSON payloads | Card content switches between rendered and JSON | `implemented` | `P2` |
| `E-18` | Decode CID utility | `Utilities -> CID Decoder`, click decode | `LOCAL-01`, `LOCAL-02` | none (client-side decode) | none | CID decoded fields (codec/hash/size) | CID window displays decode table | `implemented` | `P2` |
| `E-19` | Open API reference docs | `PDS -> API Reference` | `EXP-15` | `GET /api/pds/docs` | none | HTML docs page | Browser navigates to docs page | `implemented` | `P2` |
| `E-20` | Open PLC explorer/metrics links | `PLC` menu links | `LOCAL-01` | external navigation | none | none | New tab/window opens PLC explorer or metrics | `implemented` | `P2` |
| `E-21` | Open embedded MST utility window | `Utilities -> MST Viewer` | `LOCAL-01` | none | none | none | `#win-mst-viewer` visible | `implemented` | `P1` |
| `E-22` | Embedded MST load by DID | `#mst-load-btn` / Enter | `MST-02`, `MST-03` | `GET /api/mst/tree/{did}`, `GET /api/mst/stats/{did}` | none | Tree payload + stats payload | MST window shows tree, stats, status text | `implemented` | `P1` |
| `E-23` | Embedded MST expand/collapse/export | MST utility buttons | `LOCAL-05` | none (export local from loaded data) | none | local `currentMstData` | Node expansion state and JSON download update | `implemented` | `P2` |
| `E-24` | Open login dialog and resolve handle hint | `File -> Login…`, handle blur | `LOCAL-01`, `AUTH-01` | `GET /xrpc/com.atproto.identity.resolveHandle` | none | `did` or resolve failure | Login dialog status message updated | `implemented` | `P1` |
| `E-25` | Start OAuth sign-in from Explore | login submit | `AUTH-02` | browser redirect to `/oauth/authorize` | none | redirect only | Browser leaves page for OAuth flow | `implemented` | `P0` |
| `E-26` | Process OAuth callback in Explore | callback return to `/?oauth_callback=1` | `AUTH-03` | `POST /oauth/token` with DPoP | DPoP proof | `access_token`, `sub` | Session established, login UI updates, poster enabled | `implemented` | `P0` |
| `E-27` | Logout Explore session | `File -> Logout` | `LOCAL-01` | local token clear | prior session required | none | Session/menu/admin state reset | `implemented` | `P1` |
| `E-28` | Open post composer and load recent posts | `File -> New Post` | `AUTH-06` | `GET /xrpc/com.atproto.repo.listRecords` | none (public read path) | `records[]` | Poster window opens with recent post list | `implemented` | `P1` |
| `E-29` | Test authenticated session in poster | `#poster-test-btn` | `AUTH-04` | `GET /xrpc/com.atproto.server.getSession` | DPoP token | session JSON | Poster result area shows auth/session payload | `implemented` | `P1` |
| `E-30` | Create post in poster | `#poster-post-btn` | `AUTH-05` | `POST /xrpc/com.atproto.repo.createRecord` | DPoP token | success `uri` or error | Post result shown, fields reset on success | `implemented` | `P0` |

## Admin Surface (Unified Panel + Legacy Admin Windows)
| ID | User-visible action | Entry route / trigger | Contract ID(s) | Backend call(s) | Auth | Response dependency (fields consumed) | Expected UI state transition | Status | Severity |
|---|---|---|---|---|---|---|---|---|---|
| `A-01` | Admin login dialog submit | `#admin-login-btn` / Enter | `ADM-01` | `POST /admin/login` | none | `token` | Admin token stored; admin menu/panel enabled | `implemented` | `P0` |
| `A-02` | Open admin panel | `Admin -> Invite Codes` / `Admin -> Moderation` | `ROUTE-02`, `LOCAL-01` | Dynamic module loads from `/admin-ui/js/*.js` | admin token required | AdminUI module bundle availability | `#win-admin-panel` opens on selected tab | `implemented` | `P0` |
| `A-03` | Switch admin tabs | tab click | `LOCAL-01` | none directly | admin token required | none | Active tab/content panel changes | `implemented` | `P1` |
| `A-04` | Load overview stats | Overview tab load | `ADM-02` | `GET /admin/stats` | bearer admin token | account/repo/blob/report/invite counters | Overview cards and sections render | `implemented` | `P0` |
| `A-05` | Load/search/select accounts | Accounts tab load + search input | `ADM-03`, `LOCAL-04` | `GET /admin/users` | bearer admin token | `users[]` | Accounts list populates and detail pane updates | `implemented` | `P0` |
| `A-06` | Disable account invite capability | account action button | `ADM-10` | `POST /xrpc/com.atproto.admin.disableAccountInvites` | bearer admin token | success/error only | Account status updates after refresh | `implemented` | `P0` |
| `A-07` | Enable account invite capability | account action button | `ADM-11` | `POST /xrpc/com.atproto.admin.enableAccountInvites` | bearer admin token | success/error only | Account status updates after refresh | `implemented` | `P0` |
| `A-08` | Show account info popup | `Get Info...` action | `LOCAL-01` | none | admin token required | account fields already loaded | Info popup rendered from selected account | `implemented` | `P2` |
| `A-09` | Load/filter moderation reports | Reports tab + status filter | `ADM-08`, `LOCAL-04` | `GET /xrpc/com.atproto.admin.getModerationReports` | bearer admin token | `reports[]`, `status`, `reason_type` | Reports list refreshes with filter | `implemented` | `P0` |
| `A-10` | Resolve or dismiss report | report action button | `ADM-09` | `POST /xrpc/com.atproto.admin.resolveReport` | bearer admin token | success/error | Report status transitions and list reloads | `implemented` | `P0` |
| `A-11` | Load system status panel | System tab load | `ADM-02` | `GET /admin/stats` | bearer admin token | status/invite summary counters | System status and invite stats sections render | `implemented` | `P1` |
| `A-12` | Load audit log preview | System tab load | `ADM-07` | `GET /admin/audit-log` | bearer admin token | `entries[]` | Preview list renders with recent actions | `implemented` | `P1` |
| `A-13` | Open full audit modal and filter | `View Full Audit Log...` + filter select | `ADM-07`, `LOCAL-04` | `GET /admin/audit-log` | bearer admin token | `entries[]` | Modal opens and table/filter updates | `implemented` | `P1` |
| `A-14` | Open invite manager from system tab | `Manage Invite Codes...` | `LOCAL-01` | none directly | bearer admin token | none | Legacy invite window opens | `implemented` | `P2` |
| `A-15` | Legacy invite list load | legacy invite window | `ADM-04` | `GET /admin/invites` | bearer admin token | `invites[]` | Invite table populated | `implemented` | `P1` |
| `A-16` | Legacy invite generate | `Generate Code` | `ADM-05` | `POST /admin/invites` | bearer admin token | returned `code` | Result banner and refreshed invite table | `implemented` | `P1` |
| `A-17` | Legacy invite disable | row `Disable` button | `ADM-06` | `POST /admin/invites/disable` | bearer admin token | success/error only | Invite row status updates after refresh | `implemented` | `P1` |
| `A-18` | Legacy moderation list load | legacy moderation window | `ADM-03` | `GET /admin/users` | bearer admin token | `users[]` | Moderation table populated | `implemented` | `P1` |
| `A-19` | Legacy moderation disable/enable actions | legacy moderation row action | `ADM-10`, `ADM-11` | admin XRPC account invite toggles | bearer admin token | success/error only | Moderation row status updates after refresh | `implemented` | `P1` |

## Standalone MST Viewer Surface (`/mst-viewer`)
| ID | User-visible action | Entry route / trigger | Contract ID(s) | Backend call(s) | Auth | Response dependency (fields consumed) | Expected UI state transition | Status | Severity |
|---|---|---|---|---|---|---|---|---|---|
| `M-01` | Open standalone MST Viewer shell | `GET /mst-viewer` | `ROUTE-03` | none (shell + assets) | none | page shell elements render | Standalone MST app visible | `implemented` | `P1` |
| `M-02` | Load/search/select account | init + account click + filter input | `MST-01`, `LOCAL-04` | `GET /api/mst/accounts` | none | `accounts[]` with `did`,`handle` | Account list updates and selected account highlights | `implemented` | `P1` |
| `M-03` | Load tree and stats for selected account | account select | `MST-02`, `MST-03` | `GET /api/mst/tree/{did}`, `GET /api/mst/stats/{did}` | none | tree payload + stats payload | Tree/list and stats panes render current DID | `implemented` | `P1` |
| `M-04` | Switch tree/list mode | view mode radio | `LOCAL-01` | none directly | none | existing loaded data | Visible pane swaps tree/list and re-renders | `implemented` | `P2` |
| `M-05` | Export MST in JSON/DOT/SVG | export buttons | `MST-04` | `GET /api/mst/export/{did}?format=...` | none | download payload or JSON content message | File download or export status feedback | `implemented` | `P1` |
| `M-06` | Tree zoom controls | zoom buttons | `LOCAL-01` | none | none | local renderer state | Zoom in/out/reset updates current tree viewport | `implemented` | `P2` |

## OAuth Demo Surface (`/oauth-demo`)
| ID | User-visible action | Entry route / trigger | Contract ID(s) | Backend call(s) | Auth | Response dependency (fields consumed) | Expected UI state transition | Status | Severity |
|---|---|---|---|---|---|---|---|---|---|
| `O-01` | Open OAuth demo shell | `GET /oauth-demo` | `ROUTE-04` | none (shell + assets) | none | page sections (`login`, `callback`, `session`) | OAuth demo landing screen visible | `implemented` | `P1` |
| `O-02` | Start OAuth login | `#btn-login` | `AUTH-02` | browser redirect to `/oauth/authorize` | none | redirect flow only | Browser navigates to authorization endpoint | `implemented` | `P0` |
| `O-03` | Exchange callback code for tokens | callback handler on `/oauth-demo/callback` | `AUTH-03` | `POST /oauth/token` with DPoP proof | DPoP | `access_token`, `sub` | Session section opens with token JSON | `implemented` | `P0` |
| `O-04` | Test authenticated API call | `#btn-test-session` | `AUTH-04` | `GET /xrpc/com.atproto.server.getSession` | DPoP token | session JSON including DID | API result panel shows session payload | `implemented` | `P0` |
| `O-05` | Create feed post from demo | `#btn-create-post` | `AUTH-05` | `POST /xrpc/com.atproto.repo.createRecord` | DPoP token | created record response or error | Post result panel shows success/error JSON | `implemented` | `P0` |
| `O-06` | List public records for stored DID | `#btn-list-records` | `AUTH-06` | `GET /xrpc/com.atproto.repo.listRecords` | none (public query) | `records[]` | Records panel populated or error text | `implemented` | `P1` |
| `O-07` | Logout demo session | `#btn-logout` | `LOCAL-01` | local token clear + redirect | prior session required | none | Session cleared and browser redirected to `/oauth-demo/` | `implemented` | `P1` |

## Global Local-Only Chrome
| ID | User-visible action | Entry route / trigger | Contract ID(s) | Backend call(s) | Auth | Response dependency | Expected UI state transition | Status | Severity |
|---|---|---|---|---|---|---|---|---|---|
| `L-01` | Window close/open/title updates | close buttons + `openWindow()` | `LOCAL-01` | none | none | none | Local window visibility and active section update | `unmapped` | `P2` |
| `L-02` | Drag desktop windows / z-order | title-bar drag | `LOCAL-03` | none | none | none | Window moves and is brought to front | `unmapped` | `P2` |
| `L-03` | Status clock tick | interval timer | `LOCAL-06` | none | none | system time | Status clock updates each second | `unmapped` | `P2` |

## Parity Gate Rule
Cutover is blocked until every row above reaches `verified`.

## Matrix Validation
1. Every row has non-empty: contract ID, backend call entry (or explicit `none`), auth mode, status, severity.
2. No row contains `TBD`.
3. Every contract ID resolves to `docs/plans/objective-j-ui/phase-1-api-contract.md`.
4. Acceptance check for each row is defined by its `Expected UI state transition` cell.
