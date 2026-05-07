# HeaderDoc audit: Sync & Relay semantic group

## Summary

- Total files audited: 45
- Quality A: 4
- Quality B: 18
- Quality C: 18
- Quality D: 5

### Main recurring issues

- Most public headers are only partially documented: missing `@param` / `@return` coverage on initializers and helper methods.
- Several `.m` files rely on inline comments only, and many of those comments restate code flow instead of explaining intent or invariants.
- A few files have solid HeaderDoc blocks but still lack `@see` cross-references to related transport / relay classes.
- A small number of implementation files have no comments at all.

## File-by-file findings

| File | Quality | Specific issues found |
| --- | --- | --- |
| `Sync/Firehose/Firehose.h` | B | Public factory/accessor methods are undocumented; missing `@param` / `@return` blocks for the subscription and event constructors; no `@see` links to related Firehose/relay types. |
| `Sync/Firehose/Firehose.m` | C | Only inline comments; no file HeaderDoc block; comments mostly describe control flow instead of protocol intent. |
| `Sync/Firehose/FirehoseCARBuilder.h` | D | No comments or HeaderDoc at all. |
| `Sync/Firehose/FirehoseCARBuilder.m` | C | Only one inline note; no top-level HeaderDoc; comments do not explain why CAR assembly choices were made. |
| `Sync/Firehose/FirehoseProtocolSession.h` | D | No comments or HeaderDoc at all. |
| `Sync/Firehose/FirehoseProtocolSession.m` | D | No comments at all. |
| `Sync/Firehose/SubscribeReposHandler.h` | B | Core public methods are documented, but `init`/initializer coverage is incomplete; missing `@param` / `@return` blocks on several entry points; no `@see` references to `FirehoseCARBuilder` / `RelayMetrics`. |
| `Sync/Firehose/SubscribeReposHandler.m` | C | Inline comments dominate; several comments restate implementation details (for example the event-queue dispatch notes) rather than explaining design intent. |
| `Sync/Relay/EventFormatter.h` | B | HeaderDoc is present, but the encode/decode methods are missing `@param` / `@return` tags; no `@see` cross-references to protocol/session helpers. |
| `Sync/Relay/EventFormatter.m` | C | Only inline comments; comments are largely explanatory of the code path and internal sanitization rather than documenting behavior at the API level. |
| `Sync/Relay/RelayAPIHandler.h` | A | Strong HeaderDoc coverage overall; minor gap is the lack of `@see` links to related metrics / upstream manager types. |
| `Sync/Relay/RelayAPIHandler.m` | C | Inline comments only; route comments mostly narrate what the code does instead of why each endpoint is structured that way. |
| `Sync/Relay/RelayClient.h` | B | Second initializer is undocumented; public methods lack `@param` / `@return` blocks; no `@see` references to the Firehose transport path. |
| `Sync/Relay/RelayClient.m` | C | Inline comments only; repeated "Capture strongly" notes and phase labels restate implementation details. |
| `Sync/Relay/RelayConfiguration.h` | B | File header exists, but the public API is effectively undocumented; missing method-level HeaderDoc and `@param` / `@return` coverage. |
| `Sync/Relay/RelayConfiguration.m` | D | No comments or HeaderDoc at all. |
| `Sync/Relay/RelayDownstreamHandler.h` | A | Well-formed HeaderDoc for the public API; minor gap is the lack of `@see` cross-references to upstream/resequencing collaborators. |
| `Sync/Relay/RelayDownstreamHandler.m` | B | File header is present, but the implementation relies on inline comments only; several comments are procedural or restate code paths. |
| `Sync/Relay/RelayEventBuffer.h` | B | Top-level docs exist, but all public methods are undocumented; missing `@param` / `@return` blocks. |
| `Sync/Relay/RelayEventBuffer.m` | C | Only inline comments; comments describe pruning mechanics but do not document invariants or retention behavior at the API boundary. |
| `Sync/Relay/RelayEventFilter.h` | B | Partial HeaderDoc only; public setters/query methods lack `@param` / `@return` tags. |
| `Sync/Relay/RelayEventFilter.m` | C | Inline comments only; comments mostly mirror conditional logic. |
| `Sync/Relay/RelayEventValidator.h` | B | HeaderDoc is present, but validation methods are undocumented; missing `@param` / `@return` blocks and `@see` references to MST / signature helpers. |
| `Sync/Relay/RelayEventValidator.m` | C | Inline comments only; comments are mostly placeholder explanations and restatements of the code, with some LLM-ish phrasing. |
| `Sync/Relay/RelayMetrics.h` | B | File header plus one documented method, but most recorders/properties are undocumented; `renderPrometheusMetrics` also lacks `@return` documentation. |
| `Sync/Relay/RelayMetrics.m` | C | Inline comments only; the histogram/backfill note is a stub and the Prometheus section largely describes output rather than intent. |
| `Sync/Relay/RelayRepoStateManager.h` | B | File header is present, but per-method HeaderDoc is missing for the repo state API; no `@param` / `@return` blocks. |
| `Sync/Relay/RelayRepoStateManager.m` | C | Only inline comments; persistence comments are speculative and do not explain the intended state model. |
| `Sync/Relay/RelayUpstreamManager.h` | B | Top doc is solid, but most public mutators/query methods are undocumented; missing `@param` / `@return` coverage. |
| `Sync/Relay/RelayUpstreamManager.m` | C | Inline comments only; many comments explain normalization or control flow that is already obvious from the code. |
| `Sync/WebSocket/PDSWebSocketNetworkAdapter.h` | A | Complete HeaderDoc for the sole public initializer; no major issues, though a few `@see` links would improve navigation. |
| `Sync/WebSocket/PDSWebSocketNetworkAdapter.m` | B | File HeaderDoc is partial and methods are undocumented; inline comments explain mechanics rather than intent. |
| `Sync/WebSocket/PDSWebSocketServer.h` | B | File docs are good, but the second initializer is undocumented and the API is missing full `@param` / `@return` coverage. |
| `Sync/WebSocket/PDSWebSocketServer.m` | B | File header is present, but the implementation is only inline-commented; no method-level HeaderDoc and some comments are procedural. |
| `Sync/WebSocket/PDSWebSocketTransport.h` | A | Strong HeaderDoc across the protocol and block typedefs; no major issues, aside from missing `@see` cross-references. |
| `Sync/WebSocket/WebSocketCodec.h` | C | Inline comments only; no file HeaderDoc, and the comments are simple section labels rather than documentation. |
| `Sync/WebSocket/WebSocketCodec.m` | C | Inline comments only; comments mostly narrate frame-processing steps that the code already makes explicit. |
| `Sync/WebSocket/WebSocketConnection.h` | B | File header exists, but the public API lacks `@param` / `@return` tags and several methods are only one-line summaries. |
| `Sync/WebSocket/WebSocketConnection.m` | C | Inline comments only; comments are mostly operational notes and restatements of the control flow. |
| `Sync/WebSocket/WebSocketHeartbeatPolicy.h` | C | Inline comments only; no file HeaderDoc and the comments are just implementation labels. |
| `Sync/WebSocket/WebSocketHeartbeatPolicy.m` | C | Inline comments only; comments restate the heartbeat state machine rather than documenting policy rationale. |
| `Sync/WebSocket/WebSocketProtocolSession.h` | C | Inline comments only; no HeaderDoc for the session action types or configuration API. |
| `Sync/WebSocket/WebSocketProtocolSession.m` | D | No comments or HeaderDoc at all. |
| `Sync/WebSocket/WebSocketServer.h` | B | File header is present, but the public API is only partially documented; `broadcastMessage:toConnectionsMatching:` lacks `@param` coverage. |
| `Sync/WebSocket/WebSocketServer.m` | B | File header is partial, but method-level documentation is missing; inline comments mostly explain implementation details. |

## Notes

- No source files were edited.
- The overall pattern is consistent: headers are often partially documented, while implementation files tend to fall into either inline-only commentary or no commentary at all.
