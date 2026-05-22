# Objective-C OAuth DPoP Conformance Scan

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
