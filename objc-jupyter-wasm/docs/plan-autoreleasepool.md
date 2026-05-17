# @autoreleasepool Implementation Plan

## Context

The wasm kernel is a **custom ObjC interpreter** that parses source into AST and evaluates it. It
uses string-pool markers (`FDObj:...`) to represent objects, not real ObjC runtime objects. There is
no real reference counting — `retain`/`release`/`autorelease` are currently unimplemented.

Real `@autoreleasepool` semantics:

1. Pushes a new autorelease pool onto a per-thread stack
2. All `[obj autorelease]` calls add obj to the **current** pool
3. On scope exit, the pool is **drained** — sends `release` to all objects, then pops

For the interpreter: we implement the **structural/scaffolding** correctly; the actual
retain/release cycle is a no-op (objects are just string-pool markers).

---

## Phase 1: Data Structures

### 1.1 Add token type to `objc_interp_types.h`

**File:** `kernel/objc_interp_types.h`

Add to `TokenType` enum (after `TOK_SUPER`):

```c
TOK_AUTORELEASEPOOL,  /* @autoreleasepool keyword */
```

### 1.2 Add pool stack to `InterpContext`

**File:** `kernel/objc_interp_context.h`

Add to `InterpContext` struct (after the try-catch state, before string pool):

```c
/* ── Autorelease pool stack ─────────────────────────── */
#define MAX_AUTORELEASE_POOL_DEPTH 16
#define MAX_AUTORELEASE_OBJECTS 256

typedef struct {
    unsigned int object_markers[MAX_AUTORELEASE_OBJECTS];
    unsigned int count;
} AutoreleasePool;

AutoreleasePool pools[MAX_AUTORELEASE_POOL_DEPTH];
unsigned int pool_depth;
```

Also add `MAX_AUTORELEASE_POOL_DEPTH` and `MAX_AUTORELEASE_OBJECTS` as `#define` constants near the
top of `objc_interp_types.h` (alongside other MAX_* constants).

### 1.3 Add AST node type

**File:** `kernel/objc_interp_types.h`

Add `AST_AUTORELEASEPOOL` to `AstNodeType` enum (after `AST_THROW`):

```c
AST_AUTORELEASEPOOL  /* @autoreleasepool { ... } */
```

Add union member to `AstNode` struct:

```c
struct { /* AST_AUTORELEASEPOOL */
    AstNode *body;
} autoreleasepool;
```

---

## Phase 2: Lexer — Recognize `@autoreleasepool`

**File:** `kernel/objc_interp_lexer.c`

In `lexer_next_token()`, there is already a block handling `@` keywords (look for `TOK_AT_KEYWORD`
handling). Extend it:

Find the section that checks `@` followed by identifier. After existing checks for `@try`, `@catch`,
`@finally`, `@throw`, `@interface`, etc., add:

```c
if (cstr_eq(word, "autoreleasepool")) {
    token->type = TOK_AUTORELEASEPOOL;
    return;
}
```

The existing `@`-keyword handling likely builds a string `word` from the identifier after `@`, then
switches on it. Follow the exact same pattern.

---

## Phase 3: Parser — Parse `@autoreleasepool { ... }`

**File:** `kernel/objc_interp_ast.c`

### 3.1 Add AST constructor

Add after the `ast_make_try_catch()` function:

```c
AstNode *ast_make_autoreleasepool(void) {
    AstNode *n = ast_alloc();
    if (!n) return n;
    n->type = AST_AUTORELEASEPOOL;
    n->autoreleasepool.body = 0;
    return n;
}
```

### 3.2 Parse in `parse_statement_ast()`

In `parse_statement_ast()`, add a new branch for `TOK_AUTORELEASEPOOL`. Follow the pattern used for
`TOK_AT_KEYWORD` / `@try`:

```c
/* @autoreleasepool { ... } */
if (tok.type == TOK_AT_KEYWORD && cstr_eq(tok.text, "@autoreleasepool")) {
    AstNode *node = ast_make_autoreleasepool();
    if (!node) return 0;
    parser_advance(p); /* consume '@autoreleasepool' */

    /* Expect '{' */
    if (parser_current(p).type != TOK_OPEN_BRACE) {
        parser_error(p, "Expected '{' after @autoreleasepool");
        return 0;
    }
    parser_advance(p); /* consume '{' */

    /* Parse body block */
    node->autoreleasepool.body = parse_block_ast(p);
    if (!node->autoreleasepool.body) return 0;

    /* Expect '}' */
    if (parser_current(p).type != TOK_CLOSE_BRACE) {
        parser_error(p, "Expected '}' after @autoreleasepool body");
        return 0;
    }
    parser_advance(p); /* consume '}' */
    return node;
}
```

Place this in the same `if/else if` chain as `@try`, `@throw`, etc.

---

## Phase 4: Evaluator — Push/Pop Pools, Drain

**File:** `kernel/objc_interp_ast.c`

### 4.1 Add case in `eval_ast()`

In the `switch (node->type)` in `eval_ast()`, add after the `AST_THROW` case:

