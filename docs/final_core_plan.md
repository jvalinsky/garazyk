# Final Core Documentation Sprint Plan

## Objective

Reach 85% documentation coverage for the `Core` subsystem. Current status: ~74%.

## Remaining Tasks (Prioritized by Impact)

### 1. Repository Infrastructure (Target: 80%)

- [ ] **Core/Repositories:**
  - `PDSAccountRepository.h`
  - `PDSSessionRepository.h`
- [ ] **Core/Primitives:**
  - `ATURI.h`
  - `MSTCacheManager.h`

### 2. Sync & Relay Infrastructure (Target: 83%)

- [ ] **Sync/Firehose:**
  - `FirehoseProtocolSession.h`
  - `FirehoseCARBuilder.h`
- [ ] **Sync/Relay:**
  - `RelayEventBuffer.h`
  - `RelayUpstreamManager.h`
  - `RelayConfiguration.h`
  - `RelayMetrics.h`

### 3. Security & Final Push (Target: 85%)

- [ ] **Security:**
  - `PDSKeyEnvelope.h`
  - `PDSAuthzManager.h`
  - `PDSSecurityCompare.h`
  - `PDSBiometricKeychain.h`
- [ ] **Sync/WebSocket:**
  - `PDSWebSocketServer.h`
  - `WebSocketCodec.h`

## Execution Strategy

1. **Batch Processing:** Document 2-3 headers per interaction to maximize context usage and maintain
   quality.
2. **Review Cycle:** Perform a mini-audit after every 3 headers to update the coverage status.
3. **Standards:** Every header edit will be accompanied by a run of
   `deno run -A scripts/docs/doc-coverage.ts Garazyk/Sources --by-subsystem` to confirm progress.

## Governance & Maintenance

- Once 85% is reached:
  - Lock the `objc-doc-coverage` gate in CI at the current achieved percentage for the `Core`
    subsystem.
  - Initiate a final Doxygen report cleanup (target 0 warnings).
  - Remove the `docs/core_documentation_plan.md` plan file.
