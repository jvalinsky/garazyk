# Core Subsystem Documentation Subplans

## 1. Core/Repositories (Target: PDSAccountRepository.h, PDSSessionRepository.h)

- **Strategy:** Formalize the repository contract. Define the purpose of the methods and clear
  return/error expectations.
- **Key Elements:**
  - Document method purpose: `Account`, `Session` storage management.
  - Clarify `NSError` usage.
  - Document protocol requirements for implementations.
- **Verification:** Run `doc-coverage` for file to verify coverage > 80%.

## 2. Core/Primitives (Target: ATURI.h, MSTCacheManager.h)

- **Strategy:** Focus on structural contracts. Clarify URI parsing behavior and cache invalidation
  policies.
- **Key Elements:**
  - `ATURI`: Document parsing logic, validation, and components.
  - `MSTCacheManager`: Document cache size, eviction policy, and thread safety if applicable.
- **Verification:** Confirm coverage improvement per file.

## 3. Sync/Firehose (Target: FirehoseProtocolSession.h, FirehoseCARBuilder.h)

- **Strategy:** Document session lifecycle and CAR format building logic.
- **Key Elements:**
  - `FirehoseProtocolSession`: Document states (handshake, active, closed) and event handling.
  - `FirehoseCARBuilder`: Document serialization process, error handling for CAR format compliance.
- **Verification:** Audit protocol compliance.

## 4. Sync/Relay (Target: RelayEventBuffer.h, RelayUpstreamManager.h, RelayConfiguration.h, RelayMetrics.h)

- **Strategy:** Document orchestration logic for relay events.
- **Key Elements:**
  - `RelayEventBuffer`: Buffer management, capacity limits.
  - `RelayUpstreamManager`: Connection lifecycle, event processing.
- **Verification:** Ensure metrics/buffer logic is fully annotated.

## 5. Security (Target: PDSKeyEnvelope.h, GZAuthzManager.h, PDSSecurityCompare.h, PDSBiometricKeychain.h)

- **Strategy:** Focus on security contracts. Ensure all cryptographic/authz methods define
  input/output security guarantees.
- **Key Elements:**
  - Clear warnings regarding potential security side effects.
  - Explicitly document nullability for sensitive parameters.
- **Verification:** Security-focused audit (check for Doxygen `@warning` or `@throws` tags).

## 6. Sync/WebSocket (Target: PDSWebSocketServer.h, WebSocketCodec.h)

- **Strategy:** Focus on network protocol handling and framing.
- **Key Elements:**
  - Document WebSocket framing, codec mapping, and frame-handling lifecycle.
- **Verification:** Ensure protocol/interface compliance documentation is clear.
