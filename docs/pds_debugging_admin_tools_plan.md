# PDS Debugging and Admin Tools Plan

## Executive Summary

 This document outlines debugging and administration tools for the Objective-C PDS implementation. The plan draws inspiration from the Pegasus OCaml PDS implementation while adding tools specific to the Objective-C/macOS ecosystem.

---

## 1. CLI Admin Commands

### 1.1 Core Management Commands

#### `pds serve`
Start the PDS server with configurable options:
```bash
./pds serve \
  --port 2583 \
  --data-dir /path/to/data \
  --config /path/to/config.yaml \
  --log-level debug|info|warn|error \
  --foreground  # Don't daemonize
```

#### `pds health`
Check PDS health status:
```bash
./pds health              # Basic health check
./pds health --verbose    # Detailed status including DB connectivity
./pds health --json       # JSON output for scripting
```

### 1.2 Account Management Commands

#### `pds account create`
Create a new account (admin only):
```bash
./pds account create \
  --email user@example.com \
  --handle user.example.com \
  [--password secr3t] \
  [--invite-code CODE]
```

#### `pds account list`
List all accounts with pagination:
```bash
./pds account list                   # First 100 accounts
./pds account list --limit 50        # Custom limit
./pds account list --cursor ABC123   # Pagination
./pds account list --filter email    # Search filter
./pds account list --json            # JSON output
```

#### `pds account info <did|handle>`
Get detailed account information:
```bash
./pds account info did:plc:abc123
./pds account info user.example.com
```

#### `pds account deactivate <did>`
Deactivate an account:
```bash
./pds account deactivate did:plc:abc123
./pds account deactivate --reason "policy-violation" did:plc:abc123
```

#### `pds account reactivate <did>`
Reactivate a deactivated account:
```bash
./pds account reactivate did:plc:abc123
```

#### `pds account delete <did>`
Permanently delete an account (with confirmation):
```bash
./pds account delete did:plc:abc123 --confirm
```

#### `pds account update-email <did> <email>`
Update account email:
```bash
./pds account update-email did:plc:abc123 new@example.com
```

#### `pds account update-handle <did> <handle>`
Update account handle:
```bash
./pds account update-handle did:plc:abc123 newhandle.example.com
```

### 1.3 Invite Code Management

#### `pds invite create`
Create invite codes:
```bash
./pds invite create                     # Single use code
./pds invite create --uses 5            # 5 uses
./pds invite create --expires 7d        # Expires in 7 days
./pds invite create --count 10          # Create 10 codes
./pds invite create --disabled          # Create disabled code
```

#### `pds invite list`
List invite codes:
```bash
./pds invite list                       # All codes
./pds invite list --used                # Only used codes
./pds invite list --unused              # Only unused codes
./pds invite list --expired             # Include expired
```

#### `pds invite revoke <code>`
Revoke an invite code:
```bash
./pds invite revoke ABCDE-12345
```

### 1.4 Blob Management Commands

#### `pds blob list`
List blobs with filtering:
```bash
./pds blob list                     # First 100 blobs
./pds blob list --user did:plc:abc  # Filter by user
./pds blob list --mimetype image    # Filter by type
./pds blob list --size-min 1MB      # Minimum size
./pds blob list --size-max 10MB     # Maximum size
```

#### `pds blob info <cid>`
Get blob metadata:
```bash
./pds blob info bafkrei...
```

#### `pds blob delete <cid>`
Delete a blob (admin only):
```bash
./pds blob delete bafkrei... --user did:plc:abc --confirm
```

#### `pds blob export <cid> <filepath>`
Export blob to file:
```bash
./pds blob export bafkrei... /path/to/output.jpg
```

#### `pds blob migrate [options]`
Migrate blobs between storage backends:
```bash
./pds blob migrate --to s3                 # Migrate all to S3
./pds blob migrate --user did:plc:abc      # Migrate user's blobs
./pds blob migrate --dry-run               # Preview without changes
./pds blob migrate --batch-size 100        # Batch size for rate limiting
```

#### `pds blob reconcile`
Check blob integrity against repo references:
```bash
./pds blob reconcile                        # Check all
./pds blob reconcile --user did:plc:abc    # Check specific user
./pds blob reconcile --repair              # Auto-repair missing blobs
```

### 1.5 Repository Management Commands

