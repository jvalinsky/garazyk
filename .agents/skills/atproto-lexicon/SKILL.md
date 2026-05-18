---
name: atproto-lexicon
description: "Use when authoring, validating, evolving, or invoking AT Protocol lexicons, records, and XRPC methods in Rust, TypeScript, or Go. Covers NSIDs, defs, $type dispatch, record validation, strongRefs, blob refs, AT-URIs, XRPC HTTP and WebSocket wire formats, firehose consumers, code generation, and backward-compatible schema changes."
---

# AT Protocol Lexicon + XRPC + Records

An AT Protocol **lexicon** is a JSON document that declares the shape of one record type or one XRPC method. Every record's `$type`, every XRPC path, and every `ref` between them ties back to an NSID. The lexicon is the protocol's type system; validation against it is the contract between clients, servers, and the repository layer.

This skill routes to per-language guides for Rust, TypeScript, and Go, sitting on top of a language-neutral spec in `references/shared/`.

## Defaults

- **Lexicon doc** — `{lexicon: 1, id: <nsid>, revision?, defs: {...}}`. Primary types (`record`, `query`, `procedure`, `subscription`) live under `main`. Secondary types can use any name.
- **NSID** — reversed-DNS authority + name segment. ASCII only, 317 bytes max, name segment allows no hyphens. See `references/shared/nsid.md`.
- **`$type`** — required on every record. Bare NSID implies `#main`. Used for union dispatch. Missing `$type` = invalid record.
- **AT-URIs in records** — DIDs strongly preferred over handles for the authority. Query strings forbidden. See `references/shared/at-uri.md`.
- **strongRef** — `{uri, cid}` where `cid` is a **plain string**, not a `cid-link`. Common bug source.
- **Blob refs (modern)** — `{$type:"blob", ref:{$link:<cid>}, mimeType, size}`. Legacy `{cid, mimeType}` only accepted with an opt-in lenient flag.
- **XRPC wire** — `/xrpc/<nsid>` path. GET for queries, POST for procedures, WebSocket for subscriptions. Errors as `{error, message}`. Subscription frames are two concatenated DAG-CBOR objects per WS binary message.
- **Validation** — strict by default on write, lenient on read. `ALLOW_LEGACY_BLOB` and `ALLOW_LENIENT_DATETIME` are the typical lenient opt-ins.

Full normative rules: `references/shared/lexicon-spec.md`, `references/shared/nsid.md`, `references/shared/at-uri.md`, `references/shared/record-model.md`, `references/shared/xrpc-wire.md`, `references/shared/backward-compat.md`. Fixtures: `references/shared/test-vectors.md`. Cross-language differences: `references/shared/divergence-matrix.md`.

## Language detection

Before generating or reviewing any lexicon / XRPC / record code, determine the target language from project files or the file being edited:

- `Cargo.toml`, `*.rs`, any mention of `atproto-lexicon` / `atproto-client` / `atproto-record` / `atproto-jetstream` → **Rust** — read from `references/rust/`.
- `package.json`, `tsconfig.json`, `*.ts`, `*.tsx`, imports of `@atproto/lexicon` / `@atproto/xrpc` / `@atproto/xrpc-server` / `@atproto/api` / `@atproto/lex-cli` → **TypeScript** — read from `references/typescript/`. Also `*.js`/`*.jsx` when there is no `.ts` present.
- `go.mod`, `*.go`, imports of `github.com/bluesky-social/indigo/atproto/lexicon` / `atproto/data` / `xrpc` / `api/atproto` / `api/agnostic` / `events` → **Go** — read from `references/go/`.

Prefer the *file being edited* over the *repo root* when they disagree: a `.go` consumer inside a TypeScript monorepo still means Go for that task.

If multiple languages are present and the task does not point at one unambiguously, **ask which one applies**. Never mix lexicon libraries across languages in generated code.

