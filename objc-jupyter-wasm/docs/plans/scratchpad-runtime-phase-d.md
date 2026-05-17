# Runtime Expansion Phase D: Exceptions & Protocols

## Goal

Implement Objective-C exception handling (`@try`/`@catch`/`@finally`/`@throw`) and runtime protocol
conformance checking.

## Design Choices

1. **Try-Catch Stack**: Use a stack of `TryFrame` objects in the interpreter context. Each frame
   will record the current catch/finally targets and the exception state.
2. **Exception Propagation**: Since we are using an AST evaluator, we can check for a "pending
   exception" flag in the global context after each statement evaluation. If set, we unwind the
   evaluation stack until we find a matching `@catch` or `@finally` block.
3. **Protocol Enforcement**: Store protocol declarations and class conformance in the side table.
   Implement `conformsToProtocol:` in the message dispatch layer to query these tables.
4. **No-op `retain`/`release` in Protocols**: Methods like `retain` and `release` in protocols will
   be recognized but treated as no-ops to maintain compatibility with standard Foundation protocols.

## Task List

- [x] Define `TryFrame` and `MAX_TRY_DEPTH` in `kernel/objc_interp_types.h`.
- [x] Add `exception_stack` and `exception_depth` to `InterpContext`.
- [x] Implement `AST_TRY_CATCH` and `AST_THROW` in `objc_interp_ast.c`.
- [x] Update `eval_ast` to handle exception unwinding.
- [x] Implement `@protocol` parsing in `objc_interp_class.c`.
- [x] Update `objc_interp_messages.c` to support `conformsToProtocol:`.
- [x] Add tests for nested `@try`/`@catch` and protocol conformance.
