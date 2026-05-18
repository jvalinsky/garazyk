---
name: atproto-attestation
description: "Use when implementing, porting, auditing, or debugging AT Protocol record attestations per badge.blue in Rust, TypeScript, or Go. Covers inline ECDSA attestations, remote proof-record strongRefs, content-CID signing, low-S normalization, signature byte formats, replay protection, and attestation verification failures."
---

# AT Protocol record attestations (badge.blue)

CID-first record attestations as specified at <https://badge.blue/> and implemented in the `atproto-attestation` Rust crate. This skill routes to per-language guides for Rust, TypeScript, and Go, sitting on top of a language-neutral spec in `references/shared/`.

## Defaults

An attestation binds a cryptographic or content-addressed claim to a specific record in a specific repository:

- **Content CID**: CIDv1, codec `0x71` (dag-cbor), hash `0x12` (SHA-256), 32-byte digest, 36-byte binary form. Computed over a canonical merge of `record` (without `signatures`) + `$sig` metadata (without `cid`/`signature`, with `repository` inserted).
- **Inline attestation**: the 36-byte CID bytes are ECDSA-signed (P-256 or K-256), normalized to low-S, base64-encoded (standard alphabet with padding), and embedded in `record.signatures[]` alongside the metadata.
- **Remote attestation**: the content CID is written into a separate *proof record* in the attestor's repo; the subject record's `signatures[]` carries a `com.atproto.repo.strongRef` pointing at the proof record.

Full normative rules: `references/shared/spec.md`. Step-by-step CID procedure: `references/shared/cid-computation.md`. Inline flow: `references/shared/inline-attestation.md`. Remote flow: `references/shared/remote-attestation.md`. Signature normalization: `references/shared/signature-normalization.md`. Fixtures: `references/shared/test-vectors.md`. Cross-language differences: `references/shared/divergence-matrix.md`.

## Language detection

Before generating or reviewing any attestation code, determine the target language from project files:

- `Cargo.toml`, `*.rs`, any mention of `atproto-attestation` / `atproto-identity` / `k256` / `p256` → **Rust** — read from `references/rust/`. The reference crate lives here.
- `package.json`, `tsconfig.json`, `*.ts`, `*.tsx`, imports of `@noble/curves` / `@ipld/dag-cbor` / `multiformats` → **TypeScript** — read from `references/typescript/`.
- `go.mod`, `*.go`, imports of `github.com/ipfs/go-cid` / `github.com/ipld/go-ipld-prime` / `github.com/decred/dcrd/dcrec` → **Go** — read from `references/go/`.

Prefer the *file being edited* over the *repo root* when they disagree.

If multiple languages are present and the task does not point at one unambiguously, **ask which one applies**. Never mix attestation libraries across languages in generated code.

For an unsupported language (Python, Java, Elixir, Swift, …), point the user at `references/shared/spec.md` and the Rust crate as the reference implementation to transliterate from.

## Reading guide

For every attestation task:

1. Read `references/shared/spec.md` for the normative rules (terminology, record shapes, verification order, known gaps).
2. If the task is about computing the CID to sign, read `references/shared/cid-computation.md`. Every non-trivial implementation bug in this space is at this step.
3. Read one of the flow-specific specs:
   - Inline (embed signature in record) → `references/shared/inline-attestation.md`.
   - Remote (proof record + strongRef) → `references/shared/remote-attestation.md`.
   - ECDSA signing / normalization details → `references/shared/signature-normalization.md`.
4. Read the relevant task file in the detected language directory:
   - Dependency setup, library choice, idioms → `references/{lang}/README.md`
   - Creating an attestation (inline or remote) → `references/{lang}/creating.md`
   - Verifying a record's attestations → `references/{lang}/verifying.md`
   - ECDSA primitives, curve-specific pitfalls → `references/{lang}/signatures.md`
5. Consult `references/shared/divergence-matrix.md` when porting between languages or reviewing cross-stack interop.

Always prefer the reference crate (Rust) or the primitive libraries called out in each `references/{lang}/README.md` over hand-rolling. Never guess function names — read the relevant file, and if a detail is missing, consult live docs (docs.rs, npm, pkg.go.dev) rather than inventing.

## Architecture (shared concepts)

### What gets signed

Neither the raw record nor the metadata alone — the ECDSA signature is over the **36-byte binary content CID** of a canonical merge:

