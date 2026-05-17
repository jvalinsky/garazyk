# Issue: Multi-token type parsing (unsigned int, short int)

## Description

Parser doesn't handle multi-token C types like `unsigned int`, `short long`, etc. Requires reading
two tokens as the type name instead of one.

## Example Failing Code

```c
unsigned int x = 0;
short int y = 10;
unsigned long z = 100;
```

## Status: PENDING

To be addressed in separate implementation phase.

## Root Cause

`parse_type_and_var_decl()` reads one identifier as the type name (line 357-359). When it encounters
"unsigned", it stores that as the type name, then expects the next token to be a variable name. But
the next token is "int", causing a parse failure.

## Solution Approach

Modify `parse_type_and_var_decl()` to:

1. Check if type_name is "unsigned" or "short"
2. If so, read the next token as a modifier
3. Combine into full type name (e.g., "unsigned int")

Alternatively: Add special routing for unsigned/short in `parse_statement()` to handle them
similarly to other type modifiers.

## Estimated Impact

- Fixes 3-4 failing cells across notebooks
- Enables common C99 pattern declarations

## Blocked By

- None; can be implemented independently

## Related Issues

- #01-static-storage-qualifier.md (same file, adjacent logic)