```c
case AST_AUTORELEASEPOOL: {
    /* Push a new autorelease pool */
    if (g_ctx.pool_depth >= MAX_AUTORELEASE_POOL_DEPTH) {
        g_ctx.error_code = OBJC_INTERP_RESOURCE_ERROR;
        cstr_copy(g_ctx.error_buffer,
                  "@autoreleasepool nesting too deep (max 16)",
                  OBJC_INTERP_ERROR_SIZE);
        break;
    }
    AutoreleasePool *pool = &g_ctx.pools[g_ctx.pool_depth++];
    pool->count = 0;

    /* Execute body */
    eval_ast(node->autoreleasepool.body, source);

    /* Drain: pop pool (objects "released" — no-op in interpreter) */
    g_ctx.pool_depth--;
    break;
}
```

### 4.2 Initialize pool_depth in `objc_interp_init()`

**File:** `kernel/objc_interpreter.c`

In `objc_interp_init()`, after the try-catch init, add:

```c
g_ctx.pool_depth = 0;
```

---

## Phase 5: Handle `[obj autorelease]` Messages

**File:** `kernel/objc_interp_messages.c`

In the message dispatch (the big function that handles `[target selector:args]`), add handling for
the `autorelease` selector. Find where `retain`, `release`, `description`, etc. are handled (search
for `"retain"` or `"description"` in the file).

Add a case for `autorelease`:

```c
/* Handle 'autorelease' — add to current autorelease pool */
if (cstr_eq(sel_name, "autorelease")) {
    /* Add receiver to current pool if one is active */
    if (g_ctx.pool_depth > 0) {
        AutoreleasePool *pool = &g_ctx.pools[g_ctx.pool_depth - 1];
        if (pool->count < MAX_AUTORELEASE_OBJECTS) {
            /* Store the object marker (receiver pointer as offset into string pool) */
            pool->object_markers[pool->count++] = (unsigned int)(uintptr_t)receiver;
        }
    }
    return value_from_id(receiver);  /* returns self, like real autorelease */
}
```

Place this near other no-op message handlers (like `retain`, `release` if they exist, or near
`description`).

---

## Phase 6: Update Interpreter Header

**File:** `kernel/objc_interpreter.h`

Add to the "It does NOT support" list, remove or update:

```
*   - @autoreleasepool (scaffolding only; retain/release are no-ops)
```

Change to indicate it IS supported (with caveat):

```
*   - @autoreleasepool (structural support; no real retain/release)
```

---

## Phase 7: Tests

**Files:** `tests/` (Node harness)

Add test cases in a new test file or extend existing:

```javascript
// Test 1: Basic @autoreleasepool parses and runs without error
const result1 = await executeInWasm(`
@autoreleasepool {
    id s = @"hello";
}
`);
assert(result1.status === "ok");

// Test 2: Nested @autoreleasepool
const result2 = await executeInWasm(`
@autoreleasepool {
    @autoreleasepool {
        id s = @"nested";
    }
}
`);
assert(result2.status === "ok");

// Test 3: autorelease message adds to pool (no crash)
const result3 = await executeInWasm(`
@autoreleasepool {
    id s = @"test";
    [s autorelease];
}
`);
assert(result3.status === "ok");
```

---

## Phase 8: Update `objc_kernel_info_json` Response

**File:** `kernel/objc_runtime_bridge.c`

In the kernel info JSON (the response from `objc_kernel_info_json`), the `language_info` blob may
list supported features. Add `"@autoreleasepool"` to the supported features list if there is one, or
add a `features` field:

```c
builder_append(builder, "\"features\":[\"@interface\",\"@implementation\",\"@property\",\"@autoreleasepool\",\"@try\",\"blocks\",\"for-in\"]");
```

---

## Summary of Files to Modify

| File                            | Change                                                                        |
| ------------------------------- | ----------------------------------------------------------------------------- |
| `kernel/objc_interp_types.h`    | Add `TOK_AUTORELEASEPOOL`, `AST_AUTORELEASEPOOL`, pool structs, max constants |
| `kernel/objc_interp_context.h`  | Add `pools[]`, `pool_depth` to `InterpContext`                                |
| `kernel/objc_interp_lexer.c`    | Recognize `@autoreleasepool` keyword                                          |
| `kernel/objc_interp_ast.c`      | `ast_make_autoreleasepool()`, parse + eval cases                              |
| `kernel/objc_interp_messages.c` | Handle `autorelease` selector                                                 |
| `kernel/objc_interpreter.c`     | Initialize `pool_depth = 0` in `objc_interp_init()`                           |
| `kernel/objc_interpreter.h`     | Update "NOT support" comments                                                 |
| `kernel/objc_runtime_bridge.c`  | (Optional) Add to kernel info features                                        |

---

## Verification Checklist

- [ ] `@autoreleasepool { ... }` parses without syntax error
- [ ] Nested pools work (push/pop correctly)
- [ ] `[obj autorelease]` doesn't crash; object added to pool
- [ ] Pool drain on scope exit doesn't crash (pool popped)
- [ ] `[obj retain]` and `[obj release]` are also no-ops (verify they don't error)
- [ ] Existing tests still pass (no regressions)
- [ ] `objc_interp_full_reset()` resets `pool_depth = 0`
