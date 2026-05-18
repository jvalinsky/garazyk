---
name: atproto-oauth
description: "Use when implementing, auditing, or debugging AT Protocol OAuth in Rust, TypeScript, or Go. Covers OAuth 2.1 profile flows, PAR, PKCE, DPoP proofs and nonces, client metadata, private_key_jwt, scopes and permission sets, session storage, refresh token races, BFF, SPA, and native client patterns."
---

# AT Protocol OAuth

AT Protocol OAuth is an **OAuth 2.1** profile with mandatory **PKCE (S256)**, **PAR**, **DPoP**, and URL-based dynamic client registration via a published **client metadata document**. No `client_secret` — confidential clients authenticate to the token endpoint with a `private_key_jwt` assertion (ES256). Public / SPA / native clients authenticate by DPoP proof alone.

This skill routes to per-language guides for Rust, TypeScript, and Go, sitting on top of a language-neutral spec in `references/shared/`.

## Defaults

- **`client_id` is a URL.** It resolves to a JSON metadata document the AS fetches on demand. The URL path, host, and protocol must match byte-for-byte between registration, PAR, and authorize.
- **Every access token is DPoP-bound.** `dpop_bound_access_tokens: true` is required in client metadata; every resource request carries a fresh DPoP proof with `ath = SHA-256(access_token)` and a per-origin `nonce`.
- **PAR is required.** You push the authorize request to `pushed_authorization_request_endpoint` and redirect the user to `{AS}/oauth/authorize?client_id=...&request_uri=urn:ietf:params:oauth:request_uri:...`. Query parameters never hit the user-agent.
- **Scopes start with `atproto`.** All flows must request `atproto` as the first scope. Further scopes are layered on: `transition:generic`, `account:email?action=read`, `rpc:app.bsky.feed.*`, `include:<permission-set>`, etc.
- **The session belongs to the DID.** `sub` in the token response is a DID. Handles may change; DIDs don't. Persist by DID.
- **Identity verification is mandatory**: `sub` → DID document → `#atproto_pds` → matches the PDS you discovered → `authorization_servers[0]` → matches the AS you talked to. Skip this step = CSRF window.

Full normative rules: `references/shared/spec.md`, `references/shared/flows.md`, `references/shared/client-metadata.md`, `references/shared/dpop.md`, `references/shared/scopes.md`, `references/shared/sessions.md`, `references/shared/security-requirements.md`. Fixtures: `references/shared/test-vectors.md`. Common failures: `references/shared/troubleshooting.md`. Cross-language differences: `references/shared/divergence-matrix.md`.

## Language detection

Before generating or reviewing any OAuth code, determine the target language from project files or the file being edited:

- `Cargo.toml`, `*.rs`, mention of `atproto-oauth` / `atproto-identity` / `atproto-oauth-aip` → **Rust** — read from `references/rust/`.
- `package.json`, `tsconfig.json`, `*.ts`, `*.tsx`, imports of `@atproto/oauth-client-node` / `@atproto/oauth-client-browser` / `@atproto/oauth-client` / `@atproto/jwk-jose` → **TypeScript** — read from `references/typescript/`. Also `*.js`/`*.jsx` when there's no `.ts`.
- `go.mod`, `*.go`, imports of `github.com/bluesky-social/indigo/atproto/auth/oauth` → **Go** — read from `references/go/`.

Prefer the *file being edited* over the *repo root* when they disagree.

If multiple languages are present and the task doesn't point at one unambiguously, **ask which one applies**. Never mix OAuth libraries across languages in generated code.

If an unsupported language is detected (Python, Java, Swift, Kotlin, …), point the user at `references/shared/spec.md`, `references/shared/flows.md`, and `references/shared/dpop.md` for the wire format, and offer the TypeScript `@atproto/oauth-client-node` source as the most complete reference implementation to transliterate from.

## Client-type detection

Before picking a file, also determine what **kind** of client is being built:

| Kind                 | Clue                                                | Route to…                                                |
| -------------------- | --------------------------------------------------- | -------------------------------------------------------- |
| Confidential (BFF)   | Has server-side Rust/TS/Go code + a signing key    | Node: `references/typescript/*.md` with `NodeOAuthClient`. Rust/Go: only option. |
| Public (SPA)         | Browser-only; no server; tokens land in the browser | **TypeScript only** → `references/typescript/*.md` with `BrowserOAuthClient`. Rust and Go don't ship a browser client. |
| Public (native)      | Desktop / mobile app with custom-scheme redirects   | TypeScript (`NodeOAuthClient` with `token_endpoint_auth_method: none`). Rust can do it manually. Go: unsupported. |
| AS or resource server | Implementing the server side (rare)                 | Rust only (`references/rust/dpop.md` §server-side). TS and Go don't ship validators. |

