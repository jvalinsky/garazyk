# Runtime Expansion Phase F: __block & Fast Enumeration

## Goal

Implement the `__block` storage qualifier for variable capture in blocks and extend `for-in` to
support the `NSFastEnumeration` protocol.

## Design Choices

1. **`__block` Capture**:
   - Update the lexer to recognize `__block`.
   - Update `InterpVar` to include an `is_block_captured` flag (already exists, but check usage).
   - When capturing a `__block` variable, store a reference (index) to the global `g_ctx.vars` entry
     instead of a copy of the value.
   - Note: Since we don't have a heap-moving GC for interpreter variables yet, `__block` variables
     will still live in the `vars` table. We must ensure they aren't overwritten if the scope
     returns. _Correction_: The interpreter's `vars` table is currently a flat array with a
     `var_scope_base`. Variables are "popped" by decrementing `var_count`. This is problematic for
     `__block` if the block escapes. For now, we will support `__block` for same-scope or
     nested-scope modifications.

2. **Fast Enumeration**:
   - If a `for-in` collection is not a recognized internal marker (like `NSArr:`), attempt to call
     `countByEnumeratingWithState:objects:count:`.
   - Implement a simplified version of the fast enumeration protocol loop in the AST evaluator.
   - Provide a built-in implementation of this method for `NSArray`, `NSDictionary`, and `NSSet`
     markers to unify the code path.

## Task List

- [x] Update `objc_interp_lexer.c` to recognize `__block`.
- [x] Update `parse_statement` and variable declaration parsing to handle `__block`.
- [x] Modify `AST_BLOCK_LITERAL` evaluation to capture `__block` variables by reference.
- [x] Update `execute_block` to read/write to the referenced `InterpVar`.
- [x] Define `NSFastEnumerationState` marker or struct.
- [x] Refactor `AST_FOR_IN` in `objc_interp_ast.c` to use a protocol-based loop.
- [x] Add tests for `__block` modification and custom class enumeration.
