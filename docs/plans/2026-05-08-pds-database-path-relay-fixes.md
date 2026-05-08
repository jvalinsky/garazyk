# PDS Database Path / Relay Integration Fix Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix PDS database path resolution so sequencer/DID cache use the configured `data_dir`, enable relay crawling by restoring event persistence, and harden production operations.

**Architecture:** `kaszlak` PDS has three database pools (service, did_cache, sequencer). The `data_dir` config (`DEPLOY_DIR/pds-data`) is correctly propagated to `PDSApplication` and its `ServiceDatabases` instance, but `PDSHealthCheck` and `PDSReadinessCheck` bypass it via `[PDSServiceDatabases sharedInstance]` which hardcodes `~/.local/share/ATProtoPDS`. The sequencer at the correct path has 16 orphaned events (seq 20-35) that relays never see because the health/readiness components (and anything else using `sharedInstance`) open separate connections to empty databases at the default path.

**Tech Stack:** Objective-C, SQLite (WAL mode), GNUstep, systemd, Docker, AT Protocol (XRPC, firehose/SubscribeRepos)

---

### Task 1: Fix PDSHealthCheck to use injected ServiceDatabases

**Files:**
- Modify: `Garazyk/Sources/Database/Monitoring/PDSHealthCheck.h` — add `initWithServiceDatabases:`
- Modify: `Garazyk/Sources/Database/Monitoring/PDSHealthCheck.m` — replace `sharedInstance` references
- Modify: `Garazyk/Sources/Network/PDSHttpServerBuilder.m` — wire health check with injected instance

**Diagnosis:** `PDSHealthCheck` calls `[PDSServiceDatabases sharedInstance]` in 7 places (lines 50, 68, 112, 147, 171, 196, 200). `sharedInstance` hardcodes `~/.local/share/ATProtoPDS` (ServiceDatabases.m:97-108) regardless of the configured `data_dir`. This causes the `GET /xrpc/_health` endpoint to report database status from the wrong (empty) databases.

**Step 1.1: Add init method to PDSHealthCheck.h**

Add before `@end` in `PDSHealthCheck.h`:

```objc
- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases;
```

**Step 1.2: Add instance variable and init to PDSHealthCheck.m**

Add property in implementation:

```objc
@interface PDSHealthCheck ()
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@end
```

Replace `sharedInstance` singleton with init:

```objc
- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases {
    self = [super init];
    if (self) {
        _serviceDatabases = serviceDatabases;
    }
    return self;
}
```

**Step 1.3: Replace all `sharedInstance` calls**

Replace every `[PDSServiceDatabases sharedInstance]` with `self.serviceDatabases` (7 locations):

| File:Line | Current Code | Replace With |
|---|---|---|
| HealthCheck.m:50 | `[[PDSServiceDatabases sharedInstance].servicePool collectMetrics]` | `[self.serviceDatabases.servicePool collectMetrics]` |
| HealthCheck.m:68 | `PDSServiceDatabases *serviceDb = [PDSServiceDatabases sharedInstance];` | `PDSServiceDatabases *serviceDb = self.serviceDatabases;` |
| HealthCheck.m:112 | same | same |
| HealthCheck.m:147 | same | same |
| HealthCheck.m:171 | same | same |
| HealthCheck.m:196 | same | same |
| HealthCheck.m:200 | `[serviceDb.sequencerPool collectMetrics]` | `[self.serviceDatabases.sequencerPool collectMetrics]` |

**Step 1.4: Wire PDSHealthCheck in PDSHttpServerBuilder**

In `PDSHttpServerBuilder.m`, find where the health check is instantiated and change:

```objc
// Before (likely):
PDSHealthCheck *healthCheck = [PDSHealthCheck sharedInstance];

// After:
PDSHealthCheck *healthCheck = [[PDSHealthCheck alloc] initWithServiceDatabases:self.serviceDatabases];
```

If health check is created inside the route handler block, capture `serviceDatabases` with a weak reference.

**Step 1.5: Build & verify**

