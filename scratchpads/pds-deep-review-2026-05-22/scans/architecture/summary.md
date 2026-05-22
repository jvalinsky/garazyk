# Objective-C Architecture & Reliability Audit — Combined Summary

- Root: .
- Generated: 2026-05-22T18:10:17Z

## scan_gnustep_regressions
### Objective-C GNUstep Regression Scan

- Root: .
- Scan path: ./Garazyk/Sources
- Generated: 2026-05-22T18:10:09Z

## Counts (excluding Compat/)
- macOS-sensitive API signals: 309
- Platform-sensitive import signals: 38
- Linux guard signals: 67

## Prioritize first (mac API without guard signal)
- ./Garazyk/Sources/Admin/PDSAdminAuth.m
- ./Garazyk/Sources/App/AppDelegate.h
- ./Garazyk/Sources/App/PDSController.m
- ./Garazyk/Sources/App/main.m
- ./Garazyk/Sources/AppView/Server/Backfill/AppViewBackfillWorker.m
- ./Garazyk/Sources/AppView/Services/ContactService.m
- ./Garazyk/Sources/AppView/Services/FeedService.m
- ./Garazyk/Sources/Auth/JWT.m
- ./Garazyk/Sources/Auth/OAuth2Handler.m
- ./Garazyk/Sources/Auth/OAuthProvider/OAuthProvider.m
- ./Garazyk/Sources/Auth/PDSAppleKeyManager.h
- ./Garazyk/Sources/Auth/PDSOpenSSLKeyManager.m
- ./Garazyk/Sources/Auth/PKCEUtil.m
- ./Garazyk/Sources/Auth/Secp256k1.m
- ./Garazyk/Sources/Blob/PDSCloudStorageBlobProvider.h
- ./Garazyk/Sources/Blob/PDSCloudStorageBlobProvider.m
- ./Garazyk/Sources/CLI/PDSCLIHealthCommand.m
- ./Garazyk/Sources/Chat/Server/ChatAuthManager.m
- ./Garazyk/Sources/Core/ATProtoDagCBOR.m
- ./Garazyk/Sources/Core/CID.m
- ./Garazyk/Sources/Core/DID.h
- ./Garazyk/Sources/Database/Service/ServiceDatabases.m
- ./Garazyk/Sources/Email/PDSKeychainSecretsProvider.m
- ./Garazyk/Sources/Germ/Server/Identity/GermIdentityService.m
- ./Garazyk/Sources/Mikrus/MikrusXrpcRoutePack.m
- ./Garazyk/Sources/Network/SSLPinningManager.h
- ./Garazyk/Sources/Network/SSLPinningManager.m
- ./Garazyk/Sources/Network/WebSocketUpgradeHandler.m
- ./Garazyk/Sources/Network/XrpcAdminPack.m
- ./Garazyk/Sources/Network/XrpcIdentityPack.m
- ./Garazyk/Sources/Network/XrpcProxyHandler.m
- ./Garazyk/Sources/Network/XrpcRepoPack.m
- ./Garazyk/Sources/Network/XrpcServerPack.m
- ./Garazyk/Sources/PLC/DIDPLCResolver.m
- ./Garazyk/Sources/PLC/PLCRotationKeyManager.m
- ./Garazyk/Sources/Repository/MST.m
- ./Garazyk/Sources/Repository/STAR.m
- ./Garazyk/Sources/Security/PDSBiometricKeychain.m
- ./Garazyk/Sources/Security/PDSKeyEnvelope.m
- ./Garazyk/Sources/Services/PDS/PDSBlobService.m
- ./Garazyk/Sources/Services/PDS/PDSRecordService.m
- ./Garazyk/Sources/Services/PDS/PDSRelayService.h
- ./Garazyk/Sources/Sync/Relay/EventFormatter.m
- ./Garazyk/Sources/Sync/Relay/RelayUpstreamManager.m
- ./Garazyk/Sources/Sync/WebSocket/WebSocketConnection.m
- ./Garazyk/Sources/Video/VideoRemoteBlobUploader.m

## Secondary priority (platform import without guard signal)
- ./Garazyk/Sources/App/server_main.m
- ./Garazyk/Sources/AppView/Services/ContactService.m
- ./Garazyk/Sources/Auth/PDSAppleKeyManager.h
- ./Garazyk/Sources/Auth/PDSNonceManager.m
- ./Garazyk/Sources/Auth/PKCEUtil.m
- ./Garazyk/Sources/Auth/TOTPGenerator.m
- ./Garazyk/Sources/Auth/Verifier/AuthVerifier.m
- ./Garazyk/Sources/Core/ATProtoCBORSerialization.m
- ./Garazyk/Sources/Core/CID.m
- ./Garazyk/Sources/Core/TID.m
- ./Garazyk/Sources/Database/Service/ServiceDatabases.m
- ./Garazyk/Sources/Debug/GZLogger.m
- ./Garazyk/Sources/Email/PDSKeychainSecretsProvider.m
- ./Garazyk/Sources/Germ/Server/Identity/GermIdentityService.m
- ./Garazyk/Sources/Network/SSLPinningManager.m
- ./Garazyk/Sources/Repository/CAR.m
- ./Garazyk/Sources/Repository/CBOR.m
- ./Garazyk/Sources/Security/PDSBiometricKeychain.h
- ./Garazyk/Sources/Security/PDSKeyEnvelope.m

