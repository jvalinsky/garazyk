# Dashboard Report Validation

## Boundary

Report JSON files are external filesystem input. Parse and validate them before opening database transactions where practical.

## Schema

- Use Zod v3 from the dashboard package import map.
- Require:
  - `scenario`: string
  - `started_at`, `finished_at`, `duration_s`: finite nonnegative numbers
  - `steps`: array of objects with string `name`, `status`, `detail` and finite nonnegative `duration_ms`
  - `summary.passed`, `summary.failed`, `summary.skipped`, `summary.total`: nonnegative integers
  - `ok`: boolean
  - optional `artifacts` and `metadata`: records of unknown JSON-like values

## Invalid File Policy

- Invalid JSON or schema failures are skipped per file.
- Emit diagnostics that include the filename.
- Valid files in the same scan or run import should continue to import.
- Shared read helper should be used by both `importRunReports()` and `scanReports()`.
