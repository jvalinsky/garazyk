# Test Documentation Index

Comprehensive documentation for all unit and integration tests in the ATProtoPDS project.

## Test Categories

| Category | Description | Classes |
|----------|-------------|---------|
| [00-identity-auth](00-identity-auth/README) | OAuth, JWT, MFA, handle/DID resolution | 28 |
| [01-repository](01-repository/README) | MST, CAR, CBOR, core primitives | 14 |
| [02-network](02-network/README) | HTTP, XRPC, WebSocket, transport | 45 |
| [03-database](03-database/README) | Actor stores, service DBs, pooling | 18 |
| [04-application](04-application/README) | Services, controllers, CLI, admin | 24 |
| [05-security](05-security/README) | Hardening, validation, authorization | 6 |
| [06-integration](06-integration/README) | E2E, PLC, federation | 13 |
| [07-email](07-email/README) | Email providers, secrets management | 4 |
| [08-characterization](08-characterization/README) | Reference implementation compliance | 6 |
| [09-utilities](09-utilities/README) | Config, metrics, debug tools | 15 |

**Total: ~140 test classes**

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

### [00-identity-auth](00-identity-auth/README)

Authentication, authorization, and identity resolution.

| File | Focus |
|------|-------|
| [oauth.md](00-identity-auth/oauth) | OAuth 2.0/OIDC flows, PKCE, DPoP |
| [jwt-crypto.md](00-identity-auth/jwt-crypto) | Token signing, cryptographic primitives |
| [mfa.md](00-identity-auth/mfa) | Multi-factor authentication |
| [identity-resolution.md](00-identity-auth/identity-resolution) | Handle/DID resolution |

### [01-repository](01-repository/README)

Merkle Search Tree, CAR files, and repository data structures.

| File | Focus |
|------|-------|
| [mst.md](01-repository/mst) | Merkle Search Tree operations |
| [car-cbor.md](01-repository/car-cbor) | CAR file format, DAG-CBOR |
| [primitives.md](01-repository/primitives) | Core data types and validation |

### [02-network](02-network/README)

HTTP server, XRPC protocol, WebSockets, and transport layer.

| File | Focus |
|------|-------|
| [http-stack.md](02-network/http-stack) | HTTP server implementation |
| [xrpc.md](02-network/xrpc) | XRPC protocol |
| [websocket.md](02-network/websocket) | WebSocket and firehose |
| [transport.md](02-network/transport) | Network transport and rate limiting |

### [03-database](03-database/README)

SQLite-based persistence layer.

| File | Focus |
|------|-------|
| [actor-store.md](03-database/actor-store) | Per-user databases |
| [service-databases.md](03-database/service-databases) | Global service databases |
| [pool-integration.md](03-database/pool-integration) | Connection pooling |

### [04-application](04-application/README)

Business logic and application services.

| File | Focus |
|------|-------|
| [services.md](04-application/services) | Business services |
| [controller.md](04-application/controller) | Core controllers |
| [admin.md](04-application/admin) | Admin operations |
| [cli.md](04-application/cli) | CLI commands |
| [blob.md](04-application/blob) | Blob storage |

### [05-security](05-security/README)

Security hardening and input validation.

| File | Focus |
|------|-------|
| [hardening.md](05-security/hardening) | Security hardening |
| [validation.md](05-security/validation) | Input validation |
| [auth-security.md](05-security/auth-security) | Authorization security |

### [06-integration](06-integration/README)

End-to-end and integration tests.

| File | Focus |
|------|-------|
| [e2e.md](06-integration/e2e) | End-to-end flows |
| [plc.md](06-integration/plc) | PLC directory operations |
| [federation.md](06-integration/federation) | Cross-PDS federation |

### [07-email](07-email/README)

Email provider integrations.

| File | Focus |
|------|-------|
| [email.md](07-email/email) | Email providers and secrets |

### [08-characterization](08-characterization/README)

Reference implementation compliance tests.

| File | Focus |
|------|-------|
| [characterization.md](08-characterization/characterization) | Reference compliance |

### [09-utilities](09-utilities/README)

Configuration, metrics, and debugging tools.

| File | Focus |
|------|-------|
| [config-metrics.md](09-utilities/config-metrics) | Configuration and metrics |
| [debug.md](09-utilities/debug) | Debug and exploration tools |

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
├── Sync/            # Synchronization tests
└── XRPC/            # XRPC tests
```

## Related Documentation

### Architecture
- [ATProto PDS Architecture](../architecture/atproto_pds_architecture) - System architecture overview
- [XRPC Protocol Reference](../architecture/XRPC_PROTOCOL_REFERENCE) - XRPC protocol specification
- [ATProto Data Models](../architecture/atproto_data_models) - Data structure specifications

### Security
- [Security Documentation](../security/README) - Security analysis and testing
- [Security Analysis Report](../security/SECURITY_ANALYSIS_REPORT) - Detailed security review
- [SSRF Protection](../security/SSRF_PROTECTION) - Network security measures

### OAuth2
- [OAuth2 Documentation](../oauth2/README) - Authentication flow documentation
- [Authorization Flow](../oauth2/authorization-flow) - OAuth authorization process
- [DPoP Implementation](../oauth2/dpop) - Demonstrating Proof-of-Possession

### Guides
- [Development Workflows](../guides/README) - Development and testing guides

## Contributing

When adding new tests, update the relevant documentation file in the appropriate subfolder. Each test class should be documented with:
- Purpose (one sentence)
- Test method table with descriptions
- Key invariants/assertions
- Any mocks or fixtures used