If an unsupported language is detected (Python, Java, Swift, …), point the user at `references/shared/lexicon-spec.md`, `references/shared/record-model.md`, and `references/shared/xrpc-wire.md` for the wire format, and offer `indigo/atproto/lexicon` (Go) as the most complete reference implementation to transliterate from.

## Reading guide

For every lexicon / records / XRPC task:

1. Read the relevant `references/shared/*.md` first. They are short and define the rules your code must enforce.
2. Read the relevant task file in the detected language directory:
   - Authoring a new lexicon, loading into the catalog, codegen → `references/{lang}/authoring.md`
   - Validating records and XRPC payloads → `references/{lang}/validation.md`
   - Invoking XRPC methods, consuming subscriptions, server handlers → `references/{lang}/xrpc-client.md`
   - AT-URIs, TIDs, strongRef, blob refs, typed `$type` dispatch → `references/{lang}/records.md`
   - Library setup, public API at a glance, idioms → `references/{lang}/README.md`
3. Consult `references/shared/divergence-matrix.md` whenever porting between languages or reviewing cross-stack interop. The legacy-blob shape, `BlobRef`-class-vs-plain-object, and the Go two-stack (`data.Blob` vs. `lex/util.LexBlob`) split are the highest-frequency traps.

Always prefer the official library over hand-rolling: `atproto-lexicon` + `atproto-client` in Rust, `@atproto/lexicon` + `@atproto/xrpc` in TypeScript, `indigo/atproto/lexicon` + `indigo/xrpc` in Go.

## The conceptual stack

```
                       ┌──────────────────────────────┐
  Lexicon (JSON)  ───▶ │ {lexicon:1, id:<nsid>,       │
  authoring / resolve  │  revision, defs:{main,...}}  │
                       └──────────────────────────────┘
                                   │
                                   ▼
                       ┌──────────────────────────────┐
  Catalog  ──────────▶ │ Lexicons / BaseCatalog —     │
  (runtime)            │ resolves <nsid>[#def] → def  │
                       └──────────────────────────────┘
                                   │ validates ↓          ↓ schemas XRPC
                                   ▼                      ▼
                       ┌──────────────────────────────┐   ┌──────────────────────────────┐
  Record value ──────▶ │ {$type:<nsid>, ...fields...} │   │ XRPC transport               │
  (record def)         │ DAG-CBOR → CID stability     │   │ GET/POST/WS @ /xrpc/<nsid>  │
                       └──────────────────────────────┘   │ JSON in/out; frames on WS   │
                                                          └──────────────────────────────┘
```

Validation runs at both ends: on write (strict, reject unknowns) and on read (lenient, tolerate unknowns from older producers). The catalog is shared across both paths.

## Cross-language hazards to flag up front

High-frequency failure modes; full detail in `references/shared/divergence-matrix.md`:

- **strongRef `cid` is a string, not a cid-link.** Emitting `{$link: ...}` for `strongRef.cid` produces a different CID. See `references/shared/record-model.md §3`.
- **Blob shape divergence.** Modern `{$type:"blob", ref:{$link}, mimeType, size}` is the only shape for new writes. Legacy `{cid, mimeType}` is accepted on read only with `ALLOW_LEGACY_BLOB` / `AllowLegacyBlob` / equivalent.
- **`BlobRef` is a class in TypeScript.** Plain-object blobs fail `assertValidRecord`. Construct with `new BlobRef(cid, mime, size)`.
- **Go has two data-model stacks.** `atproto/data` (modern) and `lex/util` (legacy, still emitted by generated code). Convert at the boundary between validator and generated code.
- **`xrpc.Client.Do` arg order (Go).** `(ctx, kind, inpenc, method, params, body, out)` — `kind` before `method`. Easy to invert.
- **`@atproto/xrpc` `Subscription` export has moved.** Regrep `node_modules` on version bumps.
- **Closed vs. open unions.** Adding a ref to a closed union is breaking; open unions tolerate unknown `$type`. Default to open.
- **`$type` missing on a record.** Strict validators reject; lenient validators have nothing to dispatch on. Never omit.
- **Bluesky-domain records are out of scope.** `app.bsky.*` facets, richtext, embeds, threadgates — point users at the Bluesky appview or `@atproto/api` README rather than trying to cover them here.

