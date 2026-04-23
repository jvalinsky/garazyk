# JSON Report Schema (Shared)

This document describes the common JSON shapes emitted by these skills.

## Common entry shapes

### Match entry
Used for `rg`-style scans.
```
{
  "file": "path/to/file.m",
  "line": 123,
  "match": "line contents..."
}
```

### Location entry
Used for method or event listings.
```
{
  "method_id": "com.atproto.server.describeServer",
  "symbol": "ComAtprotoServerDescribeServer",
  "location": "/path/XrpcMethodRegistry.m:113"
}
```

### File result entry
Used for checks that return stub lines or claim sets.
```
{
  "file": "/path/file.m",
  "stub_lines": [1983]
}
```

## Script outputs

- `find_stubs.sh --json`: object with keys `not_implemented`, `todo_fixme`, `stub_markers` (arrays of match entries).
- `map_endpoints.py --json`: array of location entries (`method_id`, `symbol`, `location`).
- `list_xrpc_methods.py --json`: array of location entries.
- `parse_lexicons.py --json`: array entries with `method_id`, `type`, `location`.
- `diff_methods.py --json`: object with `missing_in_code`, `missing_in_lexicons`, and `summary`.
- `scan_mst_invariants.sh --json`: object with `fan_out`, `prefix`, `cbor_ordering`, `cidv1_base58` (match entry arrays).
- `check_cidv1_paths.py --json`: array of file result entries (`file`, `stub_lines`).
- `scan_platform_apis.sh --json`: object with `os_log`, `security`, `common_crypto`, `nsurlsession` (match entry arrays).
- `report_missing_guards.py --json`: object with `missing_guards` (file path array).
- `scan_auth_hotspots.sh --json`: object with `auth_hotspots` (match entry array).
- `jwt_claims_check.py --json`: array of file result entries with `found` and `missing` claim lists.
- `scan_firehose_events.py --json`: array with `event_type`, `kind`, `location`.
- `check_backpressure.sh --json`: object with `backpressure_markers` (match entry array).
