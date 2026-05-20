# Gruszka Package Research: Code Review Findings

Based on recent best practices and security advisories (2024-2025), the following areas should be carefully scrutinized during the code review of the `gruszka` package (XRPC client and DAG-CBOR firehose):

## 1. Security Considerations: DAG-CBOR Decoding
Decoding untrusted binary data from the ATProto firehose requires strict security boundaries.
- **Recursion Depth Limits:** Ensure the decoder enforces a hard limit on nested arrays and maps to prevent Call Stack Exhaustion (Denial of Service).
- **Memory Exhaustion (OOM):** The decoder must not preallocate large arrays or buffers based solely on untrusted size hints found in CBOR headers.
- **Prototype Pollution Prevention:** Validate that the decoder actively strips or rejects magic keys like `__proto__` and `constructor` to prevent pollution of JavaScript objects.
- **Strict Canonical Decoding:** The decoder should reject non-canonical formats and unexpected tags (allowing only Tag 42 for CIDs) to prevent signature bypasses and malleability issues.

## 2. XRPC Client Architecture & TypeScript Best Practices
- **Authentication Modernization:** In 2025, the ecosystem has shifted heavily toward OAuth-first authentication. Verify if the client supports or can interoperate with standard OAuth session managers, moving away from legacy App Passwords where appropriate.
- **Lexicon Type Generation:** Code generation from lexicons is standard practice. Review whether `gruszka` provides a type-safe generated interface (similar to `@atproto/lex-cli` outputs) rather than relying on loose typing or `any`.
- **Proxy Type Inference:** If the client uses JavaScript `Proxy` objects to construct dynamic nested method chains (e.g., `client.app.bsky.feed...`), carefully review the TypeScript definitions. Ensuring accurate recursive type inference that maps string paths to actual method signatures without losing type safety is complex but essential.

## 3. Network Resiliency & State Management
- **Firehose Cursor Management:** For WebSocket firehose ingestion (e.g., `com.atproto.sync.subscribeRepos`), the client must reliably track and persist the sequence `cursor`. Upon network disconnection and reconnection, it must resume from the exact last-processed cursor to prevent data loss or processing the same events twice.
- **Idempotency & Retry Safety:** Review the HTTP retry logic for XRPC calls. While `GET` requests (queries) are idempotent and generally safe to retry on network failures, `POST` requests (procedures/mutations) are not natively idempotent in XRPC. Blindly retrying mutations (like creating a record) can lead to duplicates. Ensure retries are intelligently restricted to safe methods or utilize idempotency keys if available.
