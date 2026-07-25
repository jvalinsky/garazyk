# Gruszka: XRPC Client, DAG-CBOR Firehose, Code-Gen — Research Plan

## Package Summary
Strongly typed AT Protocol XRPC client with generated lexicon methods, firehose WebSocket client, and transport layer with retry logic.

## Key Techniques
1. **DAG-CBOR decoding** — `@ipld/dag-cbor` + `cborg` for firehose frame parsing
2. **WebSocket firehose client** — `FirehoseClient` with `subscribeRepos` subscription
3. **XRPC transport with retry** — `TransportLayer` with configurable retry on 429/502/503/504
4. **Generated client from lexicons** — `createGeneratedClient()` builds nested namespace client
5. **Agent proxy pattern** — `AgentProxy` wraps `GeneratedClient` with session management
6. **Binary XRPC support** — `postBinary()` and `getBinary()` for blob/CAR operations
7. **Response history** — `lastResponses` ring buffer (20 entries) for debugging
8. **Namespace clients** — Hand-written `AccountsClient`, `AdminClient`, etc. alongside generated client

## Research Queries (for sub-agents)

### Q1: DAG-CBOR decoding correctness and security
- Search: "ipld dag-cbor JavaScript decoding security vulnerabilities"
- Search: "cborg library DAG-CBOR decodeFirst best practices"
- Search: "ATProto subscribeRepos DAG-CBOR frame parsing reference implementation"
- Focus: Known issues with `@ipld/dag-cbor` and `cborg`, correct frame parsing for firehose, CID handling

### Q2: ATProto XRPC client best practices
- Search: "ATProto XRPC client TypeScript best practices 2025"
- Search: "atproto xrpc client retry idempotency best practices"
- Focus: Reference implementations (like `@atproto/xrpc`), how they handle auth, retry, binary, error mapping

### Q3: Lexicon code generation patterns
- Search: "ATProto lexicon code generation TypeScript"
- Search: "atproto lexicon type generation approach comparison"
- Focus: How the official `@atproto/lexicon` codegen works vs gruszka's approach, type safety gaps

### Q4: WebSocket firehose reliability
- Search: "ATProto firehose WebSocket reconnection cursor"
- Search: "Deno WebSocket firehose client backpressure handling"
- Focus: The current `FirehoseClient` has no reconnection, cursor tracking, or backpressure — is this intentional for test-only use?

### Q5: Transport layer retry safety
- Search: "HTTP retry idempotency POST mutation safety"
- Search: "XRPC procedure retry semantics atproto"
- Focus: The transport retries GET but not POST by default — is this correct for all XRPC procedures? Are there idempotent procedures that should be retried?

### Q6: Agent proxy type safety
- Search: "TypeScript dynamic proxy pattern type safety"
- Search: "TypeScript Proxy object nested method chain type inference"
- Focus: The `AgentProxy` type uses recursive mapped types — are there type holes? The `createAgentProxy` uses `Object.assign` + `as unknown as AgentProxy`

## Code Review Concerns to Investigate
- `FirehoseClient.events` is a mutable public array — race condition if `collect()` is called concurrently
- `FirehoseClient.subscribe()` resolves the promise on error/close — no error propagation
- `TransportLayer.request()` reads `response.text()` then tries `JSON.parse` — could fail for binary responses
- `AgentSession` stores JWTs in memory — no refresh token rotation
- `isQueryMethod()` falls back to regex heuristic (`/^(get|list|resolve|describe)/i`) for unknown methods
- `RawCaller.call()` uses `any` types extensively — type safety gap between generated and raw callers
- `createAgentProxy` patches `createAccount` and `login` onto the generated client — fragile if generated client changes

## Deciduous Link
- Node 282: gruszka action
