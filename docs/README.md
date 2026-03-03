# ATProtoPDS Documentation

This directory contains comprehensive documentation for the ATProtoPDS project, organized by topic and function.

## Directory Index

| Folder | Description | README |
|--------|-------------|--------|
| [architecture/](architecture/) | System architecture diagrams, data models, and XRPC protocol reference | [README](architecture/README) |
| [examples/](examples/) | Example configuration files (systemd service, etc.) | — |
| [guides/](guides/) | Developer guides, setup instructions, and workflows | — |
| [oauth2/](oauth2/) | OAuth 2.0 implementation with DPoP, PKCE, and token management | [README](oauth2/README) |
| [plan/](plan/) | Project roadmap and planning documents | — |
| [plans/](plans/) | Detailed implementation plans and production readiness | — |
| [security/](security/) | Security analysis, testing plans, and vulnerability reports | — |
| [skills/](skills/) | ATProto compliance review skills and audit tools | [README](skills/README) |
| [tests/](tests/) | Test documentation index covering 135 test classes | [README](tests/README) |

## Top-Level Documents

| File | Description |
|------|-------------|
| [TESTING.md](TESTING) | Comprehensive testing guide and methodology |
| [atproto-plc-architecture.md](atproto-plc-architecture) | ATProto PLC directory architecture |
| [troubleshooting-2026-02-25.md](troubleshooting-2026-02-25) | PDS Configuration and Identity restoration logs |
| [troubleshooting-relay-sync-2026-02-25.md](troubleshooting-relay-sync-2026-02-25) | Relay integration and sync troubleshooting logs |
| [troubleshooting-bsky-ghost-posts-2026-02-26.md](troubleshooting-bsky-ghost-posts-2026-02-26) | Ghost post visibility + GNUstep `createRecord` crash investigation and fixes |
| [test-suite-stabilization-report-2026-03-01.md](test-suite-stabilization-report-2026-03-01) | **100% Pass Rate** stabilization effort, resolving 1267 test failures |
| [troubleshooting-identity-cors-2026-03-01.md](troubleshooting-identity-cors-2026-03-01) | Identity resolution, spec compliance, and dynamic CORS fixes |
| [security-and-architectural-remediation-report-2026-03-02.md](security-and-architectural-remediation-report-2026-03-02) | **100% Pass Rate** remediation report: security hardening, MST rebalancing, and protocol fixes |

## Quick Navigation

### Getting Started
- [Setup Guide](guides/SETUP_GUIDE)
- [Developer Guide](guides/DEVELOPER_GUIDE)
- [User Guide](guides/USER_GUIDE)

### Architecture & Design
- [Architecture Analysis](architecture/ARCHITECTURE_ANALYSIS)
- [PDS Architecture](architecture/atproto_pds_architecture)
- [Data Models](architecture/atproto_data_models)
- [Diagrams (Mermaid)](architecture/DIAGRAMS_MERMAID)
- [XRPC Protocol Reference](architecture/XRPC_PROTOCOL_REFERENCE)

### OAuth2 & Authentication
- [OAuth 2.0 Overview](oauth2/README)
- [Authorization Flow](oauth2/authorization-flow)
- [DPoP Implementation](oauth2/dpop)
- [PKCE](oauth2/pkce)
- [Token Management](oauth2/token-management)
- [Web UI](oauth2/web-ui)

### Security
- [Identity Hardening (Rotation Keys)](security/IDENTITY_HARDENING)
- [Security Testing Plan](security/SECURITY_TESTING_PLAN)
- [Security Analysis Report](security/SECURITY_ANALYSIS_REPORT)
- [SQL Injection Report](security/SQL_INJECTION_VULNERABILITY_REPORT)
- [SSRF Protection](security/SSRF_PROTECTION)
- [Admin Auth Configuration](security/ADMIN_AUTH_CONFIGURATION)

### Test Documentation & Reports
- [Testing Guide](TESTING)
- [Test Suite Stabilization Report (2026-03-01)](test-suite-stabilization-report-2026-03-01) - **100% Pass Rate** attainment details
- [Security and Architectural Remediation Report (2026-03-02)](security-and-architectural-remediation-report-2026-03-02) - Final remediation and 100% stability results
- [Test Documentation Index](tests/README) - Complete index of all test classes

### Guides & References
- [Script Development](guides/SCRIPT_DEVELOPMENT)
- [Objective-C Tips](guides/objective_c_tips)
- [Deployment](guides/DEPLOYMENT)
- [Development Workflows](guides/DEVELOPMENT_WORKFLOWS)
- [macOS Network Server Guide](guides/macOS_Network_Server_Guide)

## Related Documentation

This section provides quick links to key documentation in each subfolder:

| Topic | Key Documents |
|-------|---------------|
| **Architecture** | [PDS Architecture](architecture/atproto_pds_architecture), [Data Models](architecture/atproto_data_models), [Diagrams](architecture/DIAGRAMS_MERMAID) |
| **Guides** | [Developer Guide](guides/DEVELOPER_GUIDE), [Setup Guide](guides/SETUP_GUIDE), [Deployment](guides/DEPLOYMENT) |
| **OAuth2** | [Overview](oauth2/README), [Authorization Flow](oauth2/authorization-flow), [DPoP](oauth2/dpop) |
| **Security** | [Testing Plan](security/SECURITY_TESTING_PLAN), [Analysis Report](security/SECURITY_ANALYSIS_REPORT), [Identity Hardening](security/IDENTITY_HARDENING) |
| **Testing** | [Test Index](tests/README), [Identity/Auth](tests/00-identity-auth/README), [Repository](tests/01-repository/README) |

## Project Links

- [Main Project README](../README)
- [Agent Instructions (AGENTS.md)](../AGENTS)