When in doubt, **default to confidential BFF** — it's the recommended pattern for any app that has a backend, and it keeps secrets out of the browser.

## Reading guide

For every OAuth task:

1. Read the relevant `references/shared/*.md` first. They define the rules your code must enforce. Usually `references/shared/spec.md` + one of `references/shared/flows.md` / `references/shared/dpop.md` / `references/shared/sessions.md` / `references/shared/client-metadata.md` / `references/shared/scopes.md`.
2. Read the relevant task file in the detected language directory:
   - Publishing `/oauth-client-metadata.json` + `/jwks.json` → `references/{lang}/client-metadata.md`
   - Authorize / callback / refresh / logout flow → `references/{lang}/flows.md`
   - DPoP minting + nonce retry + server-side validation → `references/{lang}/dpop.md`
   - Pre-flow state, sessions, refresh-race mitigation → `references/{lang}/sessions.md`
   - Library setup, public API, idioms → `references/{lang}/README.md`
3. Consult `references/shared/divergence-matrix.md` whenever porting between languages or reviewing cross-stack interop.
4. Consult `references/shared/troubleshooting.md` when debugging a specific failure (`invalid_dpop_proof`, `invalid_grant`, callback cookie missing, etc.).
5. Before publishing a metadata doc, run `scripts/validate_client_metadata.py` against the served URL.

Always prefer the official library over hand-rolling: `atproto-oauth` in Rust, `@atproto/oauth-client-*` in TypeScript, `indigo/atproto/auth/oauth` in Go. The protocol is small but unforgiving — every byte of the wire matters.

## The conceptual stack

```
  ┌─────────────────────────────────────────────┐
  │ Client metadata document (JSON at client_id)│  ← published by you
  │ { client_id, redirect_uris, jwks_uri, … }   │
  └─────────────────────────────────────────────┘
               │ fetched once by AS
               ▼
  ┌─────────────────────────────────────────────┐
  │ PAR → /oauth/par                            │  ← flow starts
  │ POST client_assertion + DPoP + PKCE + scope │
  │    ↓                                        │
  │ request_uri: urn:ietf:params:oauth:request_uri:…│
  └─────────────────────────────────────────────┘
               │ redirect user agent to authorize
               ▼
  ┌─────────────────────────────────────────────┐
  │ User logs in at AS's UI, grants consent     │
  │    ↓                                        │
  │ Redirect back: ?code=…&state=…&iss=…        │
  └─────────────────────────────────────────────┘
               │ callback
               ▼
  ┌─────────────────────────────────────────────┐
  │ /oauth/token (code exchange)                 │
  │ POST code + PKCE verifier + assertion + DPoP │
  │    ↓                                        │
  │ { access_token, refresh_token, sub: did,    │
  │   aud: pds_url, expires_in: 3600 }          │
  └─────────────────────────────────────────────┘
               │ persist session by DID
               ▼
  ┌─────────────────────────────────────────────┐
  │ Resource request to PDS                     │
  │ Authorization: DPoP <access_token>          │
  │ DPoP: <proof with ath + nonce>              │
  └─────────────────────────────────────────────┘
```

## Cross-language hazards to flag up front

High-frequency failure modes; full detail in `references/shared/divergence-matrix.md`:

- **Refresh race** — Two concurrent requests both refresh, one invalidates the other's refresh token, dead session. TS has `NodeRequestLock` built in; Rust and Go leave it to the caller. Every production BFF needs a per-DID lock (Redis/Postgres advisory or in-process mutex).
- **`htu` normalization** — Query strings and fragments must be stripped before minting a DPoP proof; default ports must be elided. TS does this automatically; Rust and Go don't. `invalid_dpop_proof` with identical-looking URLs = suspect this.
- **Rust's hard-coded `ES256` header** — `auth_dpop()` writes `alg: ES256` into the JWT header even when the key is P-384. Non-P-256 keys need `dpop::mint` with a custom header.
- **Rust leaks private JWK components** — `jwk::generate()` on a private `KeyData` serializes the `d` field unless the caller runs `to_public(&key)` first. TS and Go strip automatically.
- **Go is BFF-only** — No SPA support. No native client support in `indigo`. If the task is browser OAuth, route to TypeScript regardless of repo language.
- **`SameSite=Strict` kills the callback** — OAuth redirects are cross-origin top-level navigations; `Strict` drops the cookie and the callback handler can't find pre-flow state. Always `Lax` on session cookies.
- **Public clients have a 14-day refresh cap, not 180.** Silent until day 15 when `invalid_grant` suddenly starts failing.

## Optional MCP Tools

If available in this Codex session, prefer these MCP tools when the goal is to validate or compute rather than teach an implementation how:

- **`lexicon-garden`** → `discover_permission_sets`, `check_compatibility` (scope tooling), `describe_me` (authorize the session).
- **`atpmcp`** → `resolve_handle_to_did`, `resolve_identity` (identity lookups — needed for PDS/AS discovery).

