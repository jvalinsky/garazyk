# Firehose Frame Decoding

## Wire Rule

AT Protocol subscription WebSocket messages are two concatenated DAG-CBOR objects:

1. Header: `{ op: number, t?: string }`
2. Body: message variant body or error body

The parser must reject malformed frames and trailing bytes.

## Design

- Decode the first object with `cborg.decodeFirst()` using `@ipld/dag-cbor` decode options for CID tag handling.
- Decode the second object from the remaining bytes with the same options.
- Require both header and body to be non-array objects.
- Reject any trailing bytes after the second object.
- Expose:
  - `payload`: raw frame bytes, unchanged for backward compatibility.
  - `header`: decoded header object.
  - `body`: decoded body object.
  - `seq`: `body.seq` when it is a number.
  - `type`: `header.t` when present, otherwise `String(header.op)`.

## Scenario Impact

- Scenario 09 should assert positive ordered sequence numbers from decoded bodies.
- Scenario 63 should use decoded cursor progression, not unknown fallback events.
