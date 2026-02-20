# Test Documentation Index

This directory contains comprehensive documentation for all unit and integration tests in the ATProtoPDS project.

## Quick Reference

| Area | Test Classes | Documentation |
|------|-------------|---------------|
| Identity & Auth | 28 | [00-identity-auth/](00-identity-auth/) |
| Repository | 12 | [01-repository/](01-repository/) |
| Network | 19 | [02-network/](02-network/) |
| Database | 8 | [03-database/](03-database/) |
| Application | 20 | [04-application/](04-application/) |
| Security | 9 | [05-security/](05-security/) |
| Integration | 12 | [06-integration/](06-integration/) |
| Email | 5 | [07-email/](07-email/) |
| Characterization | 4 | [08-characterization/](08-characterization/) |
| Utilities | 8 | [09-utilities/](09-utilities/) |

**Total: 135 test classes across 147 test files**

## Running Tests

```bash
# Build and run all tests
xcodebuild -scheme AllTests build
./build/tests/AllTests

# Run specific test suite
./build/tests/AllTests -only-testing:AllTests/OAuth2Tests

# Run tests matching a pattern
./build/tests/AllTests 2>&1 | grep -E "Test (Case|Suite)"
```

## Documentation by Area

### 00-identity-auth
Authentication, authorization, and identity resolution.

| File | Test Classes | Focus |
|------|-------------|-------|
| [oauth.md](00-identity-auth/oauth.md) | OAuth2Tests, OAuth2HandlerTests, OAuth2EndpointTests, OAuthConformanceTests, OAuthDPoPTests, OAuthPKCETests, OAuthPublicClientTests, OAuthIntegrationTests, OAuthServerMetadataTests, OAuthSessionTests, SessionStoreTests | OAuth 2.0/OIDC flows, PKCE, DPoP |
| [jwt-crypto.md](00-identity-auth/jwt-crypto.md) | JWTTests, JWTSecurityTests, CryptoTests, KeyManagerSecurityTests, PDSOpenSSLKeyManagerTests | Token signing, cryptographic primitives |
| [mfa.md](00-identity-auth/mfa.md) | TOTPTests, WebAuthnVerifierTests, YubiKeyOATHTests | Multi-factor authentication |
| [identity-resolution.md](00-identity-auth/identity-resolution.md) | HandleResolverTests, HandleResolverSSRFTests, HandleResolverSecurityTests, DIDResolverTests, DIDPLCResolverTests, IdentifierTests, ATProtoHandleValidatorTests | Handle/DID resolution |

### 01-repository
Merkle Search Tree, CAR files, and repository data structures.

| File | Test Classes | Focus |
|------|-------------|-------|
| [mst.md](01-repository/mst.md) | MSTInteropTests, MSTPersistenceTests, MSTCharacterizationTests, RepoCommitTests | Merkle Search Tree operations |
| [car-cbor.md](01-repository/car-cbor.md) | CARInteropTests, ATProtoDagCBORTests | CAR file format, DAG-CBOR |
| [primitives.md](01-repository/primitives.md) | Base58Tests, ATProtoCoreTests, ATProtoErrorTests, DIDValidationTests, RecordPathValidationTests, ProtocolCompileTests | Core data types and validation |

### 02-network
HTTP server, XRPC protocol, WebSockets, and transport layer.

| File | Test Classes | Focus |
|------|-------------|-------|
| [http-stack.md](02-network/http-stack.md) | HttpServerTests, HttpResponseTests, HttpRouterTests, HttpRouteTrieTests, HttpRequestParsingTests, HttpChunkedBodyParserTests, HttpBufferPoolTests, HttpStreamingBodyTests, PDSHttpServerBuilderTests | HTTP server implementation |
| [xrpc.md](02-network/xrpc.md) | XrpcHandlerTests, XrpcInputValidationTests, XrpcErrorResponseTests, XRPCErrorTests, XrpcIntegrationTests, XrpcProxyTests, XrpcMethodRegistryTests, XrpcMethodRegistryCharacterizationTests, GetServiceAuthMethodTests, LexiconResolveXrpcTests | XRPC protocol |
| [websocket.md](02-network/websocket.md) | WebSocketServerTests, WebSocketConnectionTests, WebSocketFrameParsingTests, WebSocketUpgradeHandlerTests, SubscribeReposHandlerTests, EventFormatterTests, FirehoseTests, FirehoseConformanceTests | WebSocket and firehose |
| [transport.md](02-network/transport.md) | PDSNetworkTransportTests, PDSNetworkTransportLinuxTests, SSLPinningTests, RateLimiterTests, RateLimitingTests | Network transport and rate limiting |

### 03-database
SQLite-based persistence layer.

| File | Test Classes | Focus |
|------|-------------|-------|
| [actor-store.md](03-database/actor-store.md) | ActorStoreTests, ActorStoreCharacterizationTests, MultiTenantDatabaseTests | Per-user databases |
| [service-databases.md](03-database/service-databases.md) | ServiceDatabasesTests, ServiceDatabasesPruningTests, DatabaseMigrationTests | Global service databases |
| [pool-integration.md](03-database/pool-integration.md) | DatabasePoolTests, PDSDatabaseIntegrationTests, PDSHealthCheckTests | Connection pooling and integration |

