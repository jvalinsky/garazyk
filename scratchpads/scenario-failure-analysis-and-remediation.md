# Scenario Failure Analysis and Remediation Plan

This document synthesizes recent debugging efforts regarding E2E scenario flakiness, app crashes, and SQLite corruption, offering concrete evidence, root causes, and long-term engineering solutions.

## 1. AppView Boot Crash (CBOR Parsing)

### Issue
The AppView backend crashed on boot when attempting to process backfilled records. The stack trace revealed an uncaught `NSException` inside `NSJSONSerialization`.

### Evidence & Explanation
The crash originated in [AppViewBackfillWorker.m](file:///Users/jack/Software/garazyk/Garazyk/Sources/AppView/Server/Backfill/AppViewBackfillWorker.m). The AppView ingests records in CBOR format, which natively supports byte arrays (often used for CIDs). The parser translates these byte arrays into `NSData` objects. 
When the worker blindly passed the resulting `NSDictionary` to `[NSJSONSerialization dataWithJSONObject:...]`, it crashed because `NSData` is not a valid JSON type.

**Current Hotfix:**
A patch was applied to check `[NSJSONSerialization isValidJSONObject:targetDict]` before serialization, dropping invalid records to prevent the crash.

**Proposed Solution:**
Implement a proper CBOR-to-JSON transcoder in the data pipeline. Whenever a CBOR object is converted for JSON serialization, byte arrays representing CIDs should be explicitly transcoded into IPLD Link objects (`{"$link": "bafy..."}`) or standard base64/base32 strings, ensuring zero data loss and safe JSON serialization.

## 2. SQLite Disk I/O Error (WAL & Lock Collisions)

### Issue
Sequential scenario runs (e.g., via `run_scenarios.ts --binary`) failed deterministically during the initial `com.atproto.server.createAccount` call with a `disk I/O error`.

### Evidence & Explanation
The `hamownia` orchestration runner uses abrupt process termination. Scripts such as [preflight.ts](file:///Users/jack/Software/garazyk/packages/hamownia/preflight.ts) and [stale_cleanup.ts](file:///Users/jack/Software/garazyk/packages/hamownia/stale_cleanup.ts) send `kill -9` (SIGKILL) to wipe out previous runs.
When SQLite is operating in WAL mode, a `SIGKILL` denies it the opportunity to gracefully flush the Write-Ahead Log to the main database and delete the `*-shm` (shared memory lock) files. When the next test rapidly boots the PDS, the new SQLite instance collides with the stale locks from the violently killed process, causing the first operation to fail.

**Proposed Solution:**
- **Runner Level (DRY & Graceful Teardown):** Currently, both `preflight.ts` (`checkHostPorts`) and `stale_cleanup.ts` (`stopStaleHostProcesses`) run the exact same `lsof` and `kill -9` routines sequentially during boot. Remove `checkHostPorts` from `preflight.ts` entirely to eliminate the DRY violation. In `stale_cleanup.ts`, change the signal from `-9` (SIGKILL) to `-15` (SIGTERM). Also, ensure each scenario uses a randomized ephemeral database folder (e.g., `/tmp/garazyk-test-<run_id>`).
- **Binary Level:** Use `[[GZSignalManager sharedManager] registerHandlerForSignal:SIGTERM handler:...]` to trap termination requests. The handler should trigger the service teardown sequence, calling `sqlite3_close()` to flush WAL files safely before the process exits.

## 3. Dangling Port 30s Timeouts (Socket Exhaustion)

### Issue
During rapid scenario execution, the orchestration runner hangs for 30 seconds waiting for the PDS or AppView to become healthy, eventually timing out.

### Evidence & Explanation
When a test tears down a binary and immediately starts a new one on the exact same port (e.g., 2583), the operating system keeps the recently closed TCP sockets in a `TIME_WAIT` state to ensure all lingering packets are handled.
Because the socket is technically still in use by the OS, the newly booted binary silently fails to `bind()` to the port. The runner then waits 30 seconds for the HTTP health check to pass, but since no binary is actually listening, the timeout is inevitable.

**Proposed Solution:**
- **Binary Level:** Apple's Network framework is used in `ATProtoNetworkTransportMac.m`. We must call `nw_parameters_set_reuse_local_address(parameters, true)` when constructing the `nw_listener_t`. This prevents the `EADDRINUSE` errors when restarting a listener on a port in `TIME_WAIT`.
- **Runner Level:** Implement a `wait-for-port-release` polling loop in the orchestrator before booting a new binary, ensuring the port is genuinely free.

---

## Master Implementation Plan

To execute the immediate fixes (building Beskid, staging, and running the Docker network), along with the remediations above, follow this sequence:

1. **Remediate Infrastructure:**
   - Update `packages/hamownia` to use `SIGTERM` instead of `SIGKILL` and ensure isolated database instances.
   - Set `SO_REUSEADDR` on TCP socket bindings in the Objective-C networking layer.
2. **Build Binaries:** 
   - Run `xcodegen generate` and compile out-of-source via CMake to include the new `beskid` target and networking changes.
3. **Stage Binaries:** 
   - Run `deno run -A scripts/stage_binaries.ts` to provision the binaries for Docker.
4. **Deploy & Test:**
   - Rebuild Docker via `docker compose -f docker/local-network/docker-compose.yml build`.
   - Start the network and run the newly unblocked cache scenarios (`60|69|75|92`).