Run: `cd /Users/jack/Software/garazyk && xcodegen generate && cmake --build build-linux --target kaszlak`
Expected: Build succeeds

**Step 1.6: Deploy & test**

Copy binary to server. Restart PDS. Call `GET /xrpc/_health`.

Run: `curl -s 'http://localhost:2583/xrpc/_health' | python3 -m json.tool`
Expected: `db_path` shows `DEPLOY_DIR/pds-data/service/service.db`

---

### Task 2: Fix PDSReadinessCheck to use injected ServiceDatabases

**Files:**
- Modify: `Garazyk/Sources/App/PDSReadinessCheck.h` — change signatures to accept `PDSServiceDatabases *`
- Modify: `Garazyk/Sources/App/PDSReadinessCheck.m` — replace `sharedInstance` calls
- Modify: `Garazyk/Sources/App/PDSApplication.m` — pass `_serviceDatabases` to readiness check

**Diagnosis:** `checkDatabasePools:` (line 60) and `checkSigningKeys:` (line 143) use `[PDSServiceDatabases sharedInstance]`, opening wrong-path DBs during startup and potentially causing false negatives.

**Step 2.1: Update PDSReadinessCheck.h signatures**

```objc
+ (BOOL)performReadinessChecksWithConfig:(PDSConfiguration *)config
                       serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                                  error:(NSError **)error;
```

**Step 2.2: Update PDSReadinessCheck.m**

Change `checkDatabasePools:error:` to accept `serviceDatabases` parameter:

```objc
+ (BOOL)checkDatabasePools:(PDSServiceDatabases *)serviceDatabases
                     error:(NSError **)error {
    // remove: PDSServiceDatabases *serviceDatabases = [PDSServiceDatabases sharedInstance];
    // use parameter directly
    ...
}
```

Similarly for `checkSigningKeys:error:` — accept and use parameter.

**Step 2.3: Update PDSApplication.m caller**

Find where `[PDSReadinessCheck performReadinessChecksWithConfig:error:]` is called and pass `_serviceDatabases`.

**Step 2.4: Build, deploy, verify**

Same as Task 1.5-1.6.

---

### Task 3: Seal the `sharedInstance` pattern

**Files:**
- Modify: `Garazyk/Sources/Database/Service/ServiceDatabases.m` — deprecate `sharedInstance`
- Optionally: `Garazyk/Sources/Database/Service/ServiceDatabases.h` — add deprecation warning

**Diagnosis:** The `sharedInstance` singleton is a trap — it creates databases at an unconditional default path. Any future code that calls it will silently operate on the wrong data. It should be deprecated to prevent future bugs.

**Step 3.1: Add deprecation attribute in header**

```objc
+ (instancetype)sharedInstance DEPRECATED_MSG_ATTRIBUTE("Use initWithDirectory:serviceMaxSize:didCacheMaxSize:sequencerMaxSize: with dataDirectory from PDSApplication instead");
```

**Step 3.2: Add log warning in implementation**

```objc
+ (instancetype)sharedInstance {
    static PDSServiceDatabases *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        PDS_LOG_CORE_WARN(@"PDSServiceDatabases sharedInstance uses default path (~/.local/share/ATProtoPDS). "
                          @"Callers should use injected instance from PDSApplication.");
        // ... existing code
    });
    return shared;
}
```

**Step 3.3: Build & verify**

---

### Task 4: Clean up disk space on server

**Files:** (operational — no code changes)

**Diagnosis:** Root partition is 91% full (19GB total, 1.7GB free). Docker images consume 7.3GB, build cache 1.7GB. No swap configured.

**Step 4.1: Docker cleanup**

Run on server:
```bash
docker system prune -af --volumes 2>/dev/null
docker image prune -af
```

**Step 4.2: Remove old build artifacts**

Run:
```bash
rm -rf DEPLOY_DIR/objpds/build
rm -rf DEPLOY_DIR/objpds/build-linux
# Then rebuild:
cd DEPLOY_DIR/objpds
cmake --build build-linux --target kaszlak
```

