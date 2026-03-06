---
title: Objective-J UI Migration - Phase 1 API Contract Freeze
---

# Objective-J UI Migration - Phase 1 API Contract Freeze

## Contract Scope
This document freezes the API/route contract used by the Objective-J migration.

Locked constraints:
1. No `/api/v2/ui` backend will be introduced.
2. Existing backend payloads remain source-of-truth.
3. Any shape adaptation happens in Objective-J client adapters.
4. All parity-matrix actions reference one of the contract IDs below.

## Route Contracts
| Contract ID | Route | Method | Auth | Behavior | Notes |
|---|---|---|---|---|---|
| `ROUTE-01` | `/` (legacy default) | `GET` | none | Served by `ExploreHandler` through wildcard fallback; returns legacy Explore shell. | Remains default until final cutover. |
| `ROUTE-02` | `/admin-ui/*` | `GET` | none | Serves static admin panel JS/CSS assets used by legacy Explore dynamic imports. | Must remain during migration. |
| `ROUTE-03` | `/mst-viewer` and `/mst-viewer/*` | `GET` | none | Serves standalone MST Viewer app shell/assets. | Existing production feature. |
| `ROUTE-04` | `/oauth-demo` and `/oauth-demo/*` | `GET` | none | Serves OAuth demo shell/assets including callback URL path. | Existing production feature. |
| `ROUTE-05` | `/ui` and `/ui/*` | `GET` | none | New Objective-J route namespace to be added in Phase 2. | Migration route, non-default until cutover. |

## Explore API Contracts (`/api/pds/*`)
Scope note: this catalog includes only endpoints consumed by legacy parity actions. Endpoints present server-side but not consumed by legacy UI are intentionally excluded from Phase 1 parity contracts.

| Contract ID | Method + path | Required query/body | Auth | Success fields consumed by UI | Error behavior observed |
|---|---|---|---|---|---|
| `EXP-01` | `GET /api/pds/accounts` | none | none | `accounts[]` with `did`, `handle` for left account list. | Fallback returns `{ accounts: [] }` on failure. |
| `EXP-02` | `GET /api/pds/lookup` | `did` or `handle` | none | `did`, optional `handle` used to focus selection/open DID view. | `{ error }` when missing params or not found. |
| `EXP-03` | `GET /api/pds/did` | `did` | none | DID document JSON; `id`, `alsoKnownAs`, `verificationMethod[]`, `service[]` rendered in summary/detail. | `{ error }` for missing/failed fetch. |
| `EXP-04` | `GET /api/pds/plc-log` | `did` | none | PLC operations array rendered timeline-style (`entry.op`, `cid`, `createdAt`). | `{ error }` for missing/failed fetch. |
| `EXP-05` | `GET /api/pds/describe` | `did` | none | Repo description with `collections[]` used for collection browser. | `{ error, did }` when describe fails. |
| `EXP-06` | `GET /api/pds/records` | `did`, `collection`; optional `limit`, `cursor` | none | `records[]`, `cursor`; each record uses `uri`, `rkey`, `cid`, `value`. | `{ error, records: [] }` on failure. |
| `EXP-07` | `GET /api/pds/record` | `uri` | none | Full record object for detail pane; UI branches on `$type`. | `{ error, uri }` when invalid/missing/not found. |
| `EXP-10` | `GET /api/pds/feed-posts` | `did`; optional `limit`, `cursor` | none | `posts[]` with `author`, `record.text`, `record.createdAt`, `record.reply`, `record.embed`. | `{ error, posts: [] }` on failure. |
| `EXP-11` | `GET /api/pds/feed-likes` | `did`; optional `limit`, `cursor` | none | `likes[]` with `subject.uri`, `subject.cid`, actor metadata, `createdAt`. | `{ error, likes: [] }` on failure. |
| `EXP-12` | `GET /api/pds/feed-reposts` | `did`; optional `limit`, `cursor` | none | `reposts[]` with subject + author metadata, `createdAt`. | `{ error, reposts: [] }` on failure. |
| `EXP-13` | `GET /api/pds/graph-follows` | `did`; optional `limit`, `direction` | none | `actors[]` with `did`, `handle`, `displayName`, `avatar`, `createdAt`. | `{ error, actors: [] }` on failure. |
| `EXP-14` | `GET /api/pds/actor-profile` | `did` | none | `did`, `handle`, `displayName`, `description`, `avatar`, `banner`, `followersCount`, `followsCount`, `postsCount`, `createdAt`. | `{ error }` on missing/failure. |
| `EXP-15` | `GET /api/pds/docs` | none | none | HTML API docs page linked from PDS menu. | 404/JSON error via handler fallback when unavailable. |

## OAuth + Session Contracts
| Contract ID | Method + path | Required query/body | Auth | Success fields consumed by UI | Error behavior observed |
|---|---|---|---|---|---|
| `AUTH-01` | `GET /xrpc/com.atproto.identity.resolveHandle` | `handle` | none | `did` used by login dialogs to show resolve status. | Non-200 treated as resolve failure by UI. |
| `AUTH-02` | `GET /oauth/authorize` | OAuth params (`client_id`, `redirect_uri`, `response_type=code`, `scope`, `state`, PKCE fields, `login_hint`) | none | Browser redirect to auth flow. | OAuth error redirect or server error response. |
| `AUTH-03` | `POST /oauth/token` | `grant_type=authorization_code`, `code`, `redirect_uri`, `client_id`, `code_verifier` | DPoP proof header required by demo/poster flows | `access_token`, `sub` used to persist session and DID. | OAuth error JSON (`error`, `error_description`). |
| `AUTH-04` | `GET /xrpc/com.atproto.server.getSession` | none | `Authorization: Bearer` or `Authorization: DPoP <token>` depending client flow | Session info; `did` and `isAdmin` are consumed in legacy UI. | 401 causes logout/prompt-login flow. |
| `AUTH-05` | `POST /xrpc/com.atproto.repo.createRecord` | JSON body with `repo`, `collection=app.bsky.feed.post`, `record` | DPoP token in poster/oauth-demo flows | Created post metadata (`uri`, etc.) used for success feedback. | Non-2xx JSON with `error`/`message`. |
| `AUTH-06` | `GET /xrpc/com.atproto.repo.listRecords` | `repo`, `collection`, optional `limit` | none for public records in demo; can also be called authenticated elsewhere | `records[]` shown in poster recent posts and oauth demo public list. | Non-200 handled as empty/error UI state. |