## Notes
- Some wrappers rely on build-system include path rather than file-local guards.
- Confirm intended compat pattern before filing findings.

## scan_service_boundaries
### Objective-C Service Boundary Scan

- Root: .
- Services path: ./Sources/App/Services
- Security path: ./Garazyk/Sources/Security
- Generated: 2026-05-22T18:10:09Z

## Counts
- Service files: 0
- Authz signals: 12
- Privileged-operation signals: 6
- External-input signals: 38

## Prioritize first (privileged service files without auth signal)
- none

## Secondary priority (service files without auth signal)
- none

## Notes
- Upstream authorization may exist; verify boundary ownership before filing findings.

## scan_xrpc_contracts
### Objective-C XRPC Contract Scan

- Root: .
- Scan path: ./Garazyk/Sources
- Generated: 2026-05-22T18:10:09Z

## Counts
- Method registration signals: 1177
- Unique NSIDs (registry grep): 0
- Auth enforcement signals: 381
- Validation signals: 1193
- Error-shape signals: 3586

## Prioritize first (method files without auth signal)
- ./Garazyk/Sources/App/NodeInfo/NodeInfoHandler.h
- ./Garazyk/Sources/App/NodeInfo/NodeInfoHandler.m
- ./Garazyk/Sources/App/NodeInfo/NodeInfoProvider.h
- ./Garazyk/Sources/App/PDSApplication.m
- ./Garazyk/Sources/App/server_main.m
- ./Garazyk/Sources/AppView/Server/Admin/AppViewAdminRoutePack.h
- ./Garazyk/Sources/AppView/Server/AppViewRuntime.m
- ./Garazyk/Sources/AppView/Server/Backfill/AppViewBackfillOrchestrator.h
- ./Garazyk/Sources/AppView/Server/Hooks/AppViewIndexHookRegistry.h
- ./Garazyk/Sources/AppView/Server/Hooks/AppViewIndexHookRegistry.m
- ./Garazyk/Sources/AppView/Server/Lexicon/AppViewCustomQueryRegistry.h
- ./Garazyk/Sources/AppView/Server/Lexicon/AppViewCustomQueryRegistry.m
- ./Garazyk/Sources/AppView/Server/Lexicon/AppViewLexiconEndpointGenerator.h
- ./Garazyk/Sources/AppView/Server/Lexicon/AppViewLexiconEndpointGenerator.m
- ./Garazyk/Sources/AppView/Services/NotificationService.h
- ./Garazyk/Sources/AppView/Services/NotificationService.m
- ./Garazyk/Sources/Auth/PDSSecondFactorService.m
- ./Garazyk/Sources/Auth/WebAuthnRegistrationHandler.h
- ./Garazyk/Sources/Auth/WebAuthnRegistrationHandler.m
- ./Garazyk/Sources/CLI/PDSCLIAccountCommand.m
- ./Garazyk/Sources/CLI/PDSCLIAccountManager.m
- ./Garazyk/Sources/CLI/PDSCLIDefinitions.h
- ./Garazyk/Sources/CLI/PDSCLIDispatcher.h
- ./Garazyk/Sources/CLI/PDSCLIDispatcher.m
- ./Garazyk/Sources/CLI/PDSCLIRegisterAll.m
- ./Garazyk/Sources/CLI/PDSCLIServeCommand.m
- ./Garazyk/Sources/Chat/Server/ChatRuntime.m
- ./Garazyk/Sources/Compat/PlatformShims/CoreFoundation/CFBase.h
- ./Garazyk/Sources/Compat/PlatformShims/CrashReporting/PDSCrashReporter.h
- ./Garazyk/Sources/Compat/PlatformShims/SignalHandling/PDSSignalManager.h
- ./Garazyk/Sources/Compat/PlatformShims/SignalHandling/PDSSignalManager.m
- ./Garazyk/Sources/Compat/XCTest/XCTest.h
- ./Garazyk/Sources/Core/ATProtoServiceContainer.h
- ./Garazyk/Sources/Core/ATProtoServiceContainer.m
- ./Garazyk/Sources/Core/PDSProviderRegistry.h
- ./Garazyk/Sources/Core/PDSProviderRegistry.m
- ./Garazyk/Sources/Database/Migrations/PDSMigrationManager.h
- ./Garazyk/Sources/Database/Migrations/PDSMigrationManager.m
- ./Garazyk/Sources/Email/PDSEmailProviderFactory.h
- ./Garazyk/Sources/Email/PDSEmailProviderFactory.m
- ./Garazyk/Sources/Federation/FederationClient.m
- ./Garazyk/Sources/Germ/Server/Runtime/GermRuntime.m
- ./Garazyk/Sources/Germ/Server/Services/GermMailboxService.h
- ./Garazyk/Sources/Germ/Server/Services/GermMailboxService.m
- ./Garazyk/Sources/Germ/Server/XrpcGermIdentityPack.h
- ./Garazyk/Sources/Germ/Server/XrpcGermIdentityPack.m
- ./Garazyk/Sources/Germ/Server/XrpcGermMailboxPack.h
- ./Garazyk/Sources/Germ/Server/XrpcGermMailboxPack.m
- ./Garazyk/Sources/Lexicon/ATProtoLexiconRegistry.h
- ./Garazyk/Sources/Lexicon/ATProtoLexiconRegistry.m
- ./Garazyk/Sources/MediaCore/ATProtoMediaServiceRuntime.m
- ./Garazyk/Sources/MediaCore/ATProtoMediaXrpcPack.h
- ./Garazyk/Sources/MediaCore/ATProtoMediaXrpcPack.m
- ./Garazyk/Sources/Mikrus/MikrusRuntime.m
- ./Garazyk/Sources/Mikrus/MikrusXrpcRoutePack.h
- ./Garazyk/Sources/Mikrus/MikrusXrpcRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpMSTViewerRoutePack.h
- ./Garazyk/Sources/Network/ATProtoHttpMSTViewerRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpMetricsRoutePack.h
- ./Garazyk/Sources/Network/ATProtoHttpMetricsRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpNodeInfoRoutePack.h
- ./Garazyk/Sources/Network/ATProtoHttpNodeInfoRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpOAuthDemoRoutePack.h
- ./Garazyk/Sources/Network/ATProtoHttpOAuthDemoRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpOAuthRoutePack.h
- ./Garazyk/Sources/Network/ATProtoHttpOAuthRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpRelayAPIRoutePack.h
- ./Garazyk/Sources/Network/ATProtoHttpRelayAPIRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpServerBuilder.h
- ./Garazyk/Sources/Network/ATProtoHttpServerBuilder.m
- ./Garazyk/Sources/Network/ATProtoHttpWellKnownRoutePack.h
- ./Garazyk/Sources/Network/ATProtoHttpWellKnownRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpXrpcRoutePack.h
- ./Garazyk/Sources/Network/ATProtoHttpXrpcRoutePack.m
- ./Garazyk/Sources/Network/AppViewXRpcRoutePack.h
- ./Garazyk/Sources/Network/HttpRouter.m
- ./Garazyk/Sources/Network/PDSHttpPDSAdminRoutePack.h
- ./Garazyk/Sources/Network/PDSHttpPDSAdminRoutePack.m
- ./Garazyk/Sources/Network/RelayXrpcRoutePack.h
- ./Garazyk/Sources/Network/RelayXrpcRoutePack.m
- ./Garazyk/Sources/Network/XrpcAdminPack.h
- ./Garazyk/Sources/Network/XrpcAdminPack.m
- ./Garazyk/Sources/Network/XrpcAppBskyActorPack.h
- ./Garazyk/Sources/Network/XrpcAppBskyAgeAssurancePack.h
- ./Garazyk/Sources/Network/XrpcAppBskyBookmarksPack.h
- ./Garazyk/Sources/Network/XrpcAppBskyContactPack.h
- ./Garazyk/Sources/Network/XrpcAppBskyDraftsPack.h
- ./Garazyk/Sources/Network/XrpcAppBskyFeedPack.m
- ./Garazyk/Sources/Network/XrpcAppBskyGraphPack.m
- ./Garazyk/Sources/Network/XrpcAppBskyNotificationPack.h
- ./Garazyk/Sources/Network/XrpcAppBskyPack.h
- ./Garazyk/Sources/Network/XrpcAppBskyPack.m
- ./Garazyk/Sources/Network/XrpcAppBskyProxyMethodPack.h
- ./Garazyk/Sources/Network/XrpcAppBskyProxyMethodPack.m
- ./Garazyk/Sources/Network/XrpcAppBskyUnspeccedPack.m
- ./Garazyk/Sources/Network/XrpcChatBskyActorPack.h
- ./Garazyk/Sources/Network/XrpcChatBskyConvoPack.m
- ./Garazyk/Sources/Network/XrpcChatBskyGroupPack.h
- ./Garazyk/Sources/Network/XrpcHandler.h
- ./Garazyk/Sources/Network/XrpcHandler.m
- ./Garazyk/Sources/Network/XrpcIdentityPack.h
- ./Garazyk/Sources/Network/XrpcIdentityPack.m
- ./Garazyk/Sources/Network/XrpcLabelPack.h
- ./Garazyk/Sources/Network/XrpcLexiconResolver.h
- ./Garazyk/Sources/Network/XrpcLexiconResolver.m
- ./Garazyk/Sources/Network/XrpcMethodRegistry.h
- ./Garazyk/Sources/Network/XrpcMethodRegistry.m
- ./Garazyk/Sources/Network/XrpcModerationPack.h
- ./Garazyk/Sources/Network/XrpcModerationPack.m
- ./Garazyk/Sources/Network/XrpcRepoPack.m
- ./Garazyk/Sources/Network/XrpcRoutePack.h
- ./Garazyk/Sources/Network/XrpcRoutePackRegistrar.h
- ./Garazyk/Sources/Network/XrpcRoutePackRegistrar.m
- ./Garazyk/Sources/Network/XrpcRoutePackServices.h
- ./Garazyk/Sources/Network/XrpcServerPack.h
- ./Garazyk/Sources/Network/XrpcServerPack.m
- ./Garazyk/Sources/Network/XrpcSyncPack.h
- ./Garazyk/Sources/Network/XrpcSyncPack.m
- ./Garazyk/Sources/Network/XrpcVendorPack.h
- ./Garazyk/Sources/Network/XrpcVendorPack.m
- ./Garazyk/Sources/Registration/PDSRegistrationGate.h
- ./Garazyk/Sources/Registration/PDSRegistrationGate.m
- ./Garazyk/Sources/Services/Core/PDSPhoneVerificationProvider.h
- ./Garazyk/Sources/Services/Core/PDSPhoneVerificationProvider.m
- ./Garazyk/Sources/Services/PDS/PDSAccountService.m
- ./Garazyk/Sources/Video/VideoXrpcPack.m

