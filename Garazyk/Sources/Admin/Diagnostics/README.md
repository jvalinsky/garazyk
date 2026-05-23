# System Diagnostics Dashboard

The System Diagnostics Dashboard provides comprehensive monitoring and management capabilities for
the AT Protocol PDS, covering three major areas: Sequencer Health, Blob Storage Audits, and Rate
Limit Management.

## Architecture Overview

### Component Structure

```
PDSSystemDiagnosticsHandler (Coordinator)
├── PDSSequencerHealthHandler
│   ├── PDSSequencerAnalyticsCollector (background collection)
│   └── API Endpoints: /stats, /history
├── PDSBlobAuditHandler
│   ├── PDSBlobAuditManager (job management)
│   ├── PDSBlobAuditOperation (base class)
│   ├── PDSBlobOrphanScanOperation
│   ├── PDSBlobCIDVerificationOperation
│   ├── PDSBlobConsistencyCheckOperation
│   └── PDSBlobReferenceScanOperation
└── PDSRateLimitAdminHandler
    └── API Endpoints: /query, /top, /clear
```

### Database Schema

Three new tables are created in `service.db`:

#### 1. sequencer_analytics

Stores time-series metrics collected every 60 seconds.

```sql
CREATE TABLE sequencer_analytics (
    id INTEGER PRIMARY KEY,
    timestamp INTEGER NOT NULL,           -- Unix timestamp
    seq_number INTEGER NOT NULL,          -- Current event sequence number
    events_per_second REAL,               -- Computed from seq delta
    subscriber_count INTEGER,             -- Active WebSocket connections
    backpressure_warnings INTEGER DEFAULT 0,
    backpressure_critical INTEGER DEFAULT 0,
    queue_overflows INTEGER DEFAULT 0,
    event_type_distribution TEXT,         -- JSON
    created_at INTEGER NOT NULL
);
CREATE INDEX idx_sequencer_analytics_timestamp ON sequencer_analytics(timestamp);
```

#### 2. blob_audit_jobs

Tracks background blob audit jobs with status and results.

```sql
CREATE TABLE blob_audit_jobs (
    id TEXT PRIMARY KEY,                  -- UUID
    job_type TEXT NOT NULL,               -- 'orphans', 'cid_verify', 'consistency', 'references'
    status TEXT NOT NULL,                 -- 'pending', 'running', 'completed', 'failed', 'cancelled'
    started_at INTEGER,
    completed_at INTEGER,
    progress REAL DEFAULT 0.0,            -- 0.0 to 100.0
    results TEXT,                         -- JSON with audit-specific results
    error TEXT,
    created_at INTEGER NOT NULL
);
CREATE INDEX idx_blob_audit_jobs_status ON blob_audit_jobs(status);
```

#### 3. rate_limit_history

Immutable audit trail for all rate limit admin actions.

```sql
CREATE TABLE rate_limit_history (
    id INTEGER PRIMARY KEY,
    identifier TEXT NOT NULL,             -- DID, IP, or blob hash
    type TEXT NOT NULL,                   -- 'did', 'ip', 'blob'
    action TEXT NOT NULL,                 -- 'cleared', 'rejected'
    admin_did TEXT,                       -- Admin who performed action
    reason TEXT,                          -- Admin-provided reason
    timestamp INTEGER NOT NULL
);
CREATE INDEX idx_rate_limit_history_identifier ON rate_limit_history(identifier);
CREATE INDEX idx_rate_limit_history_timestamp ON rate_limit_history(timestamp);
```

## Feature Documentation

### 1. Sequencer Health Monitoring

#### Purpose

Monitor real-time and historical performance of the event sequencer, including throughput,
subscriber count, and backpressure metrics.

#### Implementation

- **PDSSequencerAnalyticsCollector**: Runs a GCD dispatch timer that wakes every 60 seconds to
  collect metrics
- Metrics collected:
  - Current sequence number from ServiceDatabases
  - Events per second (computed from seq delta)
  - Active subscriber count from SubscribeReposHandler
  - Backpressure warnings/critical counts from GZMetrics
  - Queue overflow counts
- Data is persisted to `sequencer_analytics` table with 24+ month retention

#### API Endpoints

**GET /admin/api/diagnostics/sequencer/stats** Returns current real-time metrics snapshot.

Response:

```json
{
  "seq_number": 12345,
  "events_per_second": 125.5,
  "subscriber_count": 42,
  "backpressure_warnings": 2,
  "backpressure_critical": 0,
  "queue_overflows": 0,
  "timestamp": 1234567890
}
```

**GET /admin/api/diagnostics/sequencer/history?hours=24** Returns historical data for specified
period (default: 24 hours, max: 720 hours / 30 days).

Response:

```json
{
  "data": [
    {
      "timestamp": 1234567890,
      "seq_number": 12345,
      "events_per_second": 125.5,
      "subscriber_count": 42,
      "backpressure_warnings": 2,
      "backpressure_critical": 0,
      "queue_overflows": 0
    },
    ...
  ],
  "period_hours": 24
}
```

#### Frontend