#### `pds repo export <did>`
Export user repository:
```bash
./pds repo export did:plc:abc > repo.car
./pds repo export did:plc:abc --output /path/to/repo.car
```

#### `pds repo import <did> <filepath>`
Import repository CAR file:
```bash
./pds repo import did:plc:abc /path/to/repo.car
./pds repo import did:plc:abc /path/to/repo.car --force  # Overwrite existing
```

#### `pds repo rebuild-mst <did>`
Rebuild MST from records table (recovery):
```bash
./pds repo rebuild-mst did:plc:abc
./pds repo rebuild-mst did:plc:abc --dry-run  # Preview only
```

#### `pds repo verify <did>`
Verify repository integrity:
```root@server:~$ ./pds repo verify did:plc:abc
Verifying repository for did:plc:abc...
- MST root verified
- All blocks present
- Signature valid
- 47 records found
Repository is valid
```

#### `pds repo stats <did>`
Get repository statistics:
```bash
./pds repo stats did:plc:abc
```

### 1.6 Database Commands

#### `pds db migrate`
Run database migrations:
```bash
./pds db migrate                   # Run pending migrations
./pds db migrate --dry-run         # Preview without applying
./pds db migrate --version 5       # Migrate to specific version
./pds db migrate --reset           # Reset and reapply (DANGER!)
```

#### `pds db vacuum`
Optimize database:
```bash
./pds db vacuum                    # Standard VACUUM
./pds db vacuum --analyze          # Update statistics
./pds db vacuum --full             # Full VACUUM (locks DB)
```

#### `pds db status`
Check database status:
```bash
./pds db status                    # Connection and basic stats
./pds db status --verbose          # Detailed info
./pds db status --json             # JSON output
```

#### `pds db backup`
Create database backup:
```bash
./pds db backup /path/to/backup.db
./pds db backup --compress         # Gzip compress
./pds db backup --s3               # Upload to S3
```

### 1.7 Key and Cryptography Commands

#### `pds key generate`
Generate new signing keys:
```bash
./pds key generate                 # Generate new key pair
./pds key generate --type p256     # P-256 curve
./pds key generate --type k256     # K-256 curve
./pds key generate --output /path/to/key.pem
```

#### `pds key rotate <key-id>`
Rotate signing key:
```bash
./pds key rotate abc123
./pds key rotate abc123 --publish  # Immediately publish to PLC
```

#### `pds key list`
List active keys:
```bash
./pds key list
./pds key list --user did:plc:abc  # Filter by user
```

#### `pds key verify <data> <signature> <pubkey>`
Verify a signature:
```bash
./pds key verify "message" "base64sig" "did:key:..."
```

---

## 2. Web-Based Admin Dashboard

### 2.1 Admin UI Routes

| Route | Method | Description |
|-------|--------|-------------|
| `/admin` | GET | Admin dashboard home |
| `/admin/login` | GET/POST | Admin authentication |
| `/admin/users` | GET | User management page |
| `/admin/users?action=create` | POST | Create user |
| `/admin/users?action=edit&did=...` | POST | Edit user |
| `/admin/users?action=delete&did=...` | POST | Delete user |
| `/admin/invites` | GET/POST | Invite code management |
| `/admin/blobs` | GET/POST | Blob management |
| `/admin/blobs/view?did=...&cid=...` | GET | View blob |
| `/admin/repos` | GET | Repository list |
| `/admin/repos?did=...` | GET | Repository detail |
| `/admin/logs` | GET | Log viewer |
| `/admin/metrics` | GET | Metrics dashboard |
| `/admin/settings` | GET/POST | PDS settings |

### 2.2 Dashboard Features

#### User Management Panel
- List users with pagination and filtering
- Create new accounts
- Edit user details (email, handle)
- Deactivate/reactivate accounts
- Delete accounts with confirmation
- View user statistics (repo size, blob count)
- Password reset functionality
- TOTP management display

#### Invite Code Panel
- List all invite codes
- Filter by status (used/unused/disabled)
- Create new codes with custom use limits
- Revoke codes
- Set expiration dates

#### Blob Management Panel
- List all blobs with pagination
- Filter by user, MIME type, size
- View blob metadata
- Download blob content
- Delete blobs
- Storage backend status