## Secondary priority (method files without validation signal)
- ./Garazyk/Sources/App/NodeInfo/NodeInfoHandler.h
- ./Garazyk/Sources/App/NodeInfo/NodeInfoHandler.m
- ./Garazyk/Sources/App/NodeInfo/NodeInfoProvider.h
- ./Garazyk/Sources/App/PDSApplication.m
- ./Garazyk/Sources/App/server_main.m
- ./Garazyk/Sources/AppView/Server/Backfill/AppViewBackfillOrchestrator.h
- ./Garazyk/Sources/AppView/Server/Hooks/AppViewIndexHookRegistry.h
- ./Garazyk/Sources/AppView/Server/Hooks/AppViewIndexHookRegistry.m
- ./Garazyk/Sources/AppView/Server/Lexicon/AppViewCustomQueryRegistry.m
- ./Garazyk/Sources/AppView/Server/Lexicon/AppViewLexiconEndpointGenerator.m
- ./Garazyk/Sources/AppView/Services/NotificationService.h
- ./Garazyk/Sources/Auth/WebAuthnRegistrationHandler.h
- ./Garazyk/Sources/CLI/PDSCLIAccountManager.m
- ./Garazyk/Sources/CLI/PDSCLIDispatcher.m
- ./Garazyk/Sources/CLI/PDSCLIRegisterAll.m
- ./Garazyk/Sources/Chat/Server/ChatRuntime.m
- ./Garazyk/Sources/Compat/PlatformShims/CoreFoundation/CFBase.h
- ./Garazyk/Sources/Compat/PlatformShims/CrashReporting/PDSCrashReporter.h
- ./Garazyk/Sources/Compat/PlatformShims/SignalHandling/PDSSignalManager.h
- ./Garazyk/Sources/Compat/PlatformShims/SignalHandling/PDSSignalManager.m
- ./Garazyk/Sources/Compat/XCTest/XCTest.h
- ./Garazyk/Sources/Core/ATProtoServiceContainer.h
- ./Garazyk/Sources/Core/ATProtoServiceContainer.m
- ./Garazyk/Sources/Core/PDSProviderRegistry.h
- ./Garazyk/Sources/Core/PDSProviderRegistry.m
- ./Garazyk/Sources/Email/PDSEmailProviderFactory.h
- ./Garazyk/Sources/Email/PDSEmailProviderFactory.m
- ./Garazyk/Sources/Germ/Server/Runtime/GermRuntime.m
- ./Garazyk/Sources/Germ/Server/Services/GermMailboxService.h
- ./Garazyk/Sources/Germ/Server/XrpcGermIdentityPack.h
- ./Garazyk/Sources/Germ/Server/XrpcGermIdentityPack.m
- ./Garazyk/Sources/Germ/Server/XrpcGermMailboxPack.h
- ./Garazyk/Sources/Germ/Server/XrpcGermMailboxPack.m
- ./Garazyk/Sources/MediaCore/ATProtoMediaXrpcPack.h
- ./Garazyk/Sources/MediaCore/ATProtoMediaXrpcPack.m
- ./Garazyk/Sources/Mikrus/MikrusXrpcRoutePack.h
- ./Garazyk/Sources/Network/ATProtoHttpMSTViewerRoutePack.h
- ./Garazyk/Sources/Network/ATProtoHttpMSTViewerRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpMetricsRoutePack.h
- ./Garazyk/Sources/Network/ATProtoHttpMetricsRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpNodeInfoRoutePack.h
- ./Garazyk/Sources/Network/ATProtoHttpNodeInfoRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpOAuthDemoRoutePack.h
- ./Garazyk/Sources/Network/ATProtoHttpOAuthDemoRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpOAuthRoutePack.h
- ./Garazyk/Sources/Network/ATProtoHttpOAuthRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpRelayAPIRoutePack.h
- ./Garazyk/Sources/Network/ATProtoHttpRelayAPIRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpServerBuilder.h
- ./Garazyk/Sources/Network/ATProtoHttpServerBuilder.m
- ./Garazyk/Sources/Network/ATProtoHttpWellKnownRoutePack.h
- ./Garazyk/Sources/Network/ATProtoHttpWellKnownRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpXrpcRoutePack.h
- ./Garazyk/Sources/Network/ATProtoHttpXrpcRoutePack.m
- ./Garazyk/Sources/Network/AppViewXRpcRoutePack.h
- ./Garazyk/Sources/Network/PDSHttpPDSAdminRoutePack.h
- ./Garazyk/Sources/Network/RelayXrpcRoutePack.h
- ./Garazyk/Sources/Network/XrpcAdminPack.h
- ./Garazyk/Sources/Network/XrpcAppBskyActorPack.h
- ./Garazyk/Sources/Network/XrpcAppBskyActorPack.m
- ./Garazyk/Sources/Network/XrpcAppBskyAgeAssurancePack.h
- ./Garazyk/Sources/Network/XrpcAppBskyBookmarksPack.h
- ./Garazyk/Sources/Network/XrpcAppBskyBookmarksPack.m
- ./Garazyk/Sources/Network/XrpcAppBskyContactPack.h
- ./Garazyk/Sources/Network/XrpcAppBskyDraftsPack.h
- ./Garazyk/Sources/Network/XrpcAppBskyDraftsPack.m
- ./Garazyk/Sources/Network/XrpcAppBskyNotificationPack.h
- ./Garazyk/Sources/Network/XrpcAppBskyNotificationPack.m
- ./Garazyk/Sources/Network/XrpcAppBskyPack.h
- ./Garazyk/Sources/Network/XrpcAppBskyPack.m
- ./Garazyk/Sources/Network/XrpcAppBskyProxyMethodPack.h
- ./Garazyk/Sources/Network/XrpcAppBskyProxyMethodPack.m
- ./Garazyk/Sources/Network/XrpcChatBskyActorPack.h
- ./Garazyk/Sources/Network/XrpcChatBskyGroupPack.h
- ./Garazyk/Sources/Network/XrpcIdentityPack.h
- ./Garazyk/Sources/Network/XrpcLabelPack.h
- ./Garazyk/Sources/Network/XrpcLexiconResolver.h
- ./Garazyk/Sources/Network/XrpcMethodRegistry.m
- ./Garazyk/Sources/Network/XrpcModerationPack.h
- ./Garazyk/Sources/Network/XrpcRoutePack.h
- ./Garazyk/Sources/Network/XrpcRoutePackRegistrar.h
- ./Garazyk/Sources/Network/XrpcRoutePackRegistrar.m
- ./Garazyk/Sources/Network/XrpcServerPack.h
- ./Garazyk/Sources/Network/XrpcSyncPack.h
- ./Garazyk/Sources/Network/XrpcVendorPack.h
- ./Garazyk/Sources/Services/Core/PDSPhoneVerificationProvider.m