**Step 4.3: Add swap file**

```bash
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

**Step 4.4: Verify**

Run: `df -h /`
Expected: Usage < 60%

---

### Task 5: Create systemd service for PDS

**Files:** (operational — create `/etc/systemd/system/kaszlak.service`)

**Diagnosis:** PDS runs as PID 1 child with no service file, no auto-restart, stdout/stderr going to a socket (not captured). No startup mechanism visible (no crontab, no screen/tmux, no systemd unit).

**Step 5.1: Create service file**

```ini
[Unit]
Description=garazyk PDS (kaszlak)
After=network.target

[Service]
Type=simple
User=DEPLOY_USER
WorkingDirectory=DEPLOY_DIR/objpds
ExecStart=DEPLOY_DIR/objpds/build-linux/bin/kaszlak serve \
    --port 2583 \
    --hostname 0.0.0.0 \
    --config DEPLOY_DIR/objpds/config/production.json \
    --foreground
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

**Step 5.2: Enable and start**

```bash
sudo systemctl daemon-reload
sudo systemctl enable kaszlak
sudo systemctl start kaszlak
```

**Step 5.3: Verify**

Run: `sudo systemctl status kaszlak`
Expected: active (running), recent journal entries visible

---

### Task 6: Investigate and fix records/repos storage

**Files:**
- Investigate: `Garazyk/Sources/Services/PDS/PDSAccountService.m` — account creation flow
- Investigate: `Garazyk/Sources/Database/ActorStore/` — per-actor storage

**Diagnosis:** The `records`, `repos`, and `blocks` tables in the main service DB are empty (0 rows each) despite 8 accounts existing. However, `describeRepo` returns `collectionStats` with counts. There are 16 commit events in the orphaned sequencer DB (`DEPLOY_DIR/pds-data/sequencer/service.db`) that contain actual record data (posts and profiles from May 5). The current PDS process (binary built May 8) may be using a different storage strategy than the old process.

**Step 6.1: Determine where records are stored**

On the server, check if actor store databases exist per-DID:
```bash
find DEPLOY_DIR -name '*.db' | xargs -I{} sh -c 'echo "=== {} ===\n$(sqlite3 {} .tables 2>/dev/null | grep -c records)"'
```

Also dump the actual record content from the sequencer events:
```bash
sqlite3 DEPLOY_DIR/pds-data/sequencer/service.db \
  "SELECT seq, event_type, length(event_data) FROM events ORDER BY seq"
```

**Step 6.2: Check account creation code path**

In `PDSAccountService.m`, trace what happens after `createAccount:`:
- Does it create a repo entry?
- Does it initialize an actor store?
- Does it persist events to the sequencer?

Look for methods like `createAccount`, `initializeActorStore`, `createRepo` in:
- `PDSAccountService.m`
- `PDSRepositoryFactory.m`
- `PDSActorStore.m`

**Step 6.3: Create a test account to verify flow**

Use the AdminUI or direct XRPC call to create a new account and a post, then verify:
```bash
# After account creation:
sqlite3 DEPLOY_DIR/pds-data/service/service.db 'SELECT COUNT(*) FROM accounts;'

# After post creation:  
sqlite3 DEPLOY_DIR/pds-data/service/service.db 'SELECT COUNT(*) FROM records;'
sqlite3 DEPLOY_DIR/pds-data/sequencer/service.db 'SELECT COUNT(*) FROM events;'
```

Expected: records > 0, events > 0

If records remain 0, the storage strategy has changed and the describeRepo `collectionStats` is returning cached/stale data — this needs a deeper code audit.

---

### Task 7: Diagnose describeRepo timeout for uncached DIDs

**Files:**
- Investigate: `Garazyk/Sources/Core/DID.m` — DID resolution and caching
- Investigate: `Garazyk/Sources/Network/XrpcRepoMethods.m` — describeRepo handler

