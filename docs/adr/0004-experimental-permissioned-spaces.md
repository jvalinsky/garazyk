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
