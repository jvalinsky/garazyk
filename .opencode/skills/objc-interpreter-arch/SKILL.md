name: objc-interpreter-arch
description: Navigate the WASM-based Objective-C interpreter architecture: two-phase parse-eval pipeline, string pool markers, FDObj: dispatch, lexer line tracking, and common bug patterns. Use when debugging interpreter failures, adding language features, or understanding message routing.

# Objective-C Interpreter Architecture

The interpreter runs inside WASM, embedded in a Jupyter kernel. It interprets Objective-C source cells with a **two-phase pipeline** (parse to AST, then evaluate) and uses **string pool markers** for Foundation objects instead of real runtime allocation.

## File Organization

| File | Responsibility |
|---|---|
| `objc_interp_types.h` | Core types: `Value`, `Token`, `Lexer`, `Parser`, `InterpVar`, `InterpContext` (g_ctx) |
| `objc_interp_context.h` | Global context struct definition (singletons, state arena) |
| `objc_interp_lexer.c/h` | Tokenization: identifiers, keywords, literals, operators, comments |
| `objc_interp_parser.c/h` | Expression grammar, `parse_statement`, `parse_type_and_var_decl` |
| `objc_interp_ast.c/h` | AST construction (`parse_block_ast`, `parse_statement_ast`) and evaluation (`eval_ast`, `eval_source_range`) |
| `objc_interp_primary.c/h` | Primary expressions: literals, @-literals, blocks, `parse_primary` |
| `objc_interp_messages.c/h` | Message send parsing and dispatch: `parse_message_send` |
| `objc_interp_dispatch.c/h` | Method execution, NSLog evaluation |
| `objc_interp_class.c/h` | `@interface`/`@implementation` parsing, class registration |
| `objc_interp_format.c/h` | `format_value` for REPL display, string pool formatting |
| `objc_interp_state.c/h` | Variable table, property table, instance var get/set |
| `objc_interpreter.c` | Entry point: `objc_interp()`, `parser_error()`, `set_error_from_parser()` |
| `objc_runtime_bridge.c` | WASM transport: JSON request/response, host imports (`objc_kernel_host`) |

## Execution Pipeline

```
objc_kernel_execute_json (bridge)
  → objc_interp(code, length)
    → parser_init(&p, source, length, line_offset=0)
    → parse_block_ast(&p)          // Phase 1: Parse
      → parse_statement_ast(&p)
        → returns AST_NODEs with source_range {start, len}
    → if (p.error) → set_error + return
    → eval_ast(root, source)       // Phase 2: Evaluate
      → AST_BLOCK: loop children
        → eval_source_range(start, len, source, line_offset)
          → parser_init(&p, source+start, len, line_offset)
          → parse_statement(&p)
      → format_value(last, result_buffer)
```

**Critical**: Phase 2 re-parses source ranges with `line_offset` for error reporting. Each range creates a new `Parser` on a substring. The `line_offset` = count of newlines before the range in the full source.

## String Pool Markers

Foundation objects are encoded as NUL-terminated strings in the string pool:

| Marker | Encoding | Created by |
|---|---|---|
| `FDObj:ClassName` | Custom ObjC objects | `@interface`/`@implementation` |
| `NSNumber:<int>` | e.g. `"NSNumber:42"` | `@42`, `@(expr)`, `numberWithInt:` |
| `NSFloat:<float>` | e.g. `"NSFloat:3.14"` | `@3.14`, `numberWithFloat:` |
| `NSData:<hex>` | e.g. `"NSData:DEADBEEF"` | `NSData` data creation |
| `"plain C string"` | No prefix | NSString string_pool pointers |

**Rules**:
- Check markers with `cstr_starts()` or `cstr_eq_n()`, NOT `object_getClass` (crashes on non-ObjC pointers)
- `format_value()` must strip markers before display (strip prefix, show value)
- Trailing zeros in NSFloat markers must be trimmed at creation time

## Message Dispatch Flow (`parse_message_send`)

```
1. find_interpreter_method() → user-defined methods in g_ctx.methods
2. Foundation dispatch → hardcoded handlers for NSString, NSArray, NSNumber, etc.
3. Synthesized property dispatch → setXxx: / xxx patterns against g_ctx.properties
4. Error → "does not respond to selector"
```

