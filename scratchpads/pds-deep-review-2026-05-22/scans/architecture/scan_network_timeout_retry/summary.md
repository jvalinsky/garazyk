# Objective-C Network Timeout/Retry Scan

- Root: .
- Scan path: ./Garazyk/Sources/Network
- Generated: 2026-05-22T18:10:10Z

## Counts
- IO/connect signals: 56
- Timeout signals: 120
- Retry/backoff signals: 21
- Cancel/close signals: 66
- Transient error signals: 6

## Prioritize first (IO files without timeout signal)
- ./Garazyk/Sources/Network/ATProtoNetworkTransport.h
- ./Garazyk/Sources/Network/Http1PipelinePolicy.h
- ./Garazyk/Sources/Network/HttpConnectionIOCoordinator.h
- ./Garazyk/Sources/Network/HttpProtocolSession.h
- ./Garazyk/Sources/Network/HttpResponse.h
- ./Garazyk/Sources/Network/HttpResponseSender.h
- ./Garazyk/Sources/Network/HttpResponseSender.m
- ./Garazyk/Sources/Network/HttpStreamingBody.h
- ./Garazyk/Sources/Network/HttpStreamingBody.m
- ./Garazyk/Sources/Network/XrpcAuthHelper.m
- ./Garazyk/Sources/Network/XrpcChatBskyConvoPack.m
- ./Garazyk/Sources/Network/XrpcSyncPack.m

## Secondary priority (retry files without timeout signal)
- ./Garazyk/Sources/Network/ATProtoHttpRelayAPIRoutePack.m
- ./Garazyk/Sources/Network/PDSHttpPDSAdminRoutePack.m
- ./Garazyk/Sources/Network/WebSocketUpgradeHandler.h
- ./Garazyk/Sources/Network/XrpcServerPack.m

## Notes
- Heuristics identify candidates only; verify control flow and idempotency.
