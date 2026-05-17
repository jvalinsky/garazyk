# Core Subsystem Final Documentation Sprint Plan

## Objective

Reach 85% documentation coverage for the `Core` subsystem (currently 73%) and establish long-term
maintenance standards.

## Phase 1: Targeted Component Sprints (Immediate)

We will focus on the remaining high-impact areas identified in the coverage audit.

### Sprint 3: Repository & Sync Infrastructure (Goal: 80%)

- [ ] **Core/Repositories:**
  - `PDSSQLiteBlockRepository.h`
  - `PDSLegacyAccountRepository.h` (Documentation update)
- [ ] **Sync/Firehose:**
  - `FirehoseProtocolSession.h`
  - `FirehoseCARBuilder.h`
- [ ] **Sync/Relay:**
  - `RelayEventBuffer.h`
  - `RelayUpstreamManager.h`

### Sprint 4: Security & Core Primitives (Goal: 85%)

- [ ] **Core/Primitives:**
  - `ATURI.h`
  - `MSTCacheManager.h`
- [ ] **Security:**
  - `PDSKeyEnvelope.h`
  - `PDSAuthzManager.h`
  - `PDSBiometricKeychain.h`

## Phase 2: Maintenance & Governance

To ensure coverage does not regress after we hit our targets:

1. **Pre-commit Gate:** Integrate a local pre-commit hook that runs `deno task doc:coverage` and
   alerts the developer if coverage drops on modified files.
2. **Weekly Audit Report:** Automate a weekly summary of documentation coverage for the engineering
   team.
3. **Skill Enforcement:** Continue mandatory use of `rewriting-code-comments` for all header changes
   in PRs.

## Verification

- **CI Gate:** The CI `objc-doc-coverage` job will serve as the hard gate. Any changes must maintain
  or exceed subsystem thresholds.
- **Doxygen Sweep:** Run a final comprehensive Doxygen audit to identify and resolve any latent
  warnings.