## Admin Contracts
| Contract ID | Method + path | Required query/body | Auth | Success fields consumed by UI | Error behavior observed |
|---|---|---|---|---|---|
| `ADM-01` | `POST /admin/login` | JSON `{ password }` | none | Returns `token`; stored in `sessionStorage.admin_token`. | 400/401 with `{ error }`. |
| `ADM-02` | `GET /admin/stats` | none | `Bearer <admin_token>` | Dashboard/system cards consume counters (`accounts_total`, `repos_total`, `records_total`, `blobs_total`, invite/report metrics). | 401 triggers re-login; other failures show error banners. |
| `ADM-03` | `GET /admin/users` | none | bearer admin token | `users[]` with `did`, `handle`, `email`, `deactivated`, `invite_enabled`, `created_at`. | 401 or JSON `{ error }`. |
| `ADM-04` | `GET /admin/invites` | none | bearer admin token | `invites[]` for invite table/list (`code`, `created_by`, `uses`, `max_uses`, `disabled`, `created_at`). | 401 or `{ error }`. |
| `ADM-05` | `POST /admin/invites` | JSON `{ forAccount, usesAvailable }` (legacy client naming) | bearer admin token | New invite `code` shown in result panel. | 400/500 with `{ error }`. |
| `ADM-06` | `POST /admin/invites/disable` | JSON `{ code }` | bearer admin token | Success message + refresh invite list. | 400/500 with `{ error }`. |
| `ADM-07` | `GET /admin/audit-log` | Optional filters expected by client via query string | bearer admin token | `entries[]` used for preview/modal audit table. | Current handler primarily parses body; query-based filter behavior is limited and must be normalized client-side until backend fix. |
| `ADM-08` | `GET /xrpc/com.atproto.admin.getModerationReports` | Optional query filters (`status`, `reasonType`, `subjectDid`, `reportedBy`, `limit`, `cursor`) | bearer admin token | `reports[]` consumed by moderation queue and detail pane. | Non-200 -> report load error in panel. |
| `ADM-09` | `POST /xrpc/com.atproto.admin.resolveReport` | JSON `{ id, status, notes }` | bearer admin token | Success triggers moderation list refresh. | Non-200 with JSON error/message. |
| `ADM-10` | `POST /xrpc/com.atproto.admin.disableAccountInvites` | JSON `{ did }` | bearer admin token | Used in admin accounts and legacy moderation window. | Non-200 with error/message. |
| `ADM-11` | `POST /xrpc/com.atproto.admin.enableAccountInvites` | JSON `{ did }` | bearer admin token | Used in admin accounts and legacy moderation window. | Non-200 with error/message. |

## MST Contracts
| Contract ID | Method + path | Required query/body | Auth | Success fields consumed by UI | Error behavior observed |
|---|---|---|---|---|---|
| `MST-01` | `GET /api/mst/accounts` | none | none | `accounts[]` with `did`, `handle` for standalone MST list. | `{ error }` or empty list fallback. |
| `MST-02` | `GET /api/mst/tree/{did}` | path `did` | none | Tree JSON (`rootCID`, `nodes[]` or equivalent) rendered in tree/list viewers. | `{ error, did }` on not found/serialization issues. |
| `MST-03` | `GET /api/mst/stats/{did}` | path `did` | none | Stats JSON for node/leaf/depth and related metrics. | `{ error, did }` on not found/failure. |
| `MST-04` | `GET /api/mst/export/{did}?format=json|dot|svg` | path `did`, query `format` | none | JSON and DOT as downloadable payloads; SVG currently returns DOT content wrapper JSON (`format`, `content`, `message`). | 400 `{ error, format }` for invalid format. |

## Local UI Contracts (No Backend)
| Contract ID | Contract | Behavior locked for migration |
|---|---|---|
| `LOCAL-01` | Window/section routing | Opening/closing document sections and utility windows updates only local view state. |
| `LOCAL-02` | Rendered/JSON toggles | Record/feed/profile cards toggle between rendered and raw JSON without API round-trip. |
| `LOCAL-03` | Drag + z-index behavior | Desktop windows remain draggable with front-most z-order updates. |
| `LOCAL-04` | Search/filter local transforms | Admin account search and report/audit filters perform client-side filtering over loaded data unless endpoint filtering is explicitly validated. |
| `LOCAL-05` | Embedded MST expand/collapse/export | Expand/collapse is local DOM state; embedded export is client-generated from last loaded payload. |
| `LOCAL-06` | Status/clock UI chrome | Status clock and status-bar text updates are local timer/UI behavior. |

## Normalization Boundary (Locked)
1. Objective-J client adapters normalize payload shape, null/default handling, and status banner behavior.
2. Server endpoint payloads are not altered in Phase 2 to satisfy Objective-J UI ergonomics.
3. Any backend mismatch discovered during implementation is logged as an explicit backlog item, not silently patched into a new API namespace.

## Contract Validation Checklist
1. Every parity-matrix row references at least one contract ID in this document.
2. All contracts include auth mode and expected error path.
3. All contracts specify fields that existing UI actually consumes.