## Notes
- Registration files can rely on downstream handler auth.
- Treat these as triage candidates, not automatic findings.

## scan_parser_hardening
### Objective-C Parser Hardening Scan

- Root: .
- Scan paths: ./Garazyk/Sources/Repository ./Garazyk/Sources/Core
- Generated: 2026-05-22T18:10:10Z

## Counts
- Parse/decoder signals: 97
- Risky memory/range signals: 280
- Bounds/length signals: 548
- Integer/conversion signals: 517

## Prioritize first (parse + risky without bounds signal)
- ./Garazyk/Sources/Core/Base58.h
- ./Garazyk/Sources/Repository/STAR.h

## Notes
- File-level signal only; confirm exact operation-level guards.

## scan_firehose_backpressure
### Objective-C Firehose Ordering/Backpressure Scan

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

## scan_network_timeout_retry
### Objective-C Network Timeout/Retry Scan

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

## scan_oauth_dpop_conformance
### Objective-C OAuth DPoP Conformance Scan

- Root: .
- Scan path: ./Garazyk/Sources
- Generated: 2026-05-22T18:10:11Z

## Counts
- DPoP/proof signals: 329
- Token lifecycle signals: 163
- Nonce/replay signals: 140
- Clock/skew signals: 113
- Key/sign/verify signals: 412

