# Objective-C GNUstep Regression Scan

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
