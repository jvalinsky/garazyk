# Laweta Package - Code Review Research Findings

This document synthesizes research into best practices, known pitfalls, and design patterns relevant to the `laweta` package (Docker Engine API over Unix socket in Deno/TypeScript) to inform its codebase review.

## 1. Deno Unix Socket Stability (2025-2026)
When integrating Deno with Unix sockets via `Deno.createHttpClient`, several stability concerns must be addressed:
- **`URIError` in Deno v2.4.x**: Connecting to a `unix://` socket can trigger "relative URL without a base" errors. Workaround: Ensure absolute paths are used and pass a dummy base URL (e.g., `http://localhost/`) if using `fetch`.
- **Native Memory Leaks**: An open issue (as of May 2026, #33848) involves the Rust-side bridge leaking memory with in-memory channels/Unix sockets. RSS grows continuously per request. To prevent Out of Memory (OOM) crashes in long-running processes, consider avoiding the Node compatibility layer (`node:http`) and monitor memory usage.
- **Resource Management**: It is critical to either reuse a single globally instantiated `HttpClient` or rigorously call `client.close()` after each request. Failure to do so leads to file descriptor exhaustion (`EMFILE`).

## 2. Docker API & Logging Protocol
- **Log Stream Multiplexing (`tty: false`)**: The Docker log stream uses an 8-byte header for multiplexed output (1 byte stream type, 3 reserved bytes, 4 bytes big-endian payload length). The parser must implement strict boundary checks—using a read-full approach for the 8 bytes and the payload—to handle network fragmentation properly. Note that multiplexing is disabled entirely if the container is run with `tty: true`.
- **NDJSON Parsing Edge Cases**: The stream of events from Docker API endpoints (like `/events`) requires robust NDJSON parsing:
  - **Buffer Limits**: A hard limit must be enforced on the leftover buffer length to prevent memory exhaustion (DoS attacks or malformed streams) if no newline is encountered.
  - **Fragmentation**: Network chunks may not align with newline characters; the parser must preserve partial lines accurately across chunks.
  - **Escaped vs. Literal Newlines**: Ensure the parser strictly splits on literal `\n` bytes, not escaped `\n` characters within JSON strings.

## 3. The Sans-IO Pattern in TypeScript
To make the library resilient, portable, and highly testable, the **sans-IO** pattern is recommended for protocol parsing:
- Implement the Docker Engine API protocol (like the multiplexed log parser) as a pure synchronous state machine.
- Accept incoming `Uint8Array` data, update internal buffers, and return actionable events or outgoing byte chunks.
- Abstract the `socket` and network layer into a separate "driver" rather than embedding `async` network calls deeply within the parser logic. This resolves "Function Coloring" and simplifies testing edge cases like partial reads and timeouts.

## 4. Docker Health Status Unreliability
When monitoring containers via the Docker events stream:
- The `health_status` event is notoriously unreliable in standalone Docker. Events are sometimes dropped, especially during rapid state transitions or if the health check hangs.
- Standalone Docker does not automatically recover `unhealthy` containers.
- **Actionable Insight**: For critical state monitoring, do not rely solely on the event stream. Augment the system with active API polling (e.g., `docker inspect` or `/containers/{id}/json`) to maintain an accurate view of `State.Health`.

## 5. Docker Engine API v1.43 Changes
While direct searches for v1.43 endpoint deprecations did not yield specific sweeping changes in the short output, the code review must validate all used endpoints against the target API specification version to ensure no deprecated fields, behaviors, or unhandled structural changes have been introduced.