## Prioritize first (DPoP + token lifecycle files)
- ./Garazyk/Sources/Auth/JWT.h
- ./Garazyk/Sources/Auth/JWT.m
- ./Garazyk/Sources/Auth/OAuth2.h
- ./Garazyk/Sources/Auth/OAuth2.m
- ./Garazyk/Sources/Auth/OAuth2Handler.h
- ./Garazyk/Sources/Auth/OAuth2Handler.m
- ./Garazyk/Sources/Auth/OAuthProvider/OAuthProvider.h
- ./Garazyk/Sources/Auth/OAuthProvider/OAuthProvider.m
- ./Garazyk/Sources/Auth/OAuthProvider/OAuthProviderProtocols.h
- ./Garazyk/Sources/Auth/OAuthSession.h
- ./Garazyk/Sources/Auth/Session.h
- ./Garazyk/Sources/Auth/Session.m
- ./Garazyk/Sources/Auth/Verifier/AuthVerifier.h
- ./Garazyk/Sources/Network/XrpcServerPack.m

## Secondary priority (DPoP files without nonce signal)
- ./Garazyk/Sources/Auth/OAuth2Handler.h
- ./Garazyk/Sources/Auth/OAuthClientAuthPolicy.h
- ./Garazyk/Sources/Auth/OAuthClientAuthPolicy.m
- ./Garazyk/Sources/Auth/OAuthSession.m
- ./Garazyk/Sources/Auth/Session.h
- ./Garazyk/Sources/Auth/Session.m
- ./Garazyk/Sources/Network/ATProtoHttpServerBuilder.m
- ./Garazyk/Sources/Network/XrpcHandler.m
- ./Garazyk/Sources/Network/XrpcMethodRegistry.h
- ./Garazyk/Sources/Network/XrpcMiddleware.h
- ./Garazyk/Sources/Network/XrpcProxyInterceptor.m
- ./Garazyk/Sources/Network/XrpcServerPack.m
- ./Garazyk/Sources/Network/XrpcSyncPack.m

