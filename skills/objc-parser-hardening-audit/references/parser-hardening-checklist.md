# Parser Hardening Checklist

Use this checklist while validating candidates from `scan_parser_hardening.sh`.

## Bounds and offsets
- Verify each offset/range is validated before use.
- Verify length arithmetic cannot wrap or underflow.
- Verify all reads guard against truncated input.

## Integer safety
- Verify conversions between signed/unsigned widths are explicit.
- Verify multiplication/addition for buffer sizing is overflow-safe.
- Verify parser rejects impossible lengths early.

## Memory operations
- Verify `memcpy`/`getBytes` use validated source and destination lengths.
- Verify no implicit trust of external length prefixes.
- Verify partial parse failure cannot leave stale mutable state.

## Testing and fuzzing
- Add unit tests for malformed edge cases and boundary values.
- Add fuzz corpus inputs for nested/oversized/truncated payloads.
- Ensure parser fails closed with deterministic errors.