#### Repository Panel
- List repositories with statistics
- View repository details
- Export repository CAR
- Rebuild MST
- Verify repository integrity

#### Settings Panel
- View current configuration
- Update rate limiting settings
- Manage storage backends
- Configure email/SMTP settings
- Manage admin accounts

---

## 3. Debugging and Logging

### 3.1 Structured Logging

```objc
// Log levels
typedef NS_ENUM(NSInteger, PDSLogLevel) {
    PDSLogLevelDebug,
    PDSLogLevelInfo,
    PDSLogLevelWarn,
    PDSLogLevelError
};

// Logger API
@interface PDSLogger : NSObject
+ (instancetype)sharedLogger;
- (void)logWithLevel:(PDSLogLevel)level
                file:(const char *)file
                line:(NSInteger)line
              format:(NSString *)format, ... NS_FORMAT_FUNCTION(5,6);
@end

// Usage
PDSLogDebug(@"Creating record: %@", record);
PDSLogInfo(@"User %@ logged in", did);
PDSLogWarn(@"Rate limit approaching for %@", did);
PDSLogError(@"Failed to process request: %@", error);
```

### 3.2 Request Logging

Log all XRPC requests with:
- Request ID (UUID)
- Timestamp
- Method/Endpoint
- User DID (if authenticated)
- Client IP
- Response status
- Response time
- Request/Response sizes

### 3.3 Debug Endpoints

#### `GET /xrpc/_debug/logs`
Return recent log entries:
```bash
curl "http://localhost:2583/xrpc/_debug/logs?level=error&limit=100"
```

#### `GET /xrpc/_debug/state`
Return internal state for debugging:
```bash
curl "http://localhost:2583/xrpc/_debug/state"
# Returns: connection pools, cache stats, queue depths, etc.
```

#### `GET /xrpc/_debug/profile`
Return profiling data:
```bash
curl "http://localhost:2583/xrpc/_debug/profile?duration=30" -o profile.prof
# CPU profile for 30 seconds
```

#### `GET /xrpc/_debug/heap`
Return heap snapshot:
```bash
curl "http://localhost:2583/xrpc/_debug/heap" -o heap.heapsnapshot
# For Instruments analysis
```

### 3.4 Request Tracing

Implement distributed tracing with:
- Trace ID propagation
- Span creation for each operation
- Trace export to Jaeger/Zipkin
- Trace ID in response headers

```bash
# Example request with trace
curl -H "X-Trace-Id: abc123" "http://localhost:2583/xrpc/com.atproto.repo.getRecord"
# Response includes trace context
```

### 3.5 Diagnostic Commands

#### `pds debug profile`
CPU profiling:
```bash
./pds debug profile --duration 30
# Outputs CPU profile to stdout or file
```

#### `pds debug traces`
Collect recent traces:
```bash
./pds debug traces --last 5m --output traces.json
```

#### `pds debug connections`
Show active connections:
```bash
./pds debug connections
# WebSocket connections, HTTP connections, DB pool status
```

#### `pds debug cache-stats`
Show cache statistics:
```bash
./pds debug cache-stats
# DID resolver cache, repo cache, blob cache stats
```

---

## 4. Health Check System

### 4.1 Health Check Endpoints

#### `GET /xrpc/_health`
Basic health check:
```json
{
  "status": "ok",
  "version": "1.0.0",
  "timestamp": "2026-01-07T14:00:00Z"
}
```

#### `GET /xrpc/_healthz`
Detailed health check:
```json
{
  "status": "ok",
  "checks": {
    "database": {"status": "ok", "latency_ms": 5},
    "storage": {"status": "ok"},
    "plc": {"status": "ok", "latency_ms": 150},
    "memory": {"status": "ok", "used_bytes": 524288000, "limit_bytes": 1073741824}
  }
}
```

### 4.2 Health Check Categories

| Check | Description | Critical |
|-------|-------------|----------|
| Database | SQLite connection and latency | Yes |
| Storage | Blob storage accessibility | Yes |
| PLC | PLC directory connectivity | Yes |
| Memory | Heap usage below threshold | Yes |
| Disk | Free disk space | No |
| Rate Limits | Rate limiter capacity | No |

### 4.3 Health Check CLI

```bash
./pds health              # Basic check
./pds health --checks all # All checks
./pds health --json       # JSON output
./pds health --watch      # Continuous monitoring
```

