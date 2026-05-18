---
name: atproto-repository
description: "Use when constructing, parsing, exporting, importing, diffing, or signature-validating AT Protocol repositories in Rust, TypeScript, or Go. Covers CAR v1, MST nodes, DRISL canonical DAG-CBOR, commit records, signing bytes, commit signatures, record placement, firehose repo events, block stores, and CID mismatch debugging."
---

# AT Protocol Repository

An AT Protocol **repository** is a single account's entire record store, addressed by its DID. Every record lives at a key in a Merkle Search Tree; the tree's root CID is sealed by a signed commit; the commit plus every block it transitively references are the repository. On the wire, it travels as a **CAR v1** file.

This skill routes to per-language guides for Rust, TypeScript, and Go, sitting on top of a language-neutral spec in `references/shared/`.

## Defaults

- **DRISL** — canonical DAG-CBOR: bytewise map keys, shortest-form integers, no indefinite-length framing, CIDs as tag 42 + identity multibase.
- **CAR v1** — `varint ‖ header-cbor ‖ (varint ‖ 36-byte-CID ‖ bytes)*`. Roots list declares the commit CID.
- **MST** — SHA-256 key height with fanout 4 (count pairs of leading zero bits). Node shape `{l?, e:[{p,k,v,t?}]}`. Keys are `<collection>/<rkey>`, max 1024 bytes.
- **Commit** — `{did, version:3, data, rev, prev, sig}`. `prev` is `null` for genesis (though see §divergence). Signing bytes = DAG-CBOR of the commit minus `sig`.
- **Signature** — raw `r ‖ s` ECDSA (k-256 or p-256), low-S normalized. Verified against the `#atproto` Multikey in the signer's DID document.

Full normative rules: `references/shared/drisl.md`, `references/shared/car-v1.md`, `references/shared/mst.md`, `references/shared/commit-and-signing.md`, `references/shared/data-model.md`. Fixtures: `references/shared/test-vectors.md`. Cross-language differences: `references/shared/divergence-matrix.md`.

## Language detection

Before generating or reviewing any repo code, determine the target language from project files or the file being edited:

- `Cargo.toml`, `*.rs`, any mention of `atproto-repo` / `atproto-dasl` / `atproto-record` → **Rust** — read from `references/rust/`.
- `package.json`, `tsconfig.json`, `*.ts`, `*.tsx`, imports of `@atproto/repo` / `@atproto/lex-cbor` / `@atproto/crypto` → **TypeScript** — read from `references/typescript/`. Also `*.js`/`*.jsx` when there is no `.ts` present.
- `go.mod`, `*.go`, imports of `github.com/bluesky-social/indigo/atproto/repo` → **Go** — read from `references/go/`.

Prefer the *file being edited* over the *repo root* when they disagree: a `.go` consumer inside a TypeScript-workspace monorepo still means Go for that task.

If multiple languages are present and the task does not point at one unambiguously, **ask which one applies**. Never mix repo libraries across languages in generated code.

If an unsupported language is detected (Python, Java, Swift, …), point the user at `references/shared/drisl.md`, `references/shared/car-v1.md`, `references/shared/mst.md`, and `references/shared/commit-and-signing.md` for the wire format, and offer the Go `indigo/atproto/repo` source as the most complete reference implementation to transliterate from.

## Reading guide

For every repo task:

1. Read the relevant `references/shared/*.md` first. They are short and define the rules your code must enforce.
2. Read the relevant task file in the detected language directory:
   - DRISL / canonical DAG-CBOR encoding of any block → `references/{lang}/drisl.md`
   - CAR v1 reading and writing → `references/{lang}/car.md`
   - MST construction, traversal, diff → `references/{lang}/mst.md`
   - Commit record shape, signing, verification → `references/{lang}/commit.md`
   - Library setup, public API at a glance, idioms → `references/{lang}/README.md`
3. Consult `references/shared/divergence-matrix.md` whenever porting between languages or reviewing cross-stack interop. The `prev: null` vs omitted divergence alone has caused many hours of "why does my signature not verify" debugging.

Always prefer the official library over hand-rolling: `atproto-repo` crate in Rust, `@atproto/repo` in TypeScript, `github.com/bluesky-social/indigo/atproto/repo` in Go.

## The conceptual stack

```
                       ┌──────────────────────────────┐
  CAR v1 file  ──────▶ │ header: { version:1, roots }  │
  (on the wire)        │ block: [cid, data] …          │
                       │ block: [cid, data] …          │
                       └──────────────────────────────┘
                                   │
                                   ▼
                       ┌──────────────────────────────┐
  Signed commit ─────▶ │ { did, version:3, data, rev, │
  (root block)         │   prev, sig }                │
                       └──────────────────────────────┘
                                   │ data: CID
                                   ▼
                       ┌──────────────────────────────┐
  MST node ──────────▶ │ { l?, e:[entry,entry,…] }    │
  (many blocks)        │ entry = { p, k, v, t? }      │
                       └──────────────────────────────┘
                                   │ v: CID (leaf = record block)
                                   ▼
                       ┌──────────────────────────────┐
  Record block ──────▶ │ DAG-CBOR encoding of record  │
  (many blocks)        │ { $type: "<nsid>", … }       │
                       └──────────────────────────────┘
```

CAR just frames a sequence of `(CID, bytes)` blocks. The same block bytes travel over `getRecord`, the firehose, and any cache.

## Cross-language hazards to flag up front

High-frequency failure modes; full detail in `references/shared/divergence-matrix.md`:

