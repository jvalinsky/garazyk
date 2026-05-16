---
title: "Refined Plan: PureDarwin Build Target for objpds"
---

# Refined Plan: PureDarwin Build Target for objpds

## Updated Objectives (Incorporating User Preferences)
Create a PureDarwin build target with **full feature parity** to macOS builds, targeting **PureDarwin PD-17.4 (latest stable, Darwin 17 base)**. Use **best practices** for dependency management (CMake subprojects/vendoring where possible). Generate **separate build artifacts** for different targets (macOS, Linux, PureDarwin) to avoid conflicts.

## Key Adjustments Based on Preferences
- **Full Feature Parity**: Implement complete alternatives to macOS frameworks, ensuring no functionality loss (e.g., full QR code support, equivalent networking performance).
- **Target Version**: Focus on Darwin 17 compatibility, testing against PD-17.4 VMDK.
- **Dependencies**: Prefer CMake subprojects for portability; avoid system packages to ensure consistent builds across environments.
- **Artifacts**: Use distinct output directories (e.g., `build/macos/`, `build/puredarwin/`) and target-specific naming.

## Implementation Plan (Refined)

### Phase 1: Build System Configuration
1. **PureDarwin Detection & Configuration**:
   - Add `PURE_DARWIN` CMake option with auto-detection (check for Darwin version < 18 or absence of macOS frameworks)
   - Create separate `CMakeLists-PureDarwin.txt` for target-specific settings
   - Update `project.yml` with Darwin-only SDK targeting, removing macOS deployment assumptions

2. **Artifact Separation**:
   - Modify build scripts to output to `build/${TARGET_PLATFORM}/` directories
   - Add platform suffixes to binary names (e.g., `kaszlak-puredarwin`)

### Phase 2: Core API Replacements (Full Parity Focus)
1. **Network Transport (Complete Rewrite for Parity)**:
   - Implement BSD sockets + libdispatch alternative in `ATProtoNetworkTransportDarwin.m`
   - Maintain async performance equivalent to Network.framework using kqueue/epoll patterns
   - Add connection pooling and TLS support using OpenSSL (CMake subproject)

2. **Cryptography & Security (Framework-Free)**:
   - Replace Security.framework with OpenSSL integration (subproject)
   - Ensure TOTP and auth operations use identical algorithms for parity

3. **Logging System (Unified Interface)**:
   - Create `PDLogging.h` abstraction layer with platform-specific backends
   - PureDarwin: `NSLog` fallback; macOS: `os_log` for enhanced features

### Phase 3: Feature Adaptations (No Compromises)
1. **QR Code Generation (Full Support)**:
   - Add `qrencode` as CMake subproject
   - Implement identical QR output to CoreImage version
   - Maintain PNG generation using libpng (subproject)

2. **UI/AppKit Components (Stub with Parity)**:
   - Create `PDAppDelegateDarwin.h` with stub implementations
   - Ensure CLI functionality remains identical across platforms

### Phase 4: Dependencies & Tooling (Best Practices)
1. **Vendored Dependencies**:
   - Convert all externals to CMake subprojects: `qrencode`, `openssl`, `libpng`
   - Use git submodules for version control and reproducibility
   - Build statically to avoid runtime dependencies

2. **Build Tools**:
   - Adapt XcodeGen for Darwin targets (conditional SDKROOT)
   - Add PureDarwin toolchain file for CMake

### Phase 5: Testing & Validation
1. **Build Verification**:
   - CI pipeline with PureDarwin VM testing (automate VMDK setup)
   - Cross-platform artifact generation and verification

2. **Runtime Parity Testing**:
   - Identical test suites across platforms (no PureDarwin-specific skips)
   - Performance benchmarks ensuring <10% degradation vs. macOS
   - End-to-end tests: record creation, networking, auth, QR generation

3. **Compatibility Validation**:
   - Test against PD-17.4 VMDK with real hardware simulation
   - Validate Darwin 17 API availability and behavior

## Dependencies & Prerequisites
- **PureDarwin PD-17.4 VMDK** for testing
- **New Subprojects**: qrencode, openssl, libpng (vendored)
- **Build Tools**: CMake 3.20+, XcodeGen (patched for Darwin)

## Risk Assessment & Mitigations
- **High Risk**: Full networking parity - extensive testing needed; mitigate with benchmarks
- **Medium Risk**: Dependency vendoring complexity; mitigate with clear subproject management
- **Low Risk**: Feature completeness - prioritized in plan

## Timeline Estimate (Slightly Extended for Parity)
- **Phase 1-2**: 3-4 weeks (build system + core rewrites)
- **Phase 3-4**: 2-3 weeks (feature completion + dependencies)
- **Phase 5**: 1-2 weeks (thorough testing)

## Success Criteria
- All macOS features functional on PureDarwin with identical behavior
- Successful builds and tests on PD-17.4
- Separate, clearly labeled artifacts for each platform
- No external dependencies in final binaries

## Next Steps
With these preferences incorporated, the plan is ready for implementation. Do you want to proceed, or are there any other aspects to adjust (e.g., specific timeline concerns or dependency preferences)? If ready, I can begin executing the phases.

---

## Related Documentation

- [Archive Index](README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
- [Architecture Docs](../../architecture/README) - System architecture documentation