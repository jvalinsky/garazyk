# Detailed Next Steps Plan

## Overview

This plan details the execution steps for **Phase 12 (Architecture Refinement)** and **Phase 11 (Production Hardening)**. These phases address technical debt and prepare the PDS for real-world usage.

---

## Phase 12: Architecture Refinement (Priority: High)

**Goal**: Complete the transition from the monolithic `PDSController` to the modular `PDSApplication` architecture. Eliminate "God Object" anti-patterns.

### 12.1. Dependency Injection Cleanup (`XrpcMethodRegistry`)
The `XrpcMethodRegistry` currently accepts `PDSApplication` but still extracts `legacyController` to pass to helper functions. This enforces a dependency on the legacy controller.

- [ ] **Refactor `registerServerAccountAndSessionMethods`**
  - Change signature to accept `PDSAccountService` and `PDSConfiguration` directly instead of `PDSController`.
  - Update implementations to use extraction logic from services.
- [ ] **Refactor `extractDIDFromAuthHeader`**
  - Currently takes `PDSController` to access `serverHost` or `jwtMinter`.
  - Update to accept `PDSConfiguration` or `JWTMinter` directly.
- [ ] **Remove `application.legacyController` usage**
  - Identify all call sites in `registerMethodsWithDispatcher:application:`.
  - Replace with specific service properties from `PDSApplication` (e.g., `adminController`, `repoService`).

### 12.2. PDSController as Pure Facade
Once `XrpcMethodRegistry` no longer needs `PDSController` for logic, we can gut `PDSController`.

- [ ] **Deprecate Legacy Init**
  - Mark `initWithDirectory:serviceMaxSize:...` as deprecated.
  - Ensure it internally creates a `PDSApplication` if used.
- [ ] **Remove Internal State**
  - Remove ivars like `_repoQueue`, `_repos` from `PDSController` if they are now owned by `PDSRepositoryService`.
  - `PDSController` should have *zero* logic, only forwarding calls to `_backingApplication`.

### 12.3. Service Boundaries
- [ ] **Audit `PDSAccountService`**: Ensure it doesn't call back into `PDSController`.
- [ ] **Audit `PDSRepositoryService`**: Ensure MST persistence is fully encapsulated.

---

## Phase 11: Production Hardening (Priority: High)

**Goal**: Verify the PDS works with real-world clients and workloads.

### 11.1. Manual Verification with Bluesky Client
Connect the official Bluesky iOS/Web app to your local PDS.

- [ ] **Network Exposure**
  - Set up `ngrok` or similar tunnel to expose local port 2583.
  - Update `PDS_PUBLIC_URL` environment variable.
- [ ] **Client Connection**
  - Use "Sign In" -> "Other Server" in Bluesky client.
  - Enter PDS URL (e.g., `https://your-ngrok.io`).
  - Attempt login / account creation.
- [ ] **Feature Verification**
  - Create Post (text, image).
  - Like/Repost.
  - Update Profile.
  - Verify data persists in local PDS.

### 11.2. Performance Profiling
- [ ] **Profile MST Rebuilds**
  - The current implementation performs a full O(N) rebuild of the Merkle Search Tree on every write.
  - **Task**: Instrument `MST.m` to measure rebuild time vs repo size.
  - **Optimization**: Implement delta updates or partial path rebuilding.
- [ ] **SQLite Concurrency**
  - Review `PDSDatabasePool` settings.
  - Ensure WAL mode is enabled for high concurrency.

---

## Execution Order
1.  **Phase 12.1**: Unblock clean DI in XRPC Registry.
2.  **Phase 12.2**: Finalize PDSController refactor.
3.  **Phase 11.1**: Manual Verification (can be done in parallel).
4.  **Phase 11.2**: Performance optimization (based on findings from 11.1).
