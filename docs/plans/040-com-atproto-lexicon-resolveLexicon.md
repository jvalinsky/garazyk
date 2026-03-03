# Implement `com.atproto.lexicon.resolveLexicon`

## Summary

Expose lexicon schema resolution via the `com.atproto.lexicon.resolveLexicon` XRPC method.

## Background / current state (as of 2026-02-12)

- Lexicon exists: `ATProtoPDS/Resources/lexicons/com/atproto/lexicon/resolveLexicon.json`
- Endpoint is implemented in:
  - `ATProtoPDS/Sources/Network/XrpcHandler.h`
  - `ATProtoPDS/Sources/Network/XrpcHandler.m`
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
- Test coverage added in:
  - `ATProtoPDS/Tests/Network/LexiconResolveXrpcTests.m`
  - `ATProtoPDS/Tests/test_main.m` (suite registration)

## Goals

- Provide a reliable way for clients/dev tooling to fetch lexicon schemas by NSID.
- Ensure outputs are deterministic (`cid` must be stable for a given schema).
- Keep lookup behavior consistent with how the server loads lexicons (search paths, overrides).

## Non-goals

- Serving remote lexicons from the network (only resolve lexicons known to this server).
- Supporting multiple lexicon versions for the same NSID (we can add later if needed).

## Lexicon shape

- Type: `query`
- Params:
  - `nsid` (required; format `nsid`)
- Output (required):
  - `uri` (at-uri)
  - `cid` (cid)
  - `schema` (ref `com.atproto.lexicon.schema#main`)
- Error:
  - `LexiconNotFound`

## Proposed approach

### 1) Find schema JSON by NSID

- Validate `nsid` input.
- Prefer resolving from on-disk lexicon JSON so we can return the full schema object.
  - Suggested lookup strategy:
    1) Compute relative path from NSID:
       - `com.atproto.server.describeServer` → `com/atproto/server/describeServer.json`
    2) Search through lexicon roots returned by `ATProtoLexiconRegistry -searchPathsForDirectory:`
    3) Load the first matching JSON file and parse to an object/dictionary
- If not found: return an error named `LexiconNotFound` (status code should match existing server conventions; likely 400 or 404).

### 2) Build response values

- `schema`:
  - return the parsed lexicon JSON as an object
  - note: `com.atproto.lexicon.schema#main` only requires `lexicon` and is permissive of extra top-level fields (`id`, `defs`, etc), so returning the full schema object should validate
- `uri`:
  - use the server DID already exposed by `com.atproto.server.describeServer` (currently `did:web:<hostname>`)
  - proposed format:
    - `at://did:web:<hostname>/com.atproto.lexicon.schema/<nsid>`
- `cid`:
  - compute CID over the schema record using the same mechanism we use for records:
    - encode the schema object to canonical CBOR (dag-cbor) using our CBOR serializer
    - compute sha2-256 multihash
    - wrap as CIDv1 with codec `dag-cbor` (0x71)
  - requirement: must be deterministic across runs for the same schema JSON

## Tests

- [x] missing `nsid` -> 400 InvalidRequest
- [x] invalid `nsid` -> 400 InvalidRequest
- [x] unknown `nsid` -> LexiconNotFound error
- [x] known `nsid` -> returns `uri`, `cid`, `schema`
- [ ] (Optional) CID is stable across repeated calls

## Files likely touched

- `ATProtoPDS/Sources/Network/XrpcHandler.{h,m}`
- `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
- `ATProtoPDS/Tests/*` (new targeted tests)
- Potentially lexicon registry implementation (if we decide to store raw JSON or file paths)

## Definition of done

- [x] Endpoint is registered and reachable.
- [x] Output shape matches lexicon requirements.
- [x] CID computation is deterministic and documented.
- [x] Tests cover not-found + success cases.

## Subtasks

- [x] Add XRPC registration and handler implementation.
- [x] Implement NSID → file lookup in lexicon roots (respect `PDS_LEXICON_PATH` override).
- [x] Decide status code for `LexiconNotFound` and make it consistent with other error responses.
  - Implemented as HTTP 404 with `error=LexiconNotFound`.
- [x] Implement CID computation (canonical CBOR → sha2-256 → CIDv1 dag-cbor).
- [x] Add tests using one or more known bundled lexicons as fixtures.
- [ ] Add a short doc blurb (optional): how `uri` is constructed (did:web-based).
