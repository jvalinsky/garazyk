# Issue: static/extern keyword routing

## Description

`parse_statement()` doesn't recognize `static` and `extern` keywords, sending them to expression
parser instead of type/variable declaration parser. Results in "Unknown identifier" errors.

## Example Failing Code

```c
static Calculator *sharedCalc = 0;
static int counter = 0;
```

## Status: ✅ COMPLETED

Completed on 2026-05-04.

## Solution Implemented

- Added `is_storage_qualifier` flag in `parse_statement()` (lines 674-677)
- Routes static/extern to `parse_type_and_var_decl()` directly
- `parse_type_and_var_decl()` already had logic to handle static (line 350-352)

## Commit

- b9875dee: Parser: Add storage qualifier routing for static/extern declarations

## Files Changed

- objc_interp_parser.c (lines 671-726)
  - Added is_storage_qualifier flag
  - Extended routing condition
  - Added direct routing for storage qualifiers

## Testing

- Kernel builds successfully (220KB WASM)
- Fixes cells [3] and [4] in objc-state-and-blocks.ipynb
- Unblocks ~6-7 cells across notebooks

## Notes

- unsigned/short omitted (require multi-token type parsing)
- Also expanded is_builtin_type to include Foundation and C99 types
