# Plan: System Diagnostics Dashboard

## Objective
Provide a robust suite of diagnostic tools for PDS operators to monitor internal service health, data consistency, and system-level performance.

## Backend Enhancements
### PDSMetrics
- Add `sequencerLagSeconds` to track the time between event commit and firehose emission.
- Add `rateLimitUsageForDid:(NSString *)did` to expose internal quota states.

### PDSBlobService
- Implement a `- (void)triggerIntegrityAuditWithCompletion:(void (^)(NSDictionary *report))completion;` that scans the `blob` directory and confirms each file matches its CID metadata in the database.

## Frontend Implementation
### Sidebar & Navigation
- Add a "Diagnostics" item under the "PDS" sidebar section.
- Split into tabs: "Sequencer", "Blob Audit", "Rate Limits".

### Partial Templates
- `diag_sequencer.html`: Visualization of the event pipeline.
- `diag_blob_audit.html`: Status of the last integrity check and a "Start New Audit" button.
- `diag_rate_limits.html`: A search tool to see the current remaining quota for a DID or IP address.

### UI Controls
- **Trigger Audit**: Start a background consistency check.
- **Reset Rate Limit**: Clear the consumption bucket for a specific user if they are being unfairly throttled.

## Implementation Steps
1. Enhance `PDSMetrics.m` with lag tracking.
2. Add diagnostic endpoints to `PDSAdminHandler.m`.
3. Implement `AdminDiagnostics` JS helper for real-time lag polling.
4. Design high-density monitoring templates.