- **`prev: null` vs omitted** — When signatures fail on genesis commits only, suspect cross-encoder `prev` drift. Rust reference impl omits `prev` for genesis (4-entry map); Go and TS always serialize `prev: null` (5-entry map). Strip the signature from raw bytes rather than re-encoding before verifying.
- **TS MST is immutable** — When an add/update/delete appears to have no effect, reassign to the return value. `add`/`update`/`delete` return a new `MST`; the original is unchanged. Rust and Go mutate in place.
- **TS CAR reader verifies CIDs on ingest** — When a CAR that Go or Rust accepts fails TS intake, suspect block corruption. `verifyIncomingCarBlocks` defaults on in TS; Go and Rust do not verify.
- **Go cbor-gen sorts by struct declaration order, not bytewise** — When adding a new cbor-gen struct, audit field order against bytewise canonical order. The `Commit` struct happens to be canonical, but anything you add must be checked.
- **Partial trees are normal in Go/Rust, exceptional in TS** — When a firehose event traversal throws `MissingBlockError` in TS, treat the partial tree as expected and fall back to a partial walker. Go/Rust return a partial-tree sentinel instead.
- **Only Go has end-to-end wired verification** — When verifying in TS or Rust, resolve the signing DID key separately first. `VerifyCommitSignatureFromCar` is Go-only; TS needs a pre-resolved didKey and Rust needs the caller to do everything.
- **Rust `Mst::insert_recursive` can't cross heights** — When building an MST from scratch in Rust, build bottom-up from sorted `(key, cid)` pairs, not top-down.

## Optional MCP Tools

If available in this Codex session, prefer these MCP tools when the goal is to *compute* or *validate* rather than teach an implementation how:

- **`lexicon-garden`** → `create_record_cid(record)`, `transmogrify_record`, `invoke_xrpc` (e.g. `com.atproto.sync.getRepo`, `getBlocks`).
- **`atpmcp`** → `create_record_cid`, `get_record`, `transmogrify_record`, `generate_tid` against a local PDS.

Concrete example — computing a spec-conformant record CID against an in-memory record before writing a test vector:

```
create_record_cid({
  "$type": "app.bsky.feed.post",
  "text":  "hello",
  "createdAt": "2024-01-01T00:00:00.000Z"
})
→ "bafyreihsh..."
```

Use this to verify your own encoder output matches the canonical CID without having to boot a PDS. `transmogrify_record` is the round-trip companion — feed it a record, get back the DAG-CBOR bytes and the CID together.

For record-side helpers (TID generation, AT-URI parsing), the `atproto-record` Rust crate ships the cleanest reference; the TS equivalent is `@atproto/syntax`, and Go uses `atproto/syntax` in indigo.

## Cross-skill plumbing: DID resolution for verification

`VerifyCommitSignatureFromCar` (Go) does identity lookup and signature check in one call. TypeScript and Rust need the signing key resolved separately before verification:

- **Rust** — resolve with `atproto-identity` first, extract the `#atproto` verification method, then pass the Multikey into `atproto-repo`'s verify loop. See `../atproto-identity-resolution/references/rust/resolution.md` for the resolver and `references/rust/commit.md` for the verify surface.
- **TypeScript** — resolve via `@atproto/identity` → `IdResolver.did.resolveAtprotoData(did)` → yields `{ signingKey }` as a `didKey`, then pass into `verifyCommitSig`. See `../atproto-identity-resolution/references/typescript/resolution.md` and `references/typescript/commit.md`.
- **Go** — `VerifyCommitSignatureFromCar` wraps both; no manual plumbing required.

## Directory layout

```
atproto-repository/
├── SKILL.md                          # this file — router
├── references/shared/
│   ├── drisl.md                      # canonical DAG-CBOR rules
│   ├── car-v1.md                     # CAR v1 byte layout
│   ├── mst.md                        # MST algorithm + invariants
│   ├── commit-and-signing.md         # commit shape, signing bytes, verification
│   ├── data-model.md                 # records, NSIDs, TIDs, AT-URIs
│   ├── test-vectors.md               # fixtures
│   └── divergence-matrix.md          # cross-language differences
├── references/rust/
│   ├── README.md                     # atproto-repo / atproto-dasl / atproto-record setup
│   ├── drisl.md                      # atproto-dasl encoding
│   ├── car.md                        # CarReader / CarWriter
│   ├── mst.md                        # Mst<S>, insert_recursive, diff_entries
│   └── commit.md                     # Commit / UnsignedCommit / signing loop
├── references/typescript/
│   ├── README.md                     # @atproto/repo setup
│   ├── drisl.md                      # @atproto/lex-cbor
│   ├── car.md                        # readCar / writeCarStream / verifyIncomingCarBlocks
│   ├── mst.md                        # immutable MST class
│   └── commit.md                     # signCommit / verifyCommitSig / verifyRepo
└── references/go/
    ├── README.md                     # indigo/atproto/repo setup
    ├── drisl.md                      # cbor-gen + atdata
    ├── car.md                        # LoadRepoFromCAR / go-car
    ├── mst.md                        # Tree / Node / partial-tree semantics
    └── commit.md                     # Commit / Sign / VerifyCommitSignatureFromCar
```

## References

All reachable from this Codex skill folder. Listed here for quick grep:

- `references/shared/drisl.md`, `references/shared/car-v1.md`, `references/shared/mst.md`, `references/shared/commit-and-signing.md`, `references/shared/data-model.md`, `references/shared/test-vectors.md`, `references/shared/divergence-matrix.md`
- `references/rust/README.md`, `references/rust/drisl.md`, `references/rust/car.md`, `references/rust/mst.md`, `references/rust/commit.md`
- `references/typescript/README.md`, `references/typescript/drisl.md`, `references/typescript/car.md`, `references/typescript/mst.md`, `references/typescript/commit.md`
- `references/go/README.md`, `references/go/drisl.md`, `references/go/car.md`, `references/go/mst.md`, `references/go/commit.md`
