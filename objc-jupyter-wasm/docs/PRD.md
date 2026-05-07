# Parser Fixes: Cross-Cell Class Persistence & Parsing Gaps

## Problem Statement
The Objective-C kernel's parser fails on valid C syntax that appears in notebook cells, preventing 10/85 cells from passing. Root cause: parser routing logic doesn't recognize storage qualifiers and type modifiers, sending them to expression parser instead of type/variable declaration parser.

## Goals
1. Fix `static` and `extern` keyword routing (6-7 cells blocked)
2. Fix `unsigned int`, `short int` multi-token type parsing (3-4 cells blocked)  
3. Fix `enumerateObjectsUsingBlock:` with `BOOL *stop` parameter (2-3 cells blocked)
4. Expand type recognition for Foundation and C99 types

## Success Criteria
- ✓ Smoke tests pass (60+ features)
- ✓ Notebook tests improve from 75/85 to 80+/85
- ✓ No regressions in existing functionality
- ✓ Parser handles common C99/Foundation declarations without error

## Current Status
- Fix 1 (static/extern): IMPLEMENTED & COMMITTED (b9875dee)
- Fix 2 (enum with BOOL *stop): PENDING investigation
- Fix 3 (multi-token types): PENDING implementation
- Fix 4 (smoke tests): PENDING verification

## Technical Context
- Parser entry: `parse_statement()` in objc_interp_parser.c (line 646+)
- Key function: `parse_type_and_var_decl()` handles type/var declarations
- Routing logic: `is_builtin_type`, `is_class_type`, `is_typedef`, `is_block_qualifier` flags
- New: `is_storage_qualifier` flag added for static/extern

## Blockers & Unknowns
- Smoke test failures may be pre-existing or test-harness related
- Multi-token type parsing requires significant refactoring
- Block parameter types (int *stop) may need special closure handling