### 04-application
Business logic and application services.

| File | Test Classes | Focus |
|------|-------------|-------|
| [services.md](04-application/services.md) | FeedServiceTests, ActorServiceTests, NotificationServiceTests, PDSAccountServiceTests, PDSRecordServiceTests, PDSRepositoryServiceTests, PDSBlobServiceTests, PDSPhoneVerificationProviderTests, FollowersCountIntegrationTests | Business services |
| [controller.md](04-application/controller.md) | PDSControllerTests, PDSApplicationTests, PDSAccountManagerTests, PDSServiceContainerTests, PDSNewArchitectureTests | Core controllers |
| [admin.md](04-application/admin.md) | PDSAdminControllerTests, PDSAdminServiceTests, PDSAdminAuthTests, AdminMiddlewareTests, PDSAuthzManagerTests | Admin operations |
| [cli.md](04-application/cli.md) | PDSCLITests, PDSCLIAccountCommandTests, PDSCLIInviteCommandTests, PDSCLIServiceStubTests, CoverageGapTests | CLI commands |

### 05-security
Security hardening and input validation.

| File | Test Classes | Focus |
|------|-------------|-------|
| [hardening.md](05-security/hardening.md) | SecurityHardeningTests, ProductionSecurityTests, CBORSecurityTests | Security hardening |
| [validation.md](05-security/validation.md) | PDSInputValidatorTests, HandleResolverSecurityTests, ATProtoErrorTests | Input validation |
| [auth-security.md](05-security/auth-security.md) | PDSAuthzManagerTests, PDSReplayCacheTests, AdminAuthXrpcTests, RepoAuthXrpcTests, AdminAuthApplicationXrpcTests, AdminModerationAuthTests | Authorization security |

### 06-integration
End-to-end and integration tests.

| File | Test Classes | Focus |
|------|-------------|-------|
| [e2e.md](06-integration/e2e.md) | PDSIntegrationTests, CommitChainTests, FirehoseIntegrationTests, EmailIntegrationTests, PDSMetricsTests | End-to-end flows |
| [plc.md](06-integration/plc.md) | PDSPLCIntegrationTests, PLCServerTests, PLCStoreTests, PLCOperationTests, PLCAuditorTests, PLCCacheDirectoryTests, PLCDIDKeyTests | PLC directory operations |
| [federation.md](06-integration/federation.md) | FederationClientTests, RelayClientTests | Cross-PDS federation |

### 07-email
Email provider integrations.

| File | Test Classes | Focus |
|------|-------------|-------|
| [email.md](07-email/email.md) | PDSResendEmailProviderTests, PDSEmailHTTPClientTests, PDSKeychainSecretsProviderTests, PDSEnvironmentSecretsProviderTests, EmailIntegrationTests | Email providers and secrets |

### 08-characterization
Reference implementation compliance tests.

| File | Test Classes | Focus |
|------|-------------|-------|
| [characterization.md](08-characterization/characterization.md) | ActorStoreCharacterizationTests, KeyManagerCharacterizationTests, SessionCharacterizationTests, MSTCharacterizationTests | Reference compliance |

### 09-utilities
Configuration, metrics, and debugging tools.

| File | Test Classes | Focus |
|------|-------------|-------|
| [config-metrics.md](09-utilities/config-metrics.md) | PDSConfigurationTests, PDSMetricsTests, NodeInfoTests, ExploreCacheTests | Configuration and metrics |
| [debug.md](09-utilities/debug.md) | PDSLoggerPerformanceTests, ExploreHandlerTests, MSTViewerHandlerTests, OAuthDemoHandlerConfigurationTests | Debug and exploration tools |

## Test File Locations

```
ATProtoPDS/Tests/
├── Admin/           # Admin tests
├── App/             # Application tests
├── AppView/         # App view service tests
├── Auth/            # Authentication tests
├── Blob/            # Blob storage tests
├── CharacterizationTests/  # Characterization tests
├── CLI/             # CLI tests
├── Core/            # Core primitive tests
├── Database/        # Database tests
├── Debug/           # Debug tool tests
├── Email/           # Email tests
├── Federation/      # Federation tests
├── Identity/        # Identity tests
├── Integration/     # Integration tests
├── Lexicon/         # Lexicon validation tests
├── Metrics/         # Metrics tests
├── Network/         # Network tests
├── PLC/             # PLC tests
├── Repository/      # Repository tests
├── Security/        # Security tests
├── Services/        # Service tests
├── Sources/         # Source-specific tests
├── Sync/            # Synchronization tests
└── XRPC/            # XRPC tests
```

## Contributing

When adding new tests, update the relevant documentation file in this directory. Each test class should be documented with:
- Purpose (one sentence)
- Test method table with descriptions
- Key invariants/assertions
- Any mocks or fixtures used
