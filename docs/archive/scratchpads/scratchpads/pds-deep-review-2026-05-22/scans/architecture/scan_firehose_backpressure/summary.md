# Objective-C Firehose Ordering/Backpressure Scan

- Root: .
- Scan path: ./Garazyk/Sources/Sync
- Generated: 2026-05-22T18:10:10Z

## Counts
- Ordering/cursor signals: 314
- Backpressure/buffer signals: 87
- Emit/write signals: 432
- Retry/replay signals: 25
- Lock/sync signals: 44

## Prioritize first (ordering + backpressure same file)
- ./Garazyk/Sources/Sync/Firehose/Firehose.h
- ./Garazyk/Sources/Sync/Firehose/FirehoseCARBuilder.m
- ./Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.h
- ./Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m
- ./Garazyk/Sources/Sync/Relay/RelayClient.h
- ./Garazyk/Sources/Sync/Relay/RelayDownstreamHandler.h
- ./Garazyk/Sources/Sync/Relay/RelayDownstreamHandler.m
- ./Garazyk/Sources/Sync/Relay/RelayEventBuffer.h
- ./Garazyk/Sources/Sync/Relay/RelayEventBuffer.m
- ./Garazyk/Sources/Sync/Relay/RelayEventValidator.h
- ./Garazyk/Sources/Sync/Relay/RelayMetrics.h
- ./Garazyk/Sources/Sync/Relay/RelayMetrics.m

## Secondary priority (emitters without backpressure signal)
- ./Garazyk/Sources/Sync/Firehose/Firehose.m
- ./Garazyk/Sources/Sync/Relay/EventFormatter.h
- ./Garazyk/Sources/Sync/Relay/RelayClient.m
- ./Garazyk/Sources/Sync/Relay/RelayUpstreamManager.m
- ./Garazyk/Sources/Sync/WebSocket/PDSWebSocketNetworkAdapter.h
- ./Garazyk/Sources/Sync/WebSocket/PDSWebSocketNetworkAdapter.m
- ./Garazyk/Sources/Sync/WebSocket/PDSWebSocketServer.m
- ./Garazyk/Sources/Sync/WebSocket/WebSocketCodec.h
- ./Garazyk/Sources/Sync/WebSocket/WebSocketCodec.m
- ./Garazyk/Sources/Sync/WebSocket/WebSocketHeartbeatPolicy.h
- ./Garazyk/Sources/Sync/WebSocket/WebSocketHeartbeatPolicy.m
- ./Garazyk/Sources/Sync/WebSocket/WebSocketServer.h
- ./Garazyk/Sources/Sync/WebSocket/WebSocketServer.m

## Notes
- File-level heuristics only; verify per-connection behavior manually.