- Real-time metrics cards showing current state
- Health indicator (green/yellow/red) based on backpressure
- Chart.js time-series charts for 24-hour window
- Auto-refresh every 30 seconds

#### Server Lifecycle Integration

- **Initialization**: Created in `PDSApplication.initializeServices()` after
  `_subscribeReposHandler`
- **Start**: Collection begins in `PDSApplication.startWithError:` after relay service starts
- **Stop**: Collection stops in `PDSApplication.stop:` with cleanup

### 2. Blob Storage Audits

#### Purpose

Perform deep integrity checks on blob storage to detect orphaned files, CID mismatches, missing
files, and unreferenced blobs. All operations support dry-run mode.

#### Audit Types

**orphans** - Find blobs in filesystem without database metadata

- Scans blob storage directory
- Queries blob_objects table for metadata
- Reports blobs that exist but have no DB record
- Can delete orphaned files in non-dry-run mode

**cid_verify** - Verify computed CIDs match stored values

- Recomputes SHA-256 hash for each blob
- Converts to IPFS CIDv1
- Compares against stored CID
- Reports mismatches

**consistency** - Find database records pointing to missing files

- Queries blob_objects table
- Checks filesystem for existence
- Reports DB entries with no corresponding file

**references** - Scan repos for unreferenced blobs

- Enumerates all records in all repos
- Extracts blob references
- Reports blobs with no incoming references

#### Implementation

**PDSBlobAuditManager**

- Manages job lifecycle with persistence
- NSOperationQueue with serial execution (maxConcurrentOperationCount = 1)
- Prevents resource exhaustion during I/O and hashing
- Supports job cancellation

**PDSBlobAuditOperation** (Base class)

- Progress tracking (0.0 to 100.0)
- Database persistence of job state
- Result serialization (JSON)
- Error capture and logging

**Operation Subclasses**

- Implement specific audit logic
- Report progress every 100 blobs
- Support cancellation via `NSOperation.cancel`
- Return structured results

#### API Endpoints

**POST /admin/api/diagnostics/blobs/audit** Start a new audit job.

Request:

```json
{
  "auditType": "orphans",
  "dryRun": true
}
```

Response:

```json
{
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "status": "pending",
  "auditType": "orphans",
  "dryRun": true
}
```

**GET `/admin/api/diagnostics/blobs/status?jobId=<uuid>`** Poll current job status.

Response:

```json
{
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "status": "running",
  "progress": 45.5,
  "job_type": "orphans",
  "startedAt": 1234567890,
  "results": null
}
```

When complete:

```json
{
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "status": "completed",
  "progress": 100.0,
  "job_type": "orphans",
  "startedAt": 1234567890,
  "completedAt": 1234567950,
  "results": {
    "orphaned_count": 42,
    "freed_bytes": 1048576
  }
}
```

#### Frontend

- Audit type selector (radio buttons)
- Dry-run toggle (default: enabled)
- Active jobs display with progress bars
- Results viewer with detailed findings
- Polling mechanism (2-second intervals)
- Job history table (recent 20 jobs)

#### Performance Notes

- Orphan scan on 10K blobs: ~5 minutes
- CID verification on 10K blobs: ~7 minutes (CPU intensive)
- Consistency check on 10K blobs: ~2 minutes
- Reference scan on 10K blobs: ~8 minutes
- All operations designed to be resumable and cancellable

### 3. Rate Limit Management

#### Purpose

Query current rate limit status, view top limited users, and perform admin overrides with immutable
audit trail.

#### Admin Capabilities

**Query Status** - Look up current quota for identifier

- Supports DID, IP address, and blob hash identifiers
- Returns limit, remaining, and reset time

**Top Limited Users** - Monitor users approaching limits

- Sorted by remaining quota (ascending)
- Shows limit, remaining, reset time per user

**Clear Rate Limit** - Admin override with audit trail

- Requires non-empty reason field
- Creates immutable audit trail entry
- Logs admin DID and timestamp
- Frontend enforces confirmation modal

**View History** - Inspect admin actions

- Sorted by timestamp (descending)
- Shows admin, reason, identifier, timestamp

#### Implementation

**PDSRateLimitAdminHandler**

- Wraps underlying RateLimiter with query methods
- Manages rate_limit_history table
- Validates input (non-empty identifiers, reasons)
- Provides history queries and pruning

#### API Endpoints

**POST /admin/api/diagnostics/ratelimits/query** Query rate limit status.

Request:

```json
{
  "identifier": "did:plc:xxx",
  "type": "did"
}
```

Response:

```json
{
  "identifier": "did:plc:xxx",
  "type": "did",
  "limit": 1000,
  "remaining": 842,
  "reset_at": 1234567890
}
```

**GET /admin/api/diagnostics/ratelimits/top?limit=20** Get top rate-limited identifiers.

Response:

```json
{
  "top_limited": [
    {
      "identifier": "did:plc:xxx",
      "type": "did",
      "limit": 1000,
      "remaining": 5,
      "reset_at": 1234567890
    },
    ...
  ]
}
```

**POST /admin/api/diagnostics/ratelimits/clear** Clear rate limit with admin override.

