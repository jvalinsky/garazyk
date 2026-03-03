# macOS/XNU Integration Plan

**Date:** 2026-01-16
**Binary Name:** september
**Author:** opencode

## Overview

macOS integration for the ATProto PDS CLI tool: background service operation, security hardening, system integration, and distribution.

## User Requirements Confirmed

- **Service Management**: Both LaunchAgent (user session) + optional LaunchDaemon (headless)
- **Security**: Biometric protection enabled by default for new installs
- **Binary Name**: `september` (mystery brand, kept)

## Phases

### Phase 1: Service Management & Installation
- New CLI commands: `install`, `uninstall`, `service status|start|stop`, `service logs`
- LaunchDaemon for system-wide background operation
- LaunchAgent for user session integration
- Dedicated `_pds` system user
- Installer script with upgrade path

### Phase 2: Security Hardening  
- Biometric keychain storage (Touch ID/Face ID)
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` by default
- Keychain upgrade path for existing installations
- New error codes for biometric failures

### Phase 3: System Integration
- Spotlight indexing for at:// URIs
- Quick Look previews for records
- os_signpost performance instrumentation
- Crash reporting integration

### Phase 4: Distribution
- Homebrew formula for easy installation
- GitHub Actions release workflow
- Code signing and notarization

### Phase 5: Network & Power
- NWPathMonitor for network quality detection
- Bonjour service discovery
- Sleep/wake notification handling

### Phase 6: Diagnostic Tools
- `pds diag` command for full system reports
- CPU/memory profiling
- Performance trace export

## Files Created

| File | Description |
|------|-------------|
| `ATProtoPDS/Sources/Admin/PDSInstallerCommand.m` | Install/uninstall/service commands |
| `ATProtoPDS/Sources/Admin/PDSDiagnosticCommand.m` | Diagnostic commands |
| `ATProtoPDS/Sources/Security/PDSBiometricKeychain.h/m` | Touch ID keychain wrapper |
| `ATProtoPDS/Sources/System/PDSSpotlightIndexer.h/m` | Spotlight integration |
| `ATProtoPDS/Sources/System/PDSQuickLookGenerator.h/m` | Quick Look previews |
| `ATProtoPDS/Sources/Network/PDSNetworkMonitor.h/m` | Network monitoring |
| `ATProtoPDS/Sources/Network/PDSBonjourPublisher.h/m` | Service discovery |
| `ATProtoPDS/Sources/Debug/PDSPerformanceTracer.h/m` | Performance instrumentation |
| `ATProtoPDS/Resources/LaunchDaemons/com.atproto.pds.plist` | LaunchDaemon config |
| `ATProtoPDS/Resources/LaunchAgents/com.atproto.pds.user.plist` | LaunchAgent config |
| `scripts/install.sh` | Main installer |
| `scripts/uninstall.sh` | Cleanup script |
| `scripts/distribute/homebrew-atproto-pds.rb` | Homebrew formula |
| `.github/workflows/release.yml` | Release workflow |

## Verification

- [ ] `xcodegen generate` succeeds
- [ ] `xcodebuild -scheme ATProtoPDS-CLI build` succeeds
- [ ] `./build/bin/kaszlak help` shows new commands
- [ ] `./build/bin/kaszlak install` registers launchd services
- [ ] All 168 existing tests pass

---

## Related Documentation

- [Archive Index](./README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
- [Architecture Docs](../../architecture/README) - System architecture documentation