---

## 5. Metrics and Monitoring

### 5.1 Prometheus Metrics

#### Endpoint: `GET /metrics`

```
# HELP pds_http_requests_total Total HTTP requests
# TYPE pds_http_requests_total counter
pds_http_requests_total{method="GET",endpoint="/xrpc/com.atproto.repo.getRecord",status="200"} 1234

# HELP pds_http_request_duration_seconds HTTP request duration
# TYPE pds_http_request_duration_seconds histogram
pds_http_request_duration_seconds_bucket{endpoint="/xrpc",le="0.005"} 100
pds_http_request_duration_seconds_bucket{endpoint="/xrpc",le="0.01"} 500

# HELP pds_repository_count Total number of repositories
# TYPE pds_repository_count gauge
pds_repository_count 1234

# HELP pds_blob_count Total number of blobs
# TYPE pds_blob_count gauge
pds_blob_count 5678

# HELP pds_blob_storage_bytes Total blob storage used
# TYPE pds_blob_storage_bytes gauge
pds_blob_storage_bytes 10737418240

# HELP pds_database_size_bytes Size of database file
# TYPE pds_database_size_bytes gauge
pds_database_size_bytes 524288000

# HELP pds_active_connections Current active connections
# TYPE pds_active_connections gauge
pds_active_connections 42

# HELP pds_rate_limit_remaining Rate limit remaining for user
# TYPE pds_rate_limit_remaining gauge
pds_rate_limit_remaining{user="did:plc:abc"} 4900
```

### 5.2 Custom Metrics

#### Request Metrics
- Requests per endpoint
- Request duration (histogram)
- Request size
- Response size
- Error rate by type

#### Repository Metrics
- Repository count
- Record count per repo
- Commit frequency
- MST depth

#### Blob Metrics
- Blob count by MIME type
- Blob size distribution
- Storage backend usage
- Blob upload rate

#### Database Metrics
- Query latency
- Transaction rate
- Connection pool usage
- Lock contention

### 5.3 Metrics CLI

```bash
./pds metrics                 # Print metrics to stdout
./pds metrics --format prometheus  # Prometheus format
./pds metrics --format json        # JSON format
./pds metrics --port 9090          # Start metrics server
```

---

## 6. Recovery Tools

### 6.1 Repository Recovery

#### `pds repo recover <did>`
Recover corrupted repository:
```bash
./pds repo recover did:plc:abc
# Steps:
# 1. Verify current state
# 2. Extract all valid records from SQL
# 3. Rebuild MST from records
# 4. Verify new commit
# 5. Swap in new commit
```

#### `pds repo import-from-sql <did>`
Import repository from SQL records:
```bash
./pds repo import-from-sql did:plc:abc --output /path/to/repo.car
```

### 6.2 Account Recovery

#### `pds account reset-tokens <did>`
Reset all session tokens:
```bash
./pds account reset-tokens did:plc:abc --confirm
```

#### `pds account reset-password <did>`
Reset account password (admin):
```bash
./pds account reset-password did:plc:abc --generate-new
# Generates and displays temporary password
```

#### `pds account migrate-from <did> <old-pds-url>`
Migrate account from another PDS:
```bash
./pds account migrate-from did:plc:abc https://old-pds.example.com
```

### 6.3 Data Recovery

#### `pds recover blobs`
Find and recover orphaned blobs:
```bash
./pds recover blobs --dry-run           # Find without deleting
./pds recover blobs --delete-orphaned   # Delete orphaned blobs
./pds recover blobs --import-missing    # Import referenced but missing blobs
```

#### `pds recover repository-index`
Rebuild repository index:
```bash
./pds recover repository-index --all    # Rebuild all
./pds recover repository-index --user did:plc:abc
```

### 6.4 Emergency Procedures

#### `pds emergency lockdown`
Put PDS in lockdown mode:
```bash
./pds emergency lockdown --reason "security-incident"
# - Disables new accounts
# - Disables blob uploads
# - Read-only mode
# - Logs all requests
```

#### `pds emergency unlock`
Remove lockdown:
```bash
./pds emergency unlock
```

#### `pds emergency flush-cache`
Clear all caches:
```bash
./pds emergency flush-cache
./pds emergency flush-cache --type did-resolver
```

---

## 7. Database Utilities

### 7.1 Schema Management

