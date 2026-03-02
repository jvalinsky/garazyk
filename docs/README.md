# ATProtoPDS Documentation

This directory contains comprehensive documentation for the ATProtoPDS project, organized by topic and function.

## Directory Index

| Folder | Description | README |
|--------|-------------|--------|
| [architecture/](architecture/) | System architecture diagrams, data models, and XRPC protocol reference | [README](architecture/README.md) |
| [examples/](examples/) | Example configuration files (systemd service, etc.) | — |
| [guides/](guides/) | Developer guides, setup instructions, and workflows | — |
| [oauth2/](oauth2/) | OAuth 2.0 implementation with DPoP, PKCE, and token management | [README](oauth2/README.md) |
| [plan/](plan/) | Project roadmap and planning documents | — |
| [plans/](plans/) | Detailed implementation plans and production readiness | — |
| [security/](security/) | Security analysis, testing plans, and vulnerability reports | — |
| [skills/](skills/) | ATProto compliance review skills and audit tools | [README](skills/README.md) |
| [tests/](tests/) | Test documentation index covering 135 test classes | [README](tests/README.md) |

## Top-Level Documents

| File | Description |
|------|-------------|
| [TESTING.md](TESTING.md) | Comprehensive testing guide and methodology |
| [atproto-plc-architecture.md](atproto-plc-architecture.md) | ATProto PLC directory architecture |
| [troubleshooting-2026-02-25.md](troubleshooting-2026-02-25.md) | PDS Configuration and Identity restoration logs |
| [troubleshooting-relay-sync-2026-02-25.md](troubleshooting-relay-sync-2026-02-25.md) | Relay integration and sync troubleshooting logs |
| [troubleshooting-bsky-ghost-posts-2026-02-26.md](troubleshooting-bsky-ghost-posts-2026-02-26.md) | Ghost post visibility + GNUstep `createRecord` crash investigation and fixes |
| [test-suite-stabilization-report-2026-03-01.md](test-suite-stabilization-report-2026-03-01.md) | **100% Pass Rate** stabilization effort, resolving 1267 test failures |
| [troubleshooting-identity-cors-2026-03-01.md](troubleshooting-identity-cors-2026-03-01.md) | Identity resolution, spec compliance, and dynamic CORS fixes |

## Quick Navigation

### Getting Started
- [Setup Guide](guides/SETUP_GUIDE.md)
- [Developer Guide](guides/DEVELOPER_GUIDE.md)
- [User Guide](guides/USER_GUIDE.md)

### Architecture & Design
- [Architecture Analysis](architecture/ARCHITECTURE_ANALYSIS.md)
- [PDS Architecture](architecture/atproto_pds_architecture.md)
- [Data Models](architecture/atproto_data_models.md)
- [Diagrams (Mermaid)](architecture/DIAGRAMS_MERMAID.md)
- [XRPC Protocol Reference](architecture/XRPC_PROTOCOL_REFERENCE.md)

### OAuth2 & Authentication
- [OAuth 2.0 Overview](oauth2/README.md)
- [Authorization Flow](oauth2/authorization-flow.md)
- [DPoP Implementation](oauth2/dpop.md)
- [PKCE](oauth2/pkce.md)
- [Token Management](oauth2/token-management.md)
- [Web UI](oauth2/web-ui.md)

### Security
- [Identity Hardening (Rotation Keys)](security/IDENTITY_HARDENING.md)
- [Security Testing Plan](security/SECURITY_TESTING_PLAN.md)
- [Security Analysis Report](security/SECURITY_ANALYSIS_REPORT.md)
- [SQL Injection Report](security/SQL_INJECTION_VULNERABILITY_REPORT.md)
- [SSRF Protection](security/SSRF_PROTECTION.md)
- [Admin Auth Configuration](security/ADMIN_AUTH_CONFIGURATION.md)

### Test Documentation & Reports
- [Testing Guide](TESTING.md)
- [Test Suite Stabilization Report (2026-03-01)](test-suite-stabilization-report-2026-03-01.md) - **100% Pass Rate** attainment details
- [Test Documentation Index](tests/README.md) - Complete index of all test classes

### Guides & References
- [Script Development](guides/SCRIPT_DEVELOPMENT.md)
- [Objective-C Tips](guides/objective_c_tips.md)
- [Deployment](guides/DEPLOYMENT.md)
- [Development Workflows](guides/DEVELOPMENT_WORKFLOWS.md)
- [macOS Network Server Guide](guides/macOS_Network_Server_Guide.md)

## Related Documentation

This section provides quick links to key documentation in each subfolder:

| Topic | Key Documents |
|-------|---------------|
| **Architecture** | [PDS Architecture](architecture/atproto_pds_architecture.md), [Data Models](architecture/atproto_data_models.md), [Diagrams](architecture/DIAGRAMS_MERMAID.md) |
| **Guides** | [Developer Guide](guides/DEVELOPER_GUIDE.md), [Setup Guide](guides/SETUP_GUIDE.md), [Deployment](guides/DEPLOYMENT.md) |
| **OAuth2** | [Overview](oauth2/README.md), [Authorization Flow](oauth2/authorization-flow.md), [DPoP](oauth2/dpop.md) |
| **Security** | [Testing Plan](security/SECURITY_TESTING_PLAN.md), [Analysis Report](security/SECURITY_ANALYSIS_REPORT.md), [Identity Hardening](security/IDENTITY_HARDENING.md) |
| **Testing** | [Test Index](tests/README.md), [Identity/Auth](tests/00-identity-auth/README.md), [Repository](tests/01-repository/README.md) |

## Project Links

- [Main Project README](../README.md)
- [Agent Instructions (AGENTS.md)](../AGENTS.md)
