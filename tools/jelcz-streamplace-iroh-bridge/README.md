# jelcz-streamplace-iroh-bridge

This is a separate, receive-only Streamplace live bridge. Its local IPC is
versioned and only binds loopback TCP or a caller-selected Unix socket:

- `GET /v1/health` reports live capability and subscription state.
- `POST /v1/subscribe` accepts `streamer`, Streamplace `irohTicket`, and
  consent asserted by Jelcz after its streamer policy check. A required
  `Authorization: Bearer` capability independently limits local IPC access;
  configure the same random value as `JELCZ_STREAMPLACE_IROH_BRIDGE_TOKEN` in
both processes. On a
  successful subscription it returns the first authenticated MUXL candidate as raw
  `application/octet-stream`; it never returns a NodeTicket.

Standalone TCP remains loopback-only. The Docker lab may opt into private
service-name HTTP with `serve --bind-all`; that path is valid only with the
bearer capability, an unpublished bridge port, and Jelcz's explicit
`JELCZ_STREAMPLACE_IROH_BRIDGE_TRUST_LAN=1` lab flag. Jelcz restricts this
exception to the exact `streamplace-track-b-bridge` Compose hostname so the
capability cannot be sent to an arbitrary HTTP origin.

The protocol target is Streamplace ALPN `/iroh/streamplace/1`, whose subscribe
key is exactly the streamer DID. Segment candidates are intended to be delivered
as MUXL bytes only after the transport has authenticated the connected peer.

## Dependency pin

The bridge records the upstream Streamplace `iroh-streamplace` source target in
`Cargo.toml` metadata at immutable revision
`5ba597dbedda8f2fdb84b815ee633301212f5f51` (the `next` commit verified on
2026-08-13), and pins its compatible iroh family to `=0.93.2`. Its workspace
lock resolves `irpc` to `=0.9.0`.

This is intentionally not a normal Cargo dependency: the pinned upstream crate
publishes only `staticlib` and `cdylib`, not `rlib`. A future vendor/wrap route
must be an explicit source patch (such as adding `rlib`) or a reviewed FFI
boundary, never an assumed Rust-library import. The nested
`rust/iroh-streamplace/Cargo.lock` at the pin is stale (`iroh`/`iroh-base`
0.91.1 and no `irpc`/`irpc-iroh`); it is not the workspace build resolution and
must not be used as reproducibility evidence.

## Authenticated peer identity

At that revision, `Subscribe.remote_id` and `RecvSegment.from` are serialized
RPC payload fields marked `TODO: verify`. The upstream generic RPC handler
stores or forwards them without proving they match the authenticated iroh/QUIC
connection identity. This bridge does not use that handler. Its narrow,
pin-specific `ProtocolHandler` captures `Connection::remote_node_id()` and
rejects a `RecvSegment` unless `from`, the authenticated peer, the bound ticket
identity, and the subscribed streamer key agree. Outbound
`IrohRemoteConnection` dials the parsed ticket NodeId with the exact ALPN.

The remaining gate is empirical rather than an identity blocker: a dated opt-in
smoke must subscribe to a real Streamplace streamer and validate the received
MUXL candidate.

## Process-persistent evidence contract

The bridge records only facts it directly observes: dial/Subscribe activity,
the ticket's SHA-256 fingerprint and parsed NodeId, the exact ALPN, the
authenticated connection NodeId, and accepted segment source/positive byte
count. It writes a complete JSON replacement atomically to
`/tmp/jelcz-streamplace-iroh-bridge-evidence.json` by default (or the absolute
path supplied by `--evidence-file` / `JELCZ_STREAMPLACE_IROH_BRIDGE_EVIDENCE_FILE`).
The path must be beneath an existing `/tmp` directory, which works with the
Track B read-only image's tmpfs. Starting a bridge creates a fresh process
record, so old evidence cannot pass a new process's acceptance command.
The persistence primitive walks from an opened canonical `/tmp` descriptor
using `openat(O_NOFOLLOW)`, rejects symlink components and unsafe ownership or
permissions, creates a mode-0600 temporary file relative to that descriptor,
and replaces the report with `renameat`. The report reader also uses
`openat(O_NOFOLLOW)` and requires an owner-matching regular file.

`acceptance-report --json` reads that file rather than querying in-memory state.
It emits JSON on success or failure and exits zero only if at least one session
has complete bridge-owned evidence. The stable top-level shape is:

