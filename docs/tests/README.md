# Test Documentation Index

Comprehensive documentation for all unit and integration tests in the ATProtoPDS project.

## Test Categories

| Category | Description | Classes |
|----------|-------------|---------|
| [00-identity-auth](00-identity-auth/README.md) | OAuth, JWT, MFA, handle/DID resolution | 28 |
| [01-repository](01-repository/README.md) | MST, CAR, CBOR, core primitives | 12 |
| [02-network](02-network/README.md) | HTTP, XRPC, WebSocket, transport | 19 |
| [03-database](03-database/README.md) | Actor stores, service DBs, pooling | 8 |
| [04-application](04-application/README.md) | Services, controllers, CLI, admin | 20 |
| [05-security](05-security/README.md) | Hardening, validation, authorization | 9 |
| [06-integration](06-integration/README.md) | E2E, PLC, federation | 12 |
| [07-email](07-email/README.md) | Email providers, secrets management | 5 |
| [08-characterization](08-characterization/README.md) | Reference implementation compliance | 4 |
| [09-utilities](09-utilities/README.md) | Config, metrics, debug tools | 8 |

**Total: ~125 test classes**

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

### [00-identity-auth](00-identity-auth/README.md)

Authentication, authorization, and identity resolution.

| File | Focus |
|------|-------|
| [oauth.md](00-identity-auth/oauth.md) | OAuth 2.0/OIDC flows, PKCE, DPoP |
| [jwt-crypto.md](00-identity-auth/jwt-crypto.md) | Token signing, cryptographic primitives |
| [mfa.md](00-identity-auth/mfa.md) | Multi-factor authentication |
| [identity-resolution.md](00-identity-auth/identity-resolution.md) | Handle/DID resolution |

### [01-repository](01-repository/README.md)

Merkle Search Tree, CAR files, and repository data structures.

| File | Focus |
|------|-------|
| [mst.md](01-repository/mst.md) | Merkle Search Tree operations |
| [car-cbor.md](01-repository/car-cbor.md) | CAR file format, DAG-CBOR |
| [primitives.md](01-repository/primitives.md) | Core data types and validation |

### [02-network](02-network/README.md)

HTTP server, XRPC protocol, WebSockets, and transport layer.

| File | Focus |
|------|-------|
| [http-stack.md](02-network/http-stack.md) | HTTP server implementation |
| [xrpc.md](02-network/xrpc.md) | XRPC protocol |
| [websocket.md](02-network/websocket.md) | WebSocket and firehose |
| [transport.md](02-network/transport.md) | Network transport and rate limiting |

### [03-database](03-database/README.md)

SQLite-based persistence layer.

| File | Focus |
|------|-------|
| [actor-store.md](03-database/actor-store.md) | Per-user databases |
| [service-databases.md](03-database/service-databases.md) | Global service databases |
| [pool-integration.md](03-database/pool-integration.md) | Connection pooling |

### [04-application](04-application/README.md)

Business logic and application services.

| File | Focus |
|------|-------|
| [services.md](04-application/services.md) | Business services |
| [controller.md](04-application/controller.md) | Core controllers |
| [admin.md](04-application/admin.md) | Admin operations |
| [cli.md](04-application/cli.md) | CLI commands |
| [blob.md](04-application/blob.md) | Blob storage |

### [05-security](05-security/README.md)

Security hardening and input validation.

| File | Focus |
|------|-------|
| [hardening.md](05-security/hardening.md) | Security hardening |
| [validation.md](05-security/validation.md) | Input validation |
| [auth-security.md](05-security/auth-security.md) | Authorization security |

### [06-integration](06-integration/README.md)

End-to-end and integration tests.

| File | Focus |
|------|-------|
| [e2e.md](06-integration/e2e.md) | End-to-end flows |
| [plc.md](06-integration/plc.md) | PLC directory operations |
| [federation.md](06-integration/federation.md) | Cross-PDS federation |

### [07-email](07-email/README.md)

Email provider integrations.

| File | Focus |
|------|-------|
| [email.md](07-email/email.md) | Email providers and secrets |

### [08-characterization](08-characterization/README.md)

Reference implementation compliance tests.

| File | Focus |
|------|-------|
| [characterization.md](08-characterization/characterization.md) | Reference compliance |

### [09-utilities](09-utilities/README.md)

Configuration, metrics, and debugging tools.

| File | Focus |
|------|-------|
| [config-metrics.md](09-utilities/config-metrics.md) | Configuration and metrics |
| [debug.md](09-utilities/debug.md) | Debug and exploration tools |

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
- [ATProto PDS Architecture](../architecture/atproto_pds_architecture.md) - System architecture overview
- [XRPC Protocol Reference](../architecture/XRPC_PROTOCOL_REFERENCE.md) - XRPC protocol specification
- [ATProto Data Models](../architecture/atproto_data_models.md) - Data structure specifications

### Security
- [Security Documentation](../security/README.md) - Security analysis and testing
- [Security Analysis Report](../security/SECURITY_ANALYSIS_REPORT.md) - Detailed security review
- [SSRF Protection](../security/SSRF_PROTECTION.md) - Network security measures

### OAuth2
- [OAuth2 Documentation](../oauth2/README.md) - Authentication flow documentation
- [Authorization Flow](../oauth2/authorization-flow.md) - OAuth authorization process
- [DPoP Implementation](../oauth2/dpop.md) - Demonstrating Proof-of-Possession

### Guides
- [Development Workflows](../guides/README.md) - Development and testing guides

## Contributing

When adding new tests, update the relevant documentation file in the appropriate subfolder. Each test class should be documented with:
- Purpose (one sentence)
- Test method table with descriptions
- Key invariants/assertions
- Any mocks or fixtures used