```
record' = record without `signatures`
meta'   = metadata without `cid` / `signature`, with `repository` inserted
merged  = record' ∪ { "$sig": meta' }

content_cid = CIDv1(dag-cbor, SHA-256(DAG-CBOR(merged)))
signature   = ECDSA_sign(private_key, content_cid.bytes)
```

`repository` participates in the CID but NOT in the stored attestation. This gives replay protection: the same `record` + `metadata` signed for `did:plc:A` produces a different CID than for `did:plc:B`, so a signature made for one repo cannot be reused in another.

### Inline vs remote

| Trait                | Inline                                    | Remote                                         |
| -------------------- | ----------------------------------------- | ---------------------------------------------- |
| Cryptographic        | Yes — ECDSA signature in the record       | No — integrity by content-address + strongRef  |
| Records involved     | 1 (subject only)                          | 2 (subject + proof, usually in different repos)|
| `signatures[]` entry | metadata object with `cid` and `signature.$bytes` | `com.atproto.repo.strongRef` with `uri` + `cid` |
| Verifier needs       | public key resolution                     | record resolver (AT-URI fetch)                 |
| Revocation           | immutable once signed                     | delete proof record → unreachable              |

`references/shared/inline-attestation.md` and `references/shared/remote-attestation.md` cover each in full.

### Two CIDs in remote attestations

Remote attestations involve **two distinct CIDs** and confusing them is the most common bug:

| CID             | Where it's stored                         | What it identifies                        |
| --------------- | ----------------------------------------- | ----------------------------------------- |
| **Content CID** | Inside the proof record's `cid` field     | The signing payload (record + `$sig`)     |
| **Proof CID**   | Inside the strongRef's `cid` field        | The proof record itself (plain DAG-CBOR)  |

Always verify both. See `references/shared/remote-attestation.md` §two-CIDs.

### Curve support

| Curve | Reference crate (Rust) | TypeScript (`@noble/curves`) | Go (`crypto/ecdsa` + `dcrec`) |
| ----- | ---------------------- | ---------------------------- | ----------------------------- |
| P-256 | ✅ full                | ✅ full                      | ✅ full (low-S manual)        |
| K-256 | ✅ full                | ✅ full                      | ✅ full (dcrec low-S default) |
| P-384 | ⚠️ `normalize_signature` returns `UnsupportedKeyType` | ✅ full, but interop broken  | ✅ full, but interop broken   |

**Interop rule**: use P-256 or K-256 only. P-384 does not round-trip through the reference crate. See `references/shared/signature-normalization.md` §curve-coverage.

### Validation vs verification

- **Validation**: the attestation is structurally well-formed (required fields present, base64 decodable, signature is 64 bytes, CID is a valid bafyrei… string).
- **Verification**: the signature (inline) or content CID (remote) matches what you recompute from the record + metadata + repository.

Separate these steps in your code. Keep policy checks (is this issuer authorized? is the attestation fresh?) outside — they're application concerns above the crypto.

## Common pitfalls

Draw from each `references/shared/*.md` §common-mistakes and `references/shared/divergence-matrix.md`. The high-impact ones:

- **Signing the CID string (`bafyrei…`) instead of the 36-byte binary CID.** Silent interop break — implementations that hash `cid.bytes` don't verify signatures made over the string form.
- **Signing the 32-byte digest instead of the 36-byte CID bytes.** Similar silent break. The spec signs the full CID header + digest, not just the digest.
- **Including `repository` in the stored attestation.** It's only a transient input to CID computation; it must not appear in `signatures[]` entries. Reference implementations strip it; hand-rolled ones often don't.
- **Forgetting to strip `signatures` from the record before CID computation.** Every new signature re-signs a stripped version, so all prior signatures stay valid. Skip the strip and all signatures invalidate each other.
- **Forgetting to strip `cid` / `signature` from metadata before CID computation.** These fields are *outputs*, not inputs. Including them on re-verify produces a different CID.
- **DER-encoded signatures.** ECDSA libraries often return DER (70–72 bytes); spec requires IEEE P1363 `r‖s` (64 bytes for P-256/K-256). Convert if needed.
- **Skipping low-S normalization.** Some libraries (noble secp256k1, dcrec) default to low-S; others (Go stdlib, OpenSSL, p256 noble-default) don't. Normalize explicitly — cost is negligible.
- **URL-safe base64 for `signature.$bytes`.** Spec uses standard base64 (`+`/`/` + padding). URL-safe (`-`/`_`) decodes to different bytes for 62/63 code points.
- **Publishing the attested record before the proof record.** On network hiccup you end up with a dangling strongRef. Publish proof first.
- **Confusing the proof record's DAG-CBOR CID (in the strongRef) with the content CID (inside the proof record).** Two different bytes; one is a plain DAG-CBOR CID of the whole proof record, the other is the attestation-layer content CID.
- **Using P-384.** The Rust reference crate's normalization rejects it — create-time failures. See curve coverage above.
- **Non-canonical CBOR.** `fxamacker/cbor` without `CoreDetEncOptions` (Go), hand-rolled CBOR, or generic CBOR libraries produce different bytes than DAG-CBOR. Use strict DAG-CBOR libraries only.

