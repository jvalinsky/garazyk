# Sub-plan: 26 — AppView Ingest Load

## Problem
Scenario timed out after 120s. AppView ingestion pipeline cannot keep up with the write load.

## Investigation

### Expected behavior
AppView should process incoming records from the firehose at a rate that keeps the ingestion queue from growing unbounded.

### Root cause candidates
1. **Synchronous ingestion**: All records processed one at a time
2. **Missing batch processing**: Records are inserted individually instead of batched transactions
3. **Slow query path**: Each ingested record triggers expensive lookups
4. **Write lock contention**: Database write lock held too long
5. **Index build overhead**: No batch index creation

## Work

### 1. Profile current ingestion
- Check the AppView subscription handler in `Garazyk/Sources/AppView/`
- Measure per-record processing time
- Identify bottlenecks (DB writes, CBOR decoding, profile lookups)

### 2. Optimize bottlenecks
- **Batch DB writes**: Use INSERT statements with multiple value rows or WAL-mode transactions
- **Defer expensive lookups**: Queue profile enrichment asynchronously
- **Reduce lock scope**: Minimize time inside write transactions

### 3. Short-term fix (if optimization is complex)
- Increase the scenario timeout
- Reduce the write throughput in the scenario

## Files
- `Garazyk/Sources/AppView/` (subscription/ingestion code)
- `Garazyk/Sources/AppView/Services/` (indexing service methods)
- `Garazyk/Sources/Database/` (DB connection/WAL config)
- `scripts/scenarios/scenarios/26_appview_ingest_load.ts` (scenario)

## Verification
```bash
nix develop -c bash -c "cd scripts/scenarios && deno run -A e2e_runner.ts --scenario 26"
```