## Notes
- Validate against runtime behavior and conformance tests.

## scan_dos
### Objective-C Rate Limiting and DoS Scan

- Root: .
- Scan path: ./Garazyk/Sources
- Generated: 2026-05-22T18:10:11Z

## Counts
- Unbounded loops: 2
- Unbounded collections: 793
- Memory allocation sites: 56
- WebSocket handlers: 243
- HTTP handlers: 192
- Rate limiting usage: 247
- File size checks: 808
- Timeout configurations: 154

## High priority (handlers without rate limiting)
- ./Garazyk/Sources/AdminUIServer/UIServerRuntime.m
- ./Garazyk/Sources/App/MSTViewer/MSTViewerHandler.h
- ./Garazyk/Sources/App/MSTViewer/MSTViewerHandler.m
- ./Garazyk/Sources/App/OAuthDemo/OAuthDemoHandler.h
- ./Garazyk/Sources/App/OAuthDemo/OAuthDemoHandler.m
- ./Garazyk/Sources/App/server_main.m
- ./Garazyk/Sources/CLI/PDSCLIServeCommand.m
- ./Garazyk/Sources/Germ/Server/Runtime/GermRuntime.m
- ./Garazyk/Sources/Germ/Server/XrpcGermIdentityPack.m
- ./Garazyk/Sources/Germ/Server/XrpcGermMailboxPack.m
- ./Garazyk/Sources/MediaCore/ATProtoMediaXrpcPack.m
- ./Garazyk/Sources/Network/ATProtoHttpMSTViewerRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpOAuthDemoRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpRelayAPIRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpXrpcRoutePack.m
- ./Garazyk/Sources/Network/HttpRouter.h
- ./Garazyk/Sources/Network/HttpRouter.m
- ./Garazyk/Sources/Network/XrpcAdminPack.m
- ./Garazyk/Sources/Network/XrpcAppBskyFeedPack.m
- ./Garazyk/Sources/Network/XrpcAppBskyGraphPack.m
- ./Garazyk/Sources/Network/XrpcAppBskyPack.m
- ./Garazyk/Sources/Network/XrpcAppBskyUnspeccedPack.m
- ./Garazyk/Sources/Network/XrpcChatBskyConvoPack.m
- ./Garazyk/Sources/Network/XrpcHandler.h
- ./Garazyk/Sources/Network/XrpcHandlerContext.h
- ./Garazyk/Sources/Network/XrpcHandlerContext.m
- ./Garazyk/Sources/Network/XrpcLabelPack.m
- ./Garazyk/Sources/Network/XrpcLexiconResolver.m
- ./Garazyk/Sources/Network/XrpcMethodRegistry.h
- ./Garazyk/Sources/Network/XrpcModerationPack.m
- ./Garazyk/Sources/Network/XrpcProxyHandler.h
- ./Garazyk/Sources/Network/XrpcProxyHandler.m
- ./Garazyk/Sources/Network/XrpcProxyInterceptor.m
- ./Garazyk/Sources/Network/XrpcRoutePackRegistrar.m
- ./Garazyk/Sources/Network/XrpcServerPack.m
- ./Garazyk/Sources/Network/XrpcSyncPack.m
- ./Garazyk/Sources/Network/XrpcToolsOzonePack.m
- ./Garazyk/Sources/Network/XrpcVendorPack.m
- ./Garazyk/Sources/Sync/Relay/RelayAPIHandler.h
- ./Garazyk/Sources/Sync/Relay/RelayAPIHandler.m
- ./Garazyk/Sources/Video/VideoXrpcPack.m