For scope authoring and permission-set design, the normative source is <https://atproto.com/specs/permission> and <https://atproto.com/guides/permission-sets>.

## Validator script

`scripts/validate_client_metadata.py` checks a served client metadata document for the invariants in `references/shared/test-vectors.md` §V5. Run it in CI against your deployed URL:

```
$ python scripts/validate_client_metadata.py https://app.example.com/oauth-client-metadata.json
```

Catches mutations like missing `dpop_bound_access_tokens`, wrong `token_endpoint_auth_signing_alg`, inline `jwks` containing private `d` field, `http://` redirect outside loopback, etc.

Exit codes: `0` = document passes every invariant; `1` = at least one invariant failed (reasons printed to stdout); `2` = usage error (missing URL, network failure, non-JSON response). The script is stdlib-only and makes a single HTTP GET — no runtime dependencies, safe for CI sandboxes.

## Directory layout

```
atproto-oauth/
├── SKILL.md                          # this file — router
├── scripts/
│   └── validate_client_metadata.py   # CI validator for metadata doc
├── references/shared/
│   ├── spec.md                       # OAuth 2.1 + AT Proto profile: entities, invariants
│   ├── flows.md                      # byte-level wire content for each step
│   ├── client-metadata.md            # metadata document fields, JWKS rules
│   ├── dpop.md                       # RFC 9449 profile
│   ├── scopes.md                     # scope grammar, permission sets
│   ├── sessions.md                   # pre-flow state + post-flow session rules
│   ├── security-requirements.md      # cookies, keys, tokens, SSRF
│   ├── troubleshooting.md            # common failures and diagnosis
│   ├── test-vectors.md               # fixtures for conformance
│   └── divergence-matrix.md          # cross-language differences
├── references/rust/
│   ├── README.md                     # atproto-oauth setup
│   ├── client-metadata.md            # jwk::generate + Axum handlers
│   ├── flows.md                      # oauth_init / oauth_complete / oauth_refresh
│   ├── dpop.md                       # auth_dpop / request_dpop / DpopRetry / validate_dpop_jwt
│   └── sessions.md                   # OAuthRequestStorage + custom session abstraction + refresh race
├── references/typescript/
│   ├── README.md                     # @atproto/oauth-client-* setup
│   ├── client-metadata.md            # client.clientMetadata + client.jwks + JoseKey
│   ├── flows.md                      # authorize / callback / restore / revoke + BrowserOAuthClient
│   ├── dpop.md                       # invisible fetchHandler DPoP + per-origin nonce cache
│   └── sessions.md                   # StateStore / SessionStore / NodeRequestLock + IndexedDB SPA
└── references/go/
    ├── README.md                     # indigo/atproto/auth/oauth setup
    ├── client-metadata.md            # cfg.ClientMetadata() + cfg.PublicJWKS()
    ├── flows.md                      # StartAuthFlow / ProcessCallback / ResumeSession / Logout
    ├── dpop.md                       # NewAuthDPoP + automatic ClientSession DPoP
    └── sessions.md                   # ClientAuthStore + refresh race (caller-owned)
```

## References

All reachable from this Codex skill folder. Listed here for quick grep:

- `references/shared/spec.md`, `references/shared/flows.md`, `references/shared/client-metadata.md`, `references/shared/dpop.md`, `references/shared/scopes.md`, `references/shared/sessions.md`, `references/shared/security-requirements.md`, `references/shared/troubleshooting.md`, `references/shared/test-vectors.md`, `references/shared/divergence-matrix.md`
- `references/rust/README.md`, `references/rust/client-metadata.md`, `references/rust/flows.md`, `references/rust/dpop.md`, `references/rust/sessions.md`
- `references/typescript/README.md`, `references/typescript/client-metadata.md`, `references/typescript/flows.md`, `references/typescript/dpop.md`, `references/typescript/sessions.md`
- `references/go/README.md`, `references/go/client-metadata.md`, `references/go/flows.md`, `references/go/dpop.md`, `references/go/sessions.md`

Upstream normative sources:

- <https://atproto.com/specs/oauth> — AT Proto OAuth profile
- <https://atproto.com/specs/permission> — scopes and permission sets
- <https://atproto.com/guides/auth>, <https://atproto.com/guides/about-oauth>, <https://atproto.com/guides/oauth-patterns>, <https://atproto.com/guides/sdk-auth>, <https://atproto.com/guides/permission-requests>, <https://atproto.com/guides/permission-sets> — conceptual guides
- RFC 9449 (DPoP), RFC 7636 (PKCE), RFC 9126 (PAR), RFC 7523 (JWT client auth), RFC 8414 (server metadata), RFC 9207 (`iss`), OAuth 2.1 draft
