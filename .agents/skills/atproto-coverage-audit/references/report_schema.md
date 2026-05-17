# JSON Report Schema

The coverage helpers emit small JSON structures suitable for comparison and follow-up reports.

## Match Entry

Used for `rg`-style scans:

```json
{
  "file": "path/to/file.ts",
  "line": 123,
  "match": "line contents"
}
```

## Method Entry

Used for lexicon and method listings:

```json
{
  "method_id": "com.atproto.server.describeServer",
  "type": "query",
  "location": "lexicons/com/atproto/server/describeServer.json"
}
```

## Script Outputs

- `find_stubs.sh --json`: object with `not_implemented`, `todo_fixme`, and `stub_markers` arrays.
- `run_all.sh`: writes `xrpc_coverage.json`, `xrpc_coverage.md`, `xrpc_next_steps_plan.md`, and `xrpc_issue_candidates.md` when repo-native coverage scripts are available.
- `parse_lexicons.py --json`: array of method entries from lexicon JSON.
- `diff_methods.py --json`: object with `missing_in_code`, `missing_in_lexicons`, and `summary`.