#### Migration Files
```
Database/migrations/
├── 001_create_accounts.sql
├── 002_create_records.sql
├── 003_create_blobs.sql
├── 004_create_indexes.sql
├── 005_add_invites.sql
└── 006_add_migrations_table.sql
```

#### Migration Commands
```bash
./pds db status              # Show current version
./pds db migrate             # Run all pending migrations
./pds db migrate --to 5      # Migrate to specific version
./pds db rollback --to 4     # Rollback (if supported)
./pds db create-migration <name>  # Generate new migration template
```

### 7.2 Query Tools

#### `pds db query`
Execute SQL queries:
```bash
./pds db query "SELECT COUNT(*) FROM accounts"
./pds db query --json "SELECT * FROM accounts LIMIT 10"
./pds db query --explain "SELECT * FROM accounts WHERE handle LIKE '%test%'"
```

#### `pds db explain`
Explain query plan:
```bash
./pds db explain "SELECT * FROM records WHERE did = 'did:plc:abc'"
```

### 7.3 Backup and Restore

#### Backup
```bash
./pds db backup /path/to/backup.db
./pds db backup --compress /path/to/backup.db.gz
./pds db backup --s3 s3://bucket/path/
./pds db backup --incremental /path/to/
```

#### Restore
```bash
./pds db restore /path/to/backup.db
./pds db restore --s3 s3://bucket/path/backup.db
./pds db restore --incremental /path/to/incremental/
```

#### Point-in-Time Recovery
```bash
./pds db restore --point-in-time "2026-01-07 14:00:00"
```

---

## 8. Testing Utilities

### 8.1 Integration Test Runner

#### `pds test run`
Run integration tests:
```bash
./pds test run                           # All tests
./pds test run --filter "repo"           # Filter by tag
./pds test run --verbose                 # Detailed output
./pds test run --junit /path/to/report.xml  # JUnit output
./pds test run --parallel 4              # Parallel execution
```

### 8.2 Test Data Generation

#### `pds test generate-accounts`
Generate test accounts:
```bash
./pds test generate-accounts --count 100
./pds test generate-accounts --with-blobs --blob-count 50
./pds test generate-accounts --output /path/to/accounts.json
```

#### `pds test generate-repo`
Generate test repository:
```bash
./pds test generate-repo --records 1000 --blobs 100
```

### 8.3 Load Testing

#### `pds test load`
Run load test:
```bash
./pds test load --requests 10000 --concurrency 10
./pds test load --endpoint /xrpc/com.atproto.repo.getRecord
./pds test load --ramp-up 60s --ramp-down 30s
./pds test load --report /path/to/report.html
```

### 8.4 Fuzz Testing

#### `pds test fuzz`
Fuzz testing for XRPC endpoints:
```bash
./pds test fuzz --endpoint /xrpc/com.atproto.repo.createRecord
./pds test fuzz --iterations 10000
./pds test fuzz --dictionary /path/to/dict.txt
```

---

## 9. Development Tools

### 9.1 Lexicon Code Generation

Generate Objective-C types from lexicons:
```bash
./tools/gen-lexicon-types /path/to/lexicons --output ATProtoPDS/Lexicons/
```

### 9.2 CAR File Utilities

#### `pds car info <file>`
Show CAR file info:
```bash
./pds car info repo.car
# Root CID, version, block count
```

#### `pds car extract <file> <cid>`
Extract block from CAR:
```bash
./pds car extract repo.car bafy... --output block.cbor
```

#### `pds car verify <file>`
Verify CAR file:
```bash
./pds car verify repo.car
# Verify all signatures and CIDs
```

### 9.3 CID Utilities

#### `pds cid encode <data>`
Create CID from data:
```bash
./pds cid encode --raw /path/to/file
./pds cid encode --json /path/to/file
```

#### `pds cid decode <cid>`
Decode CID information:
```bash
./pds cid decode bafybeifxzt7l5jx5
# Version, codec, multihash algorithm, digest
```

---

## 10. Configuration Management

### 10.1 Config File Format (YAML)

