# ADR 0004: Experimental Permissioned Spaces

## Status

Accepted for implementation. The feature is disabled unless explicitly enabled.

## Sources

- Bluesky Proposal 0016, `0016-permissioned-data/README.md`.
- `bluesky-social/atproto` commit `3f6c96d5d2d25438bd40fa89d6ecc37865f8e354`.
- BLAKE3 portable C implementation commit `8aa5145039b972ba30e98e788752d37d14568824`.

## Decision

Permissioned data is a separate protocol subsystem. It is never represented as
a public repository record, a public sync event, a search document, a
moderation-feed item, or an ordinary `com.atproto.repo.*` URI. Its storage is
an isolated SQLite database with a forward-only schema migration table and
space/user keys on every repository, record, operation-log, notification, and
credential-replay row.

The PDS implements the repo-host and space-host roles as distinct service
operations. A local user PDS hosts that user's repository; a space host owns
policy, membership, delegation-token exchange, writer discovery, and
notification fan-out. This separation permits an account PDS and a space host
to be different services.

The protocol uses the exact `com.atproto.space.*` and
`com.atproto.simplespace.*` Lexicons from the pinned reference. Space URI,
OAuth scope, credential, and commit parsing are structured, bounded, and
fail-closed primitives. Callers cannot provide raw SQL, URI fragments, scope
fields, token claims, or DID-document entries to persistence or authorization
sinks without successful parsing and validation.

LtHash uses BLAKE3 XOF as specified; SHA-256 is used only for the final
LtHash digest and HMAC/HKDF-SHA256 only for the signed-commit MAC. The vendored
portable BLAKE3 source is pinned above rather than relying on a system binary.

`permissionedSpacesEnabled` defaults to `false` in production. Enabling it is
an explicit operator decision because Proposal 0016 is experimental. When it
is disabled, no space route is registered and no permissioned data is written.

Private blobs are held in the same isolated subsystem, keyed by space URI,
author DID, and raw-CID. They never pass through `PDSBlobService`, its public
filesystem namespace, or public blob metadata. Because Proposal 0016 defines
`getBlob` but no blob-upload procedure, uploads use the standard
`com.atproto.repo.uploadBlob` binary endpoint only when all three experimental
headers are present: `X-Atproto-Space`, `X-Atproto-Space-Collection`, and
`X-Atproto-Space-Action` (`create` or `update`). The verified OAuth token must
permit that exact space action and collection. This binding is deliberately
explicit, documented, and private to the experimental implementation until an
upstream upload lexicon is standardized.

## Revocation and credential lifetime

Membership changes take effect before every new credential mint and every
OAuth-authorized request. A protocol space credential contains no member DID
and is designed for offline verification by any repo host, so it cannot be
retroactively tied to a removed member without changing the protocol. Existing
credentials remain valid only until their bounded expiration; the default and
maximum implemented lifetime is two hours. The space host records every issued
credential recipient for audit and notification purposes but does not use that
record as an unverifiable remote-host revocation oracle.

Delegation tokens are single-use, recorded atomically before exchange, and
kept until expiration. Credentials and delegation tokens are never logged.

## Deliberately disabled scope

The `managing-app` policy and `appAccess#allowList` are disabled until the PDS
can validate a client attestation end-to-end: resolved client metadata, JWKS,
key identifier, signature, issuer/subject equality, audience, expiry, nonce
replay, and app identity. Their configuration is rejected instead of falling
back to `open`. This is required because accepting a merely structural
attestation would weaken the privacy boundary.

## Operations

Backups must include the permissioned-space database and its WAL sidecars.
Rollback means disabling the feature and retaining that database; downgrades
do not delete permissioned records. The space signing key initially falls back
to the account `#atproto` key as Proposal 0016 permits. A future dedicated
`#atproto_space` key requires a key-rotation migration and is not silently
emulated.

When enabled, newly created account and server DID documents explicitly publish
`#atproto_space` with the existing account signing key and
`#atproto_space_host` with the PDS endpoint. This is the allowed explicit
same-value form from Proposal 0016, not a claim that an independent space key
exists. Operators may set `permissionedSpacesHostEndpoint` to a validated
HTTP(S) URL when the endpoint that PDS peers resolve differs from the public
issuer (for example, a Docker network alias). Existing `did:plc` accounts need
an ordinary PLC rotation to acquire these entries; the PDS never rewrites a
user's DID document implicitly.

## Amendment: dedicated space signing-key rotation

### Context

The current `#atproto_space` entry can intentionally reuse `#atproto`, but
credential minting therefore uses the account signing key. Relabeling that
signature as a dedicated space key would make the DID document lie. A real
migration needs a separate private key, an ordinary operator-authorized PLC
operation, and a bounded overlap in which existing credentials continue to
verify.

### Decision

Implement dedicated-key migration as an explicit per-DID operator workflow.
The future implementation introduces a purpose-bound `PDSActorKeyManager`
instance for `#atproto_space`; it must use the same platform-protected key
storage class as account signing keys, but a distinct storage identifier and
access policy. Neither its private material, an encoded credential, nor a
delegation token is accepted as a CLI argument or emitted in logs.

The workflow has four durable states, recorded separately from the public
space database:

1. **Fallback** — only `#atproto` is authoritative. New credentials carry
   `kid: "#atproto"` and are signed by the account signer.
2. **Prepared** — the operator generated and durably stored the dedicated
   signer, but no DID operation has been accepted. This state cannot mint a
   `#atproto_space` credential.
3. **Overlap** — an operator-submitted PLC operation has published the
   dedicated public key at the exact `#atproto_space` fragment, preserving the
   account key at `#atproto`. New credentials use the dedicated signer and
   `kid: "#atproto_space"`; verifiers accept either exact fragment according
   to the token `kid`. The old account signer remains available only through
   the maximum existing credential lifetime (currently two hours) plus DID
   cache propagation time.
4. **Cut over** — after that deadline, account-key credentials are rejected
   as expired and only the dedicated signer mints credentials. The account
   key remains unchanged for ordinary repository signing.

The operator command will create a PLC operation for review and submit it only
with the account's existing rotation authority. It must show the DID, the new
public `did:key` value, the proposed operation CID, and the earliest safe
cutover time before submission; it never performs an implicit DID update at
account creation, login, or credential mint. Existing DIDs follow exactly the
same command. A failed or abandoned PLC operation leaves the persisted
dedicated signer unused and the DID in **Fallback**; it cannot change minted
credential headers.

Rollback during **Overlap** means stopping dedicated-key minting and allowing
already-issued credentials to expire naturally. A second ordinary PLC
operation may restore the same-value fallback entry only after no unexpired
dedicated-key credential can be presented. No rotation removes the account
key, rewrites public repository signatures, or deletes permissioned data.

### Consequences and verification

The implementation must make signer selection a typed `SpaceCredentialSigner`
primitive that returns both a validated exact fragment and its signing
capability. This prevents a caller from pairing arbitrary `kid` text with an
unrelated signer. It must additionally prove, in a two-PDS topology, that:

- an existing fallback credential remains readable during overlap;
- a newly minted dedicated-key credential is signed by the new public key and
  is accepted after a fresh DID resolve;
- a mismatched key/`kid`, an unpublished prepared key, and a stale DID cache
  are rejected or retried safely; and
- after the bounded overlap, minting cannot return the account-key credential.
