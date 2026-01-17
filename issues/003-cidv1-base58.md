# Issue: ExploreHandler cannot decode CIDv1 base58btc

## Summary
`ATProtoPDS/Sources/App/Explore/ExploreHandler.m` short-circuits `z` (base58btc) multibase entries, reporting `decodingStatus = "partial - base58 decoding not implemented"` and returning early without populating metadata.

## Impact
- CIDv1 resources with base58btc encodings cannot be inspected or verified via the explore APIs.
- Users receive incomplete metadata and cannot rely on the handler to surface the CID structure.

## Proposed fix
- Integrate a base58btc decoder (either custom or via a shared CID library) so base58-prefixed `z` strings are converted to binary payloads.
- Once decoded, reuse the existing CIDv1 parser to populate version, codec, multihash, and multibase information.