```yaml
# PDS Configuration
pds:
  hostname: pds.example.com
  port: 2583
  data_dir: /var/lib/atprotopds
  log_level: info
  admin_password: ${ADMIN_PASSWORD}  # From environment

# Database
database:
  path: ${PDS_DATA_DIR}/pds.db
  wal_mode: true

# Storage
storage:
  blobs_dir: ${PDS_DATA_DIR}/blobs
  s3:
    enabled: false
    endpoint: ${S3_ENDPOINT}
    bucket: ${S3_BUCKET}
    access_key: ${S3_ACCESS_KEY}
    secret_key: ${S3_SECRET_KEY}

# PLC Directory
plc:
  url: https://plc.directory

# Rate Limiting
rate_limit:
  enabled: true
  rules:
    - name: repo-write
      limit: 5000/hour
      block_duration: 3600

# Admin
admin:
  enabled: true
  basic_auth:
    username: admin
    password: ${ADMIN_PASSWORD}
```

### 10.2 Config Commands

```bash
./pds config show              # Show current config
./pds config show --secrets    # Include secrets
./pds config validate          # Validate config file
./pds config generate          # Generate template config
./pds config update key value  # Update config via CLI
```

---

## 11. Implementation Priority

### Phase 1: Essential (MVP)
1. CLI: `serve`, `health`
2. Basic health check endpoint
3. Structured logging
4. Account management CLI
5. Invite code CLI

### Phase 2: Important
1. Blob management CLI
2. Repository management CLI
3. Database utilities
4. Admin UI routes
5. Metrics endpoint

### Phase 3: Useful
1. Recovery tools
2. Debug endpoints
3. Load testing utilities
4. Advanced admin UI features
5. Tracing

### Phase 4: Polish
1. Web-based admin dashboard
2. Comprehensive monitoring
3. Automated recovery
4. Performance profiling
5. Full documentation

---

## 12. File Structure

```
ATProtoPDS/
├── Tools/
│   ├── pds-cli/                    # CLI tool
│   │   ├── main.m
│   │   ├── Commands/
│   │   │   ├── PDSCLICommand.h/m
│   │   │   ├── PDSCLIServe.h/m
│   │   │   ├── PDSCLIAccount.h/m
│   │   │   ├── PDSCLIInvite.h/m
│   │   │   ├── PDSCLIBlob.h/m
│   │   │   ├── PDSCLIRepo.h/m
│   │   │   ├── PDSCLIDatabase.h/m
│   │   │   ├── PDSCLIKey.h/m
│   │   │   ├── PDSCLIDebug.h/m
│   │   │   └── PDSCLIEmergency.h/m
│   │   └── Utilities/
│   │       ├── PDSConfigLoader.h/m
│   │       ├── PDSHealthChecker.h/m
│   │       └── PDSMetrics.h/m
│   │
│   └── admin-web/                  # Admin web UI
│       ├── AdminServer.h/m
│       ├── AdminRoutes.h/m
│       ├── AdminAuth.h/m
│       ├── AdminUsersHandler.h/m
│       ├── AdminBlobsHandler.h/m
│       ├── AdminReposHandler.h/m
│       ├── AdminInvitesHandler.h/m
│       ├── AdminSettingsHandler.h/m
│       └── AdminLogsHandler.h/m
│
├── Debug/
│   ├── PDSDebugServer.h/m          # Debug HTTP server
│   ├── PDSDebugHandlers.h/m
│   │   ├── PDSLogHandler.h/m
│   │   ├── PDSStateHandler.h/m
│   │   ├── PDSProfileHandler.h/m
│   │   └── PDSHeapHandler.h/m
│   ├── PDSLogger.h/m               # Structured logger
│   ├── PDSProfiler.h/m
│   ├── PDSRequestTracer.h/m
│   └── PDSRequestLogger.h/m
│
├── Admin/
│   ├── PDSAdminAuth.h/m            # Admin authentication
│   ├── PDSAdminService.h/m         # Admin service layer
│   └── PDSAdminModels.h/m          # Admin data models
│
└── Metrics/
    ├── PDSMetrics.h/m              # Metrics collector
    ├── PDSPrometheusExporter.h/m   # Prometheus format
    ├── PDSMetricsServer.h/m        # Metrics HTTP server
    └── PDSMetricsHandlers.h/m
```

---

## 13. References

- Pegasus OCaml PDS: https://tangled.org/futur.blue/pegasus
- atproto specifications: https://atproto.com/specs
- Prometheus metrics format: https://prometheus.io/docs/instrumenting/exposition_formats/