```json
{
  "contractVersion": "jelcz-streamplace-iroh-bridge-evidence/v1",
  "bridgeOwnedEvidenceComplete": true,
  "sessions": {
    "session-id": {
      "sessionId": "session-id",
      "requestedStreamer": "did:plc:...",
      "ticketFingerprint": "sha256:...",
      "ticketNodeId": "...",
      "alpn": "/iroh/streamplace/1",
      "dialAttempts": 1,
      "reconnectAttempts": 0,
      "reconnectAttemptLimit": 5,
      "subscribeAcknowledged": true,
      "attestationExpiresUnixMs": 1786670000000,
      "attestationConsumed": true,
      "authenticatedRemoteNodeId": "...",
      "segment": { "bytes": 123, "fromNodeId": "...", "contentSha256": "sha256:..." },
      "jelczAttestation": {
        "muxlStructuralValidation": "valid",
        "contentBytes": 123,
        "contentSha256": "sha256:...",
        "attestedUnixMs": 1786669999000
      },
      "observedRejections": []
    }
  },
  "scope": "bridge transport observations plus capability-bound Jelcz structural MUXL attestations only"
}
```

Counters and rejection codes are strictly observed values. A failed Subscribe
is retried with bounded exponential backoff; `reconnectAttempts` cannot exceed
`reconnectAttemptLimit`, and Scenario 101 proves exact exhaustion against a
peer that drops every Subscribe. The report has no fields for a
firehose, origin record, server, source image, or consent decision, because the
bridge cannot observe or prove those facts. Its evidence store never persists
or reports raw tickets or capabilities.

On a successful `POST /v1/subscribe`, the raw segment response carries the
non-secret `X-Jelcz-Bridge-Session` header. After Jelcz has independently
validated that exact response as structurally valid MUXL, it may make this
capability-protected local call:

```http
POST /v1/evidence/muxl-attestations
Authorization: Bearer <JELCZ_STREAMPLACE_IROH_BRIDGE_TOKEN>
Content-Type: application/json

{"sessionId":"<X-Jelcz-Bridge-Session>","ticketFingerprint":"sha256:<64 hex>","contentBytes":123,"contentSha256":"sha256:<64 hex>","muxlStructuralValidation":true}
```

The ticket fingerprint is the SHA-256 of the original raw ticket UTF-8 bytes;
the content fingerprint is the SHA-256 of the exact raw response bytes. Both
are encoded as lower-case hexadecimal and prefixed `sha256:`. The bridge
rejects missing, stale, mismatched, byte-count-mismatched, or
content-hash-mismatched attestations; it records only the fact that Jelcz's
structural validation passed. This attestation route accepts no content,
origin, firehose, or consent claims.

The bridge opens a 30-second attestation window immediately before returning
the candidate response (configurable in code, hard-capped at 120 seconds). The
session may be attested exactly once. An expired, consumed, missing, or
mismatched session returns `evidence_attestation_mismatch` and can never be
upgraded to complete acceptance evidence.

## Limits and redaction

The contract rejects malformed or over-2 KiB tickets, bounds segment size (8
MiB), candidate queue (32), subscriptions (64), concurrent authenticated
inbound protocol handlers (16), and subscription deadlines. Its narrow reader
uses the subscription deadline as a per-request idle timeout and framing
equivalent to pinned `irpc-iroh`, but applies the
configured segment limit plus 4 KiB of bounded postcard/key overhead before
allocating or deserializing the request. The upstream
`irpc_iroh::read_request` helper is intentionally not used: at pinned irpc
0.9.0 it has a fixed, non-configurable 16 MiB predecode ceiling. IPC errors are
stable codes and never echo NodeTickets or parser text.

## Lab-only fault peer

`fault-peer` is a Scenario 101 fixture, not a production mode. Six private
Compose services use the same pinned binary to exercise wrong streamer, wrong
ALPN, authenticated `from` spoof, corrupt MUXL, oversize segment, and dropped
Subscribe cases. Each service writes its public NodeTicket to its own private
`/tmp` tmpfs; `fault-ticket --json` is read only through `docker compose exec`.
The scenario keeps tickets process-only, records only fingerprints/NodeIds,
and requires bridge session evidence for the actual rejection or bounded
retry counters. None of the fixture services publishes a host port.
