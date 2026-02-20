# ATProto PLC Utility Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a standalone Objective-C PLC (did:plc) server utility for AT Protocol to facilitate local testing and protocol compliance.

**Architecture:** A service-oriented binary that provides a REST API for DID resolution and operation submission. It uses a provider-based storage system (Mock/SQLite) and an auditor for signature and chain verification.

**Tech Stack:** Objective-C (Foundation), HttpServer (Local), Secp256k1 (Identity), SQLite (Persistence), CMake/XcodeGen (Build).

---

### Task 1: Project Structure & Basic Models

**Files:**
- Create: `ATProtoPDS/Sources/PLC/PLCOperation.h`
- Create: `ATProtoPDS/Sources/PLC/PLCOperation.m`
- Test: `ATProtoPDS/Tests/PLC/PLCOperationTests.m`

**Step 1: Define PLCOperation model**
Implement a model that can parse and serialize PLC operations from JSON/CBOR.

```objc
@interface PLCOperation : NSObject
@property (nonatomic, copy) NSString *did;
@property (nonatomic, copy, nullable) NSString *prev;
@property (nonatomic, copy) NSString *sig;
@property (nonatomic, copy) NSDictionary *data;
@end
```

**Step 2: Write failing test for parsing**
**Step 3: Implement minimal parsing code**
**Step 4: Verify test passes**
**Step 5: Commit**

---

### Task 2: PLC Store Interface & Mock Implementation

**Files:**
- Create: `ATProtoPDS/Sources/PLC/PLCStore.h`
- Create: `ATProtoPDS/Sources/PLC/PLCMockStore.m`
- Test: `ATProtoPDS/Tests/PLC/PLCStoreTests.m`

**Step 1: Define PLCStore protocol**
```objc
@protocol PLCStore <NSObject>
- (NSArray<PLCOperation *> *)getHistoryForDID:(NSString *)did error:(NSError **)error;
- (BOOL)appendOperation:(PLCOperation *)op error:(NSError **)error;
@end
```
**Step 2: Implement PLCMockStore (In-memory)**
**Step 3: Write tests for store operations**
**Step 4: Verify tests pass**
**Step 5: Commit**

---

### Task 3: PLC Auditor (Chain Verification)

**Files:**
- Create: `ATProtoPDS/Sources/PLC/PLCAuditor.h`
- Create: `ATProtoPDS/Sources/PLC/PLCAuditor.m`
- Test: `ATProtoPDS/Tests/PLC/PLCAuditorTests.m`

**Step 1: Implement Chain Verification**
Verify `prev` hashes and signature validity using `Secp256k1`.
**Step 2: Write failing test with invalid signature**
**Step 3: Implement verification logic**
**Step 4: Verify test fails then passes**
**Step 5: Commit**

---

### Task 4: PLC Server & REST API

**Files:**
- Create: `ATProtoPDS/Sources/PLC/PLCServer.h`
- Create: `ATProtoPDS/Sources/PLC/PLCServer.m`
- Modify: `ATProtoPDS/Sources/Network/HttpServer.m` (if needed for routing)
- Test: `ATProtoPDS/Tests/PLC/PLCServerTests.m`

**Step 1: Implement GET /:did and POST /:did**
**Step 2: Write integration test using NSURLSession**
**Step 3: Implement server handlers**
**Step 4: Verify tests pass**
**Step 5: Commit**

---

### Task 5: Web Dashboard

**Files:**
- Create: `ATProtoPDS/Sources/PLC/Assets/index.html`
- Create: `ATProtoPDS/Sources/PLC/Assets/css/style.css`
- Create: `ATProtoPDS/Sources/PLC/Assets/js/app.js`
- Modify: `ATProtoPDS/Sources/PLC/PLCServer.m`

**Step 1: Implement static file serving**
Add `serveStaticFile:` and `assetsPath` to `PLCServer`.
**Step 2: Add routes**
Add routes for `/`, `/css/:file`, `/js/:file`.
**Step 3: Create Web UI**
Implement `index.html` and supporting assets for a simple DID explorer.
**Step 4: Verify Dashboard loads**
**Step 5: Commit**

---

### Task 6: Standalone Binary & Build Integration

**Files:**
- Create: `ATProtoPDS/Sources/PLC/main.m`
- Modify: `project.yml`
- Modify: `CMakeLists.txt`

**Step 1: Create main.m with CLI argument parsing**
**Step 2: Add atproto-plc target to project.yml**
**Step 3: Add atproto-plc target to CMakeLists.txt**
**Step 4: Run `xcodegen generate` and build**
**Step 5: Verify binary runs**
**Step 6: Commit**

---

## Related Documentation

- [Archive Index](./README.md) - Index of all archived plans
- [Current Plans](../README.md) - Active implementation plans
- [Architecture Docs](../../architecture/README.md) - System architecture documentation
