---
title: Incremental Chunked-Body Parsing
description: RFC 9112 framing, fragmented input, and body-size enforcement
---

HTTP/1.1 chunked transfer coding lets a sender transmit a body without a
`Content-Length`. Each chunk starts with a hexadecimal size line, followed by
that many bytes and a CRLF delimiter. A zero-sized chunk terminates the body.

```text
7\r\n
Mozilla\r\n
9\r\n
Developer\r\n
0\r\n
\r\n
```

## Parser state

`HttpChunkedBodyParser` moves through four useful states:

1. Read a chunk-size line.
2. Read the declared chunk bytes and following CRLF.
3. Read the final delimiter after the zero-sized chunk.
4. Mark the body complete.

`appendData:error:` accepts arbitrary network fragments. A size line, payload,
or delimiter can be split across calls. The parser returns the number of input
bytes it consumed and leaves its state ready for the next fragment.

## Validation

The parser:

- caps a chunk-size line at 256 bytes
- accepts hexadecimal sizes and ignores chunk extensions
- checks the CRLF after each chunk
- rejects a chunk whose cumulative decoded size exceeds `maxSize`
- returns a structured error for malformed framing

The default maximum decoded body size is 50 MiB. Passing zero to
`initWithMaxSize:` disables that parser limit and should be reserved for a
caller that imposes an equivalent bound elsewhere.

## Memory behavior

Incremental parsing avoids converting binary payloads into one large string or
rescanning all prior input after every read. The current implementation still
appends decoded bytes to `NSMutableData` and returns a complete `NSData` body.
Its memory use therefore grows with the accepted body size.

Use `HttpStreamingBody` for routes that need to spill large content to a
temporary file. Do not describe `HttpChunkedBodyParser` as zero-copy or
constant-memory until its output contract changes.

## Test cases

Chunked-parser tests should cover:

- every split point in the size line and CRLF delimiters
- chunk extensions
- a zero-length body
- invalid hex digits and missing delimiters
- cumulative size overflow
- extra bytes after the completed body
- reset and reuse

The parser should be tested independently of the socket layer, then exercised
through HTTP integration tests to confirm status-code and connection-close
behavior.