**Diagnosis:** First call to `describeRepo` for a DID is fast (20ms) if cached, but subsequent calls to other DIDs timeout at 30s+. The sync `resolveDIDSync:` call in the handler (`XrpcRepoMethods.m:889`) is the likely culprit — it performs a synchronous HTTP request to `plc.directory` via `PDSSafeHTTPClient`.

**Step 7.1: Check PDSSafeHTTPClient timeout configuration**

```bash
rg 'timeout|Timeout|TIMEOUT' Garazyk/Sources/Core/PDSSafeHTTPClient.m
```

Look for:
- Default request timeout
- Whether it has a long default timeout (e.g., 60s)
- Whether it retries on failure

**Step 7.2: Add diagnostic logging**

If not easily reproducible, add logging to describeRepo handler:
```objc
PDS_LOG_CORE_DEBUG(@"describeRepo: resolving DID %@ synchronously...", did);
// ... existing resolveDIDSync call ...
PDS_LOG_CORE_DEBUG(@"describeRepo: DID %@ resolved in %.2fms", did, elapsed * 1000);
```

**Step 7.3: Consider callback-based resolution**

If sync resolution is confirmed as the bottleneck, refactor `describeRepo` to use async resolution with a 5s timeout:
- Replace `resolveDIDSync:` with `resolveDID:completion:` pattern
- In the async callback, complete the HTTP response

---

### Task 8: Verification and relay testing

**Files:** (no code changes — operational testing)

**Step 8.1: Test describeRepo for all 8 accounts**

```bash
for did in $(sqlite3 DEPLOY_DIR/pds-data/service/service.db 'SELECT did FROM accounts'); do
    echo "=== $did ==="
    curl -s -o /dev/null -w 'HTTP %{http_code} - Time: %{time_total}s\n' \
      "http://localhost:2583/xrpc/com.atproto.repo.describeRepo?repo=$did"
done
```

Expected: All return 200 in < 2s

**Step 8.2: Test firehose subscription**

```bash
timeout 5 curl -s -N \
  -H "Accept: application/vnd.ipld.cbor" \
  "http://localhost:2583/xrpc/com.atproto.sync.subscribeRepos" 2>&1 | xxd | head -20
```

Expected: Receive CBOR-encoded event frames (commit, identity, or account events)

**Step 8.3: Test external relay connectivity**

From the server, test bsky.network relay:
```bash
curl -s -w '\nHTTP %{http_code} - Time: %{time_total}s\n' \
  "https://bsky.network/xrpc/com.atproto.sync.listRepos" | head -5
```

Expected: Returns list of repos known to the relay

**Step 8.4: Verify account appears in bsky appview**

```bash
curl -s "https://public.api.bsky.app/xrpc/app.bsky.actor.getProfile?actor=zubr.garazyk.xyz"
```

Expected: Returns profile if relay has crawled the PDS

---

### Task 9: Housekeeping — remove stale duplicate databases

**Files:** (operational)

**Diagnosis:** The `~/.local/share/ATProtoPDS/` directory contains empty database files that were created by the `sharedInstance` code path. After fixing Tasks 1-3, this directory will no longer be written to.

**Step 9.1: Backup and remove**

```bash
cp -a DEPLOY_DIR/.local/share/ATProtoPDS DEPLOY_DIR/.local/share/ATProtoPDS.backup
rm -rf DEPLOY_DIR/.local/share/ATProtoPDS
```

**Step 9.2: Verify no impact**

After removal, restart PDS and verify all endpoints work.

---

## Execution Order

Tasks are ordered by dependency and urgency:

1. **Task 4** (disk cleanup) — immediate relief, no code changes
2. **Task 5** (systemd service) — operational hardening, no code changes
3. **Tasks 1-3** (code fixes for sharedInstance) — fixes health/readiness reporting
4. **Task 6** (records investigation) — understand data storage
5. **Task 7** (describeRepo timeout) — diagnose if still an issue after fixes
6. **Task 8** (verification) — confirm all fixes work
7. **Task 9** (cleanup) — final cleanup