Request:

```json
{
  "identifier": "did:plc:xxx",
  "type": "did",
  "reason": "User complained, appears to be legitimate spike"
}
```

Response:

```json
{
  "cleared": true,
  "identifier": "did:plc:xxx",
  "type": "did",
  "timestamp": 1234567890
}
```

#### Frontend

- Query form (identifier input + type selector)
- Results card with quota bar
- Top limited users table with sorting
- Clear button with mandatory reason field
- Confirmation modal before clear

#### Safety Features

- Every clear creates immutable audit trail entry
- Admin DID and reason logged for all clears
- Reason field mandatory (non-empty validation)
- Frontend confirmation modal prevents accidental clears
- All actions timestamped and queryable

## Testing

Comprehensive integration tests are provided:

- **PDSSequencerAnalyticsTests.m** (14 tests)
  - Collection start/stop
  - Metrics persistence
  - Current snapshot retrieval
  - Historical data queries
  - Pruning old records
  - Concurrent access

- **PDSBlobAuditManagerTests.m** (13 tests)
  - Job creation with UUID
  - Different audit types
  - Dry-run mode
  - Job status retrieval
  - Cancellation
  - Recent jobs queries
  - Job pruning
  - Queue serialization

- **PDSRateLimitAdminHandlerTests.m** (15 tests)
  - Rate limit queries
  - Top limited users
  - Clear with audit trail
  - History tracking
  - Input validation
  - Concurrent clears
  - History pruning

Run tests with:

```bash
xcodebuild test -scheme Garazyk -testPlan DiagnosticsTests
```

## Monitoring and Observability

### Logging

All operations log at INFO or WARN level:

- Analytics collection start/stop
- Job creation/completion
- Admin actions (clear, queries)
- Errors with context

### Metrics

Consider adding Prometheus metrics for:

- Analytics collection lag
- Active audit jobs
- Audit job completion rates
- Rate limit clears per hour
- Top cleared identifiers

### Retention Policies

- **sequencer_analytics**: 90 days (auto-pruned)
- **blob_audit_jobs**: 90 days (auto-pruned)
- **rate_limit_history**: 30 days (auto-pruned)

## Configuration

### Collection Intervals

- Sequencer analytics: 60 seconds (edit PDSSequencerAnalyticsCollector.m)
- Audit job polling (frontend): 2 seconds

### Limits

- Top limited users: Default 20, max 100
- Recent jobs: Default 10, max 50
- Historical data window: Default 24 hours, max 30 days

## API Base Paths

All diagnostics endpoints are prefixed with `/admin/api/diagnostics/`:

| Feature     | Path                 | Method | Purpose         |
| ----------- | -------------------- | ------ | --------------- |
| Sequencer   | `/sequencer/stats`   | GET    | Current metrics |
| Sequencer   | `/sequencer/history` | GET    | Historical data |
| Blobs       | `/blobs/audit`       | POST   | Start audit job |
| Blobs       | `/blobs/status`      | GET    | Poll job status |
| Rate Limits | `/ratelimits/query`  | POST   | Query limit     |
| Rate Limits | `/ratelimits/top`    | GET    | Top limited     |
| Rate Limits | `/ratelimits/clear`  | POST   | Admin clear     |

## Security Considerations

1. **Admin Authentication**: All endpoints require admin authentication via AdminMiddleware
2. **Audit Trail**: Every admin action (rate limit clears) is logged immutably
3. **Dry-Run Safety**: Blob audits default to dry-run mode
4. **Validation**: All input validated (empty checks, type checks)
5. **Permissions**: Only authenticated admins can access diagnostics
6. **Rate Limit Overrides**: Each clear requires explicit reason field

## Future Enhancements

1. **Export Functionality**: Export analytics data to CSV/JSON
2. **Alerting**: Thresholds and notifications for backpressure
3. **Aggregation**: Per-user/per-type analytics aggregation
4. **Comparison**: Compare metrics across time periods
5. **Repair Tools**: Auto-fix capabilities for blob consistency issues
6. **WebSocket Push**: Real-time metrics push instead of polling
7. **Grafana Integration**: Prometheus metrics for visualization
8. **Batch Operations**: Clear multiple rate limits simultaneously

## Troubleshooting

### Analytics Collection Not Starting

- Verify PDSApplication.startWithError: is calling [_analyticsCollector startCollecting]
- Check server logs for "Sequencer analytics collector started"
- Verify _analyticsCollector is not nil

### Blob Audits Not Running

- Verify PDSBlobAuditManager is initialized correctly
- Check that NSOperationQueue has maxConcurrentOperationCount = 1
- Review server logs for operation execution
- Verify database permissions for audit_jobs table

### Rate Limit Clears Not Logging

- Verify rate_limit_history table exists and has correct schema
- Check that admin_did is being passed correctly
- Verify reason field is non-empty
- Check database integrity

## References

- Database Schema: See PDSSchemaManager.h
- Migration: See PDSMigrationManager.m (V3DiagnosticsSchema)
- API Routing: See AdminUIHandler.m (handlePartialPath:)
- Frontend: See admin-diagnostics.js