Foundation dispatch uses `IS_FOUNDATION_CLASS("ClassName")` macro to match. Non-Foundation `FDObj:` receivers skip Foundation handlers entirely.

## Error Handling

### `parser_error(Parser *p, const char *msg)`
- Sets `p->error = OBJC_INTERP_SYNTAX_ERROR`
- **Saves** `p->error_line = p->lex.line + p->lex.lex_line_offset`
- **Saves** `p->error_column = p->lex.column`
- Formats `"line N, column M: <msg>"` into `p->error_msg`
- **Call BEFORE any `parser_advance()`** that would consume the erroring token

### `set_error_from_parser(Parser *p)`
- Copies `p->error_msg` to `g_ctx.error_buffer`
- Uses `p->error_line` / `p->error_column` (already-saved values)
- **Never** reads `p->lex.line` directly (lexer may have advanced)

### AST_BLOCK Error Check
The `AST_BLOCK` eval loop **must** check `g_ctx.error_code != OBJC_INTERP_OK` after each child and return early, otherwise subsequent children can mask the original error.

## Lexer Line Tracking

The lexer tracks `line` and `column` as it consumes characters. Newlines increment `line`. When `lexer_next_token()` skips whitespace (including `\n`), the line counter advances.

**Common trap**: If `parser_advance()` is called before `parser_error()`, the lexer has already consumed the erroring token and possibly a newline, so `p->lex.line` is wrong. The saved `p->error_line` field prevents this.

**Substring parsing**: `eval_source_range` creates a parser on `source[start..start+len)` with `line_offset = count_newlines(source, start)`. Errors in substrings report `error_line = substring_line + line_offset`.

## Value Type System

```c
typedef struct {
    int is_int;       // NSInteger, NSUInteger, BOOL
    int int_val;
    int is_float;     // CGFloat, double
    double float_val;
    int is_id;        // Object pointer
    id obj_val;
    int is_class;     // Class object
    Class cls_val;
    int is_sel;       // Selector
    SEL sel_val;
} Value;
```

**Tagged integers**: Small integers may be stored directly in the pointer. Check with `is_int` before treating `obj_val` as a pointer.

## WASM Transport

- Host provides `objc_kernel_host.stream(kind, ptr, len)` and `objc_kernel_host.should_interrupt()`
- Kernel allocates with `objc_kernel_alloc(len)`, frees with `objc_kernel_free(ptr)`
- Request/response via `objc_kernel_execute_json(req_ptr, req_len, out_ptr_ptr, out_len_ptr)`
- Response format: JSON with `status`, `execution_count`, `data`, `ename`, `evalue`, `traceback`

## Common Bug Patterns

| Pattern | Symptom | Fix |
|---|---|---|
| `parser_advance()` before `parser_error()` | Wrong line in traceback | Call `parser_error()` first; use `p->error_line` |
| Missing `g_ctx.error_code` check in block eval | Subsequent statements overwrite error | Add early return after each child |
| `object_getClass()` on string pool ptr | WASM crash | Check `cstr_starts()` for markers first |
| NSFloat trailing zeros | `@3.14` displays as `3.140000` | Trim after decimal generation |
| `format_value()` missing marker | `@42` shows `<id: 0x...>` | Add `cstr_starts()` check for marker |
| `lex_line_offset` not propagated | Wrong line in nested eval | Pass `line_offset` through `eval_source_range` |
| Multi-keyword selector matching | `setObject:forKey:` false-matches property | Extract prop_name only up to first `:` |

## Adding a Language Feature

1. **Lexer**: Add token type to `TokenType` enum in `types.h`, add recognition in `lexer_next_token`
2. **Parser**: Add grammar rule in `objc_interp_parser.c` or `objc_interp_primary.c`
3. **AST**: If control flow, add `AstNodeType` and `parse_*_ast` / `eval_*` in `objc_interp_ast.c`
4. **Dispatch**: If message-send related, add handler in `parse_message_send`
5. **Format**: If new Value type, handle in `format_value`
6. **Test**: Add cell to `tests/kernel-smoke.mjs`
