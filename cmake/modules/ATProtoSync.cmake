# Explicit source manifest for ATProtoSync.
# Entries are repository-relative; CMake validates existence, ownership, and
# build-host independence before resolving them into target source lists.
set(ATPROTO_SYNC_MANIFEST
  "Garazyk/Sources/Sync/Firehose/Firehose.m"
  "Garazyk/Sources/Sync/Firehose/FirehoseCARBuilder.m"
  "Garazyk/Sources/Sync/Firehose/FirehoseProtocolSession.m"
  "Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m"
  "Garazyk/Sources/Sync/Relay/EventFormatter.m"
  "Garazyk/Sources/Sync/Relay/RelayAPIHandler.m"
  "Garazyk/Sources/Sync/Relay/RelayClient.m"
  "Garazyk/Sources/Sync/Relay/RelayConfiguration.m"
  "Garazyk/Sources/Sync/Relay/RelayDownstreamHandler.m"
  "Garazyk/Sources/Sync/Relay/RelayEventBuffer.m"
  "Garazyk/Sources/Sync/Relay/RelayEventFilter.m"
  "Garazyk/Sources/Sync/Relay/RelayEventValidator.m"
  "Garazyk/Sources/Sync/Relay/RelayMetrics.m"
  "Garazyk/Sources/Sync/Relay/RelayRepoStateManager.m"
  "Garazyk/Sources/Sync/Relay/RelayUpstreamManager.m"
  "Garazyk/Sources/Sync/WebSocket/PDSWebSocketNetworkAdapter.m"
  "Garazyk/Sources/Sync/WebSocket/PDSWebSocketServer.m"
  "Garazyk/Sources/Sync/WebSocket/WebSocketCodec.m"
  "Garazyk/Sources/Sync/WebSocket/WebSocketConnection.m"
  "Garazyk/Sources/Sync/WebSocket/WebSocketHeartbeatPolicy.m"
  "Garazyk/Sources/Sync/WebSocket/WebSocketProtocolSession.m"
  "Garazyk/Sources/Sync/WebSocket/WebSocketServer.m"
)