## Optional MCP Tools

If available in this Codex session, prefer these MCP tools when the goal is to *compute* or *validate* rather than teach an implementation how:

- **`lexicon-garden`** → `describe_lexicon(nsid)`, `validate_lexicon(doc)`, `invoke_xrpc(method, params, input?)`, `create_record_cid(record)`, `transmogrify_record(record)`, `check_compatibility(old, new)`.
- **`atpmcp`** → `get_lexicon(nsid)`, `validate_lexicon_schema(doc)`, `validate_xrpc(method, params, input?)`, `get_record(uri)`, `invoke_xrpc(method, params, input?)`, `generate_tid()`, `create_record_cid(record)`, `parse_facets(text)`, `transmogrify_record(record)`.

For record-side helpers (TIDs, AT-URI parsing), prefer in-language libraries — see the per-language `records.md`. For lexicon authoring or compatibility review, `lexicon-garden` is the fastest way to validate without spinning up a stack.

## Directory layout

```
atproto-lexicon/
├── SKILL.md                          # this file — router
├── references/shared/
│   ├── lexicon-spec.md               # lexicon doc structure + validation rules
│   ├── nsid.md                       # NSID grammar and reserved prefixes
│   ├── at-uri.md                     # AT-URIs in records and refs
│   ├── record-model.md               # $type, strongRef, blob refs
│   ├── xrpc-wire.md                  # HTTP + WebSocket wire format
│   ├── backward-compat.md            # breaking-vs-non-breaking matrix
│   ├── test-vectors.md               # canonical fixtures
│   └── divergence-matrix.md          # cross-language differences
├── references/rust/
│   ├── README.md                     # atproto-lexicon / atproto-client setup
│   ├── authoring.md                  # BaseCatalog, load_directory, refs
│   ├── validation.md                 # validate_record, ValidateFlags, DataValue
│   ├── xrpc-client.md                # Auth::{None,DPoP,AppPassword}, atproto-jetstream
│   └── records.md                    # ATURI, Tid, strongRef, Blob, typed dispatch
├── references/typescript/
│   ├── README.md                     # @atproto/{lexicon,xrpc,xrpc-server,api,lex-cli}
│   ├── authoring.md                  # Lexicons, lex-cli gen-api
│   ├── validation.md                 # assertValidRecord, BlobRef class, ValidationError
│   ├── xrpc-client.md                # XrpcClient, AtpAgent, createServer, Subscription
│   └── records.md                    # AtUri, TID, BlobRef, strongRef
└── references/go/
    ├── README.md                     # indigo/atproto/lexicon + xrpc + events
    ├── authoring.md                  # BaseCatalog, LoadDirectory, lexgen
    ├── validation.md                 # ValidateRecord, ValidateFlags
    ├── xrpc-client.md                # xrpc.Client.Do, api/atproto, HandleRepoStream
    └── records.md                    # data.Blob vs lex/util.LexBlob, typed dispatch
```

## References

All reachable from this Codex skill folder. Listed here for quick grep:

- `references/shared/lexicon-spec.md`, `references/shared/nsid.md`, `references/shared/at-uri.md`, `references/shared/record-model.md`, `references/shared/xrpc-wire.md`, `references/shared/backward-compat.md`, `references/shared/test-vectors.md`, `references/shared/divergence-matrix.md`
- `references/rust/README.md`, `references/rust/authoring.md`, `references/rust/validation.md`, `references/rust/xrpc-client.md`, `references/rust/records.md`
- `references/typescript/README.md`, `references/typescript/authoring.md`, `references/typescript/validation.md`, `references/typescript/xrpc-client.md`, `references/typescript/records.md`
- `references/go/README.md`, `references/go/authoring.md`, `references/go/validation.md`, `references/go/xrpc-client.md`, `references/go/records.md`