## Detailed findings

### Unbounded loops
  ./Garazyk/Sources/CLI/PDSCLIInputHelper.m:134:    while (YES) {
  ./Garazyk/Sources/Network/HttpResponse.m:186:        while (YES) {

### Memory allocation without size limits
  ./Garazyk/Sources/Lexicon/ATProtoLexiconRegistry.m:93:    NSData *data = [NSData dataWithContentsOfFile:filePath options:0 error:&readError];
  ./Garazyk/Sources/Compat/Foundation/NSDataCompat.h:16:+ (nullable NSData *)dataWithContentsOfFile:(NSString *)path
  ./Garazyk/Sources/Compat/Foundation/NSDataCompat.m:9:+ (nullable NSData *)dataWithContentsOfFile:(NSString *)path
  ./Garazyk/Sources/Compat/Foundation/NSDataCompat.m:12:    NSData *data = [NSData dataWithContentsOfFile:path];
  ./Garazyk/Sources/Sync/Relay/RelayConfiguration.m:51:    NSData *data = [NSData dataWithContentsOfFile:path];
  ./Garazyk/Sources/Compat/PlatformShims/CoreFoundation/CFNetwork.m:28:    struct __CFHTTPMessage *msg = calloc(1, sizeof(struct __CFHTTPMessage));
  ./Garazyk/Sources/Compat/PlatformShims/CoreFoundation/CFNetwork.m:108:    struct __CFURL *url = calloc(1, sizeof(struct __CFURL));
  ./Garazyk/Sources/Blob/PDSDiskBlobProvider.m:70:    return [NSData dataWithContentsOfURL:blobURL options:NSDataReadingMappedIfSafe error:error];
  ./Garazyk/Sources/CLI/PDSCLIHealthCommand.m:83:    NSString *pidContent = [NSString stringWithContentsOfFile:pidPath encoding:NSUTF8StringEncoding error:nil];
  ./Garazyk/Sources/Compat/PlatformShims/CrashReporting/PDSCrashReporter.m:200:    ss.ss_sp = malloc(SIGSTKSZ);
  ./Garazyk/Sources/Video/VideoTranscoder.m:65:            result = [NSData dataWithContentsOfURL:outputURL];
  ./Garazyk/Sources/CLI/PDSCLIDispatcher.m:46:    NSData *data = [NSData dataWithContentsOfFile:configPath options:0 error:&error];
  ./Garazyk/Sources/CLI/PDSCLIDispatcher.m:48:    NSData *data = [NSData dataWithContentsOfFile:configPath];
  ./Garazyk/Sources/Compat/PlatformShims/Security/SecKey.m:82:    SecKeyRef key = malloc(sizeof(struct SecKey));
  ./Garazyk/Sources/Compat/PlatformShims/Security/SecKey.m:93:    SecKeyRef publicKey = malloc(sizeof(struct SecKey));
  ... and 41 more

### WebSocket entry points
  ./Garazyk/Sources/Sync/Relay/RelayClient.m:6:#import "Sync/WebSocket/WebSocketConnection.h"
  ./Garazyk/Sources/Sync/Firehose/Firehose.h:313: @discussion Propagates to the underlying WebSocketConnection, causing
  ./Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m:24:#import "Sync/WebSocket/WebSocketConnection.h"
  ./Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m:25:#import "Sync/WebSocket/WebSocketServer.h"
  ./Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m:43:@interface SubscribeReposHandler () <WebSocketServerDelegate,
  ./Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m:44:                                     WebSocketConnectionDelegate>
  ./Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m:46:@property(nonatomic, strong) WebSocketServer *webSocketServer;
  ./Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m:58:    NSMutableSet<WebSocketConnection *> *attachedConnections;
  ./Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m:71:                  toConnection:(WebSocketConnection *)connection;
  ./Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m:72:- (void)detachConnection:(WebSocketConnection *)connection;

## Notes
- Unbounded loops need explicit break conditions.
- Handlers without rate limiting need manual review.
- Memory allocations need size validation for user input.
- WebSocket needs message size limits and backpressure.

## scan_sqlite_invariants
### Objective-C SQLite Invariant Scan

- Root: .
- Scan path: ./Garazyk/Sources/Database
- Generated: 2026-05-22T18:10:12Z

## Counts
- Transaction sites: 43
- Prepare sites: 36
- Step sites: 32
- Reset sites: 2
- Finalize sites: 19
- PRAGMA sites: 29

## Prioritize first (prepare without finalize signal)
- ./Garazyk/Sources/Database/Monitoring/PDSHealthCheck.m
- ./Garazyk/Sources/Database/PDSDatabase+Accounts.m
- ./Garazyk/Sources/Database/PDSDatabase+Blobs.m
- ./Garazyk/Sources/Database/PDSDatabase+Blocks.m

## Secondary priority (step without reset signal)
- ./Garazyk/Sources/Database/Migrations/PDSMigrationManager.m
- ./Garazyk/Sources/Database/Monitoring/PDSHealthCheck.m
- ./Garazyk/Sources/Database/PDSDatabase+Accounts.m
- ./Garazyk/Sources/Database/PDSDatabase+Blobs.m
- ./Garazyk/Sources/Database/PDSDatabase+OAuthClients.m

## Transaction files that also lock
- none

## Notes
- Signals are file-level heuristics only.
- Confirm control flow before filing findings.

## map_test_gaps
### Objective-C Test Gap Map

- Root: .
- Source root: ./Garazyk/Sources
- Test root: ./Tests
- Generated: 2026-05-22T18:10:17Z

## Counts
- Source implementation files: 402
- Test implementation files: 0
- Covered source candidates: 0
- Uncovered source candidates: 400

## Top uncovered modules
- Network: 75 uncovered files
- AppView: 38 uncovered files
- Database: 36 uncovered files
- Auth: 34 uncovered files
- Core: 29 uncovered files
- Sync: 22 uncovered files
- CLI: 16 uncovered files
- Admin: 16 uncovered files
- Video: 15 uncovered files
- PLC: 14 uncovered files
- Compat: 13 uncovered files
- App: 11 uncovered files
- Services: 7 uncovered files
- Repository: 7 uncovered files
- Email: 7 uncovered files

## First uncovered files
- ./Garazyk/Sources/Admin/AdminMiddleware.m
- ./Garazyk/Sources/Admin/Diagnostics/Analytics/PDSSequencerAnalyticsCollector.m
- ./Garazyk/Sources/Admin/Diagnostics/BlobAudit/PDSBlobAuditManager.m
- ./Garazyk/Sources/Admin/Diagnostics/BlobAudit/PDSBlobAuditOperation.m
- ./Garazyk/Sources/Admin/Diagnostics/BlobAudit/PDSBlobAuditUtils.m
- ./Garazyk/Sources/Admin/Diagnostics/BlobAudit/PDSBlobCIDVerificationOperation.m
- ./Garazyk/Sources/Admin/Diagnostics/BlobAudit/PDSBlobConsistencyCheckOperation.m
- ./Garazyk/Sources/Admin/Diagnostics/BlobAudit/PDSBlobOrphanScanOperation.m
- ./Garazyk/Sources/Admin/Diagnostics/BlobAudit/PDSBlobReferenceScanOperation.m
- ./Garazyk/Sources/Admin/Diagnostics/PDSBlobAuditHandler.m
- ./Garazyk/Sources/Admin/Diagnostics/PDSRateLimitAdminHandler.m
- ./Garazyk/Sources/Admin/Diagnostics/PDSSequencerHealthHandler.m
- ./Garazyk/Sources/Admin/Diagnostics/PDSSystemDiagnosticsHandler.m
- ./Garazyk/Sources/Admin/PDSAdminAuth.m
- ./Garazyk/Sources/Admin/PDSAdminController.m
- ./Garazyk/Sources/Admin/PDSInstallerCommand.m
- ./Garazyk/Sources/AdminUIServer/UIAuthManager.m
- ./Garazyk/Sources/AdminUIServer/UIBackendClient.m
- ./Garazyk/Sources/AdminUIServer/UIServerRuntime.m
- ./Garazyk/Sources/AdminUIServer/UIServiceConfig.m
- ./Garazyk/Sources/App/ATProtoServiceConfiguration.m
- ./Garazyk/Sources/App/AppDelegate.m
- ./Garazyk/Sources/App/MSTViewer/MSTViewerHandler.m
- ./Garazyk/Sources/App/NodeInfo/NodeInfoHandler.m
- ./Garazyk/Sources/App/NodeInfo/NodeInfoProvider.m
- ./Garazyk/Sources/App/NodeInfo/NodeInfoSchemas.m
- ./Garazyk/Sources/App/OAuthDemo/OAuthDemoHandler.m
- ./Garazyk/Sources/App/PDSApplication.m
- ./Garazyk/Sources/App/PDSController.m
- ./Garazyk/Sources/App/PDSReadinessCheck.m
- ./Garazyk/Sources/App/server_main.m
- ./Garazyk/Sources/AppView/AppViewIdentityHelper.m
- ./Garazyk/Sources/AppView/Server/Admin/AppViewAdminRoutePack.m
- ./Garazyk/Sources/AppView/Server/AppViewDatabase.m
- ./Garazyk/Sources/AppView/Server/AppViewRuntime.m
- ./Garazyk/Sources/AppView/Server/AppViewTypes.m
- ./Garazyk/Sources/AppView/Server/Auth/AppViewOAuth2Middleware.m
- ./Garazyk/Sources/AppView/Server/Backfill/AppViewBackfillOrchestrator.m
- ./Garazyk/Sources/AppView/Server/Backfill/AppViewBackfillWorker.m
- ./Garazyk/Sources/AppView/Server/Config/AppViewConfiguration.m

## Notes
- Mapping is heuristic; manually confirm coverage depth.
- Indirect coverage may exist even without basename match.