## Decision rules

- **Inline or remote?** Inline if the attestor holds their own key and signs in-process. Remote if the attestor is a separate service (hands a proof-record URI back) or the attestation should be independently deletable.
- **Which curve?** P-256 for NIST/FIPS environments. K-256 for atproto-repo-signing-key compatibility or when sharing keys with AT Protocol identity. Default to whichever you already have; avoid P-384.
- **Strict low-S on verify?** Optional but recommended for new verifiers. The reference crate is permissive (accepts both).
- **Verify proof record's outer DAG-CBOR CID matches strongRef `cid`?** The reference crate does not; the TS and Go guides in this skill do by default. Pass `verifyProofCid: false` / `VerifyProofCid: false` to match reference semantics exactly.
- **Where does `repository` come from at verify time?** The DID of the repo you fetched the record from. Hardcoding it or using a stale value silently invalidates every inline signature.
- **Multiple attestations on one record?** Fully supported — each signature is computed over the record with `signatures` stripped, so all prior signatures remain valid when new ones are appended.

## Optional MCP Tools

If available in this Codex session, prefer these MCP tools when the goal is to *compute* or *validate* CIDs as part of a composite workflow rather than teach an implementation how:

- **`lexicon-garden`** → `create_record_cid(record_json)` for the underlying DAG-CBOR CID primitive, `invoke_xrpc` for `com.atproto.repo.putRecord` / `getRecord`.
- **`atpmcp`** → `create_record_cid`, `get_record`, `invoke_xrpc` against a local PDS for development.

Note: neither MCP currently exposes a badge.blue-specific `create_attestation` or `verify_attestation` tool — the content-CID pipeline (`record + $sig(repository)`) is attestation-specific and must be implemented per-language as described in the guides. The MCPs are useful for the *raw CID* step inside that pipeline and for publishing the resulting records.

## Directory layout

```
atproto-attestation/
├── SKILL.md                              # this file — router
├── references/shared/
│   ├── spec.md                           # normative attestation rules
│   ├── cid-computation.md                # content-CID procedure (bit-exact)
│   ├── inline-attestation.md             # inline flow + record shape
│   ├── remote-attestation.md             # remote flow + two-CID model
│   ├── signature-normalization.md        # low-S rules, P-384 gap
│   ├── test-vectors.md                   # fixtures catalog
│   └── divergence-matrix.md              # cross-language differences
├── references/rust/
│   ├── README.md                         # reference crate setup, API map
│   ├── creating.md                       # create_inline / create_remote / append
│   ├── verifying.md                      # verify_record + resolver impls
│   └── signatures.md                     # sign / validate / normalize_signature
├── references/typescript/
│   ├── README.md                         # library stack + idioms
│   ├── creating.md                       # computeContentCid + create flows
│   ├── verifying.md                      # verifier + resolver impls
│   └── signatures.md                     # noble curves + low-S
└── references/go/
    ├── README.md                         # stdlib + dcrec + go-ipld-prime
    ├── creating.md                       # ComputeContentCID + create flows
    ├── verifying.md                      # VerifyRecord + resolvers
    └── signatures.md                     # stdlib ecdsa + dcrec + P1363
```

## References

- `references/shared/spec.md`, `references/shared/cid-computation.md`, `references/shared/inline-attestation.md`, `references/shared/remote-attestation.md`, `references/shared/signature-normalization.md`, `references/shared/test-vectors.md`, `references/shared/divergence-matrix.md`
- `references/rust/README.md`, `references/rust/creating.md`, `references/rust/verifying.md`, `references/rust/signatures.md`
- `references/typescript/README.md`, `references/typescript/creating.md`, `references/typescript/verifying.md`, `references/typescript/signatures.md`
- `references/go/README.md`, `references/go/creating.md`, `references/go/verifying.md`, `references/go/signatures.md`
- External: <https://badge.blue/> (spec), <https://tangled.org/ngerakines.me/atproto-crates/tree/main/crates/atproto-attestation> (reference crate)
