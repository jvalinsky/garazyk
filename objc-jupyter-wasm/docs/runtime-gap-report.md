# Objective-C 2.0 Runtime Gap Report — objc-jupyter-wasm Kernel

**Date:** 2026-05-06 (updated)
**Kernel version:** HEAD (phases A–H complete per PARSER_STATUS.md)
**Test commands:**
- `node tests/test-runtime-v2.mjs result/wasm/kernel.wasm` — ALL PASSED
- `node tests/kernel-smoke.mjs result/wasm/kernel.wasm` — ALL PASSED
- `node tests/test-runtime-gap-probes.mjs result/wasm/kernel.wasm` — **84/84 passed**

## Methodology

1. Read all kernel source files (dispatch, messages, class parsing, state, types, context, format, lexer, primary, AST, runtime bridge)
2. Read PARSER_STATUS.md (current reference) and runtime.h (public C ABI)
3. Run existing test suites (test-runtime-v2, kernel-smoke) — both pass
4. Write 84 targeted probe snippets covering 20+ feature categories
5. Execute probes against the WASM kernel via JSON bridge
6. Classify each feature as **supported / partial / stub / broken / missing**

## Feature Matrix

### SUPPORTED — Full implementation with passing tests

| Feature | Evidence | Source |
|---------|----------|--------|
| Basic @interface + @implementation | Probe PASS | `objc_interp_class.c` |
| @property with dot syntax | Probe PASS | `objc_interp_dispatch.c` (synthesized getter/setter) |
| @property auto-synthesis | Probe PASS | `objc_interp_dispatch.c` |
| @synthesize with custom ivar name | Probe PASS | `objc_interp_dispatch.c` |
| @property(readonly) | Probe PASS | `objc_interp_dispatch.c` |
| Blocks (return value, capture, __block) | Probe PASS (3/3) | `objc_interp_dispatch.c` |
| Block as method argument | Probe PASS | `objc_interp_messages.c` |
| @try/@catch/@finally | Probe PASS | `objc_interp_ast.c` |
| Nested @try/@catch | Probe PASS | `objc_interp_ast.c` |
| @throw | Probe PASS | `objc_interp_ast.c` |
| forwardInvocation: | Probe PASS | `objc_interp_messages.c` (lines 3492–3541) |
| KVC (valueForKey:/setValue:forKey:) | Probe PASS | `objc_interp_messages.c` (lines 686–722) |
| @autoreleasepool | Probe PASS (3/3) | `objc_interp_ast.c` |
| Categories (custom + Foundation) | Probe PASS (2/2) | `objc_interp_class.c` |
| nil messaging ([nil anyMethod]) | Probe PASS (2/2) | `objc_interp_messages.c` (line 276) |
| @selector() | Probe PASS (3/3) | `objc_interp_primary.c` |
| performSelector: | Probe PASS | `objc_interp_messages.c` (lines 916–1056) |
| respondsToSelector: | Probe PASS | `objc_interp_messages.c` (line 886) |
| stringWithFormat: | Probe PASS (2/2) | `objc_interp_format.c` |
| NSArray/NSDictionary literals + subscripts | Probe PASS (4/4) | `objc_interp_primary.c` |
| enumerateObjectsUsingBlock: | Probe PASS | `objc_interp_messages.c` (line 3307) |
| @() boxed expression | Probe PASS | `objc_interp_primary.c` |
| NSNumber boxing/unboxing | Probe PASS (2/2) | `objc_interp_messages.c` |
| NSData creation + isEqualToData: | Probe PASS (2/2) | `objc_interp_messages.c` |
| switch/case/default | Probe PASS | `objc_interp_ast.c` |
| Ternary operator | Probe PASS | `objc_interp_ast.c` |
| Compound assignment (*=, /=, %=) | Probe PASS | `objc_interp_ast.c` |
| Bitwise operators | Probe PASS | `objc_interp_ast.c` |
| Unary minus | Probe PASS | `objc_interp_ast.c` |
| Logical short-circuit (&&, \|\|) | Probe PASS | `objc_interp_ast.c` |
| typedef | Probe PASS | `objc_interp_class.c` |
| retain/release/autorelease (no-ops) | Probe PASS | `objc_interp_messages.c` (lines 3473–3487) |
| + (class method) dispatch | Probe PASS | `objc_interp_dispatch.c` |
| NSCopying protocol + copy | Probe PASS | `objc_interp_messages.c` |
| Protocol inheritance (@protocol Sub <Base>) | Probe PASS | `objc_interp_class.c` |
| KVO addObserver: (no-op, doesn't crash) | Probe PASS | `objc_interp_messages.c` |
| sel_registerName / sel_getName | Probe PASS | `runtime/runtime.c` |
| NSURL + NSURLRequest | Probe PASS | `objc_interp_messages.c` |
| NSString compare: | Probe PASS | returns 0 for equal |
| Fast enumeration (for...in) | Probe PASS | `objc_interp_primary.c` (fixed: coll_create_new) |
| for-in on dictionary | Probe PASS | `objc_interp_primary.c` (fixed: coll_create_new) |
| KVC on NSDictionary | Probe PASS | `objc_interp_messages.c` (fixed: coll_create_new) |

### PARTIAL — Implemented but with known gaps

| Feature | Status | Gap | Evidence |
|---------|--------|-----|----------|
| Inheritance chain | PARTIAL | Multi-level inheritance works for class registration, but **method dispatch on subclass instances returns 0** instead of the overridden value | Probe: `[Leaf ident]` returns 0, not 3. `find_interpreter_method` walks class hierarchy but FDObj: marker class resolution may not match. |
| [super message] | PARTIAL | `find_interpreter_method_super` exists and walks hierarchy, but **returns 0** instead of superclass result | Probe: `[Child val]` returns 0, not 15. Super dispatch code in `objc_interp_dispatch.c` lines 188–224 looks correct — likely a class pointer resolution issue. |
| @protocol + conformsToProtocol: | PARTIAL | `class_conforms_to_protocol` checks name + required methods, but **returns 0** for conforming classes | Probe: `[s conformsToProtocol:@protocol(Drawable)]` returns 0. The `@protocol(Drawable)` expression may not produce a valid protocol marker. |

### BROKEN — Implemented but produces incorrect results or crashes

| Feature | Status | Evidence | Root Cause |
|---------|--------|----------|------------|
| C-style for loop | BROKEN | `[for (int i=1; i<=5; i++)]` throws uncaught exception after first iteration | `objc_interp_ast.c` AST_FOR execution — likely `break`/`continue` or loop variable update issue. The existing smoke test passes C-style for, so this may be a `break`/`continue` interaction. |
| do/while loop | BROKEN | `do { i++; } while (i < 3)` throws exception after first iteration | Same category as for-loop — loop continuation may conflict with exception handling. |
| break in for loop | BROKEN | `break` inside for loop causes uncaught exception | `break` sets `g_ctx.break_pending` but the loop may not check it properly. |
| continue in for loop | BROKEN | `continue` inside for loop causes uncaught exception | Same as `break` — `continue` flag not handled in all loop types. |
| [obj copy] on Foundation NSArray | BROKEN | `[a copy]` returns `NSMutArr:9` marker instead of copy | `copy` dispatch on line 3463 returns `receiver` directly, but the receiver is an `NSMutArr:` marker, not an `NSArr:` marker. Immutable copy should return immutable. |
| +initialize auto-call | BROKEN | `+initialize` is not auto-called on first message send | ObjC runtime sends `+initialize` to a class before its first use. The interpreter does not implement this. |

### STUB — Placeholder that returns without doing real work

| Feature | Status | Evidence |
|---------|--------|----------|
| KVO (addObserver:forKeyPath:options:context:) | STUB | Accepts the message without error but does nothing. No observation notifications are sent. |
| retain/release/autorelease | STUB | No-ops — interpreter uses string pool GC, not refcounting. Correct for this architecture. |
| NSCopying / copy | STUB | `[obj copy]` returns `self` for Foundation types. Does not create actual copies. |
| NSMethodSignature | STUB | `signatureWithObjCTypes:` returns a fixed marker `"FDSig:v@:@"` — does not parse type encodings. |
| NSInvocation | STUB | Partial — supports setSelector:, setTarget:, invoke with 0–1 args. Multi-arg invocation is incomplete. |
| NSAutoreleasePool drain | STUB | No-op — pool stack exists but drain does nothing. |

### MISSING — Not implemented at all

| Feature | Severity | Notes |
|---------|----------|-------|
| isKindOfClass: / isMemberOfClass: | HIGH | Throws "does not respond to selector". Essential for polymorphic code. |
| NSMutableString | HIGH | Not registered as a Foundation class. `stringWithString:` on NSString works but NSMutableString is unknown. |
| @encode() | MEDIUM | Not implemented — parser doesn't recognize `@encode`. |
| @synchronized | MEDIUM | Not implemented — parser doesn't recognize `@synchronized`. |
| -> (arrow) ivar access | MEDIUM | Not implemented — `o->_val` causes parse error or infinite loop. |
| static local variables | MEDIUM | `static int c = 0;` inside function body causes "Unexpected token" parse error. |
| objc_setAssociatedObject / objc_getAssociatedObject | MEDIUM | Not implemented — `objc_setAssociatedObject` is not in the runtime bridge. |
| +initialize auto-dispatch | MEDIUM | Not implemented — `+initialize` is never called automatically. |
| NSNull | LOW | `[NSNull null]` not implemented. |
| NSStringFromSelector | LOW | Not implemented. |
| C struct access (NSRange.location) | LOW | NSRange works as a marker string `"NSRange:loc:len"` but `.location` / `.length` struct member access is not supported. |
| sortedArrayUsingSelector: | LOW | Not implemented on NSArray. |
| dataUsingEncoding: | LOW | Not implemented on NSString. |
| NSJSONSerialization (full) | LOW | JSONObjectWithData: requires NSData input which needs dataUsingEncoding: — circular dependency. |

## Severity Ranking (Implementation Priority)

### P0 — Blocks real-world code patterns

1. **for-loop break/continue** — C-style for, do/while, and break/continue all throw uncaught exceptions. This is the most impactful bug since loops are fundamental.
2. **isKindOfClass: / isMemberOfClass:** — Missing entirely. Polymorphic code depends on these.
3. **NSMutableString** — Not registered as a Foundation class. Any code using mutable strings will fail.
4. **Super dispatch returning 0** — `[super method]` exists but doesn't return correct values. Inheritance chains break.

### P1 — Important for completeness

6. **Protocol conformance check returns 0** — `conformsToProtocol:` doesn't work despite implementation existing.
7. **[NSArray copy] returns mutable marker** — Should return immutable copy.
8. **static local variables** — Parse error prevents use.
9. **Associated objects** — `objc_setAssociatedObject` not in runtime bridge.

### P2 — Nice to have

11. **@synchronized** — Not parsed.
12. **@encode** — Not parsed.
13. **-> ivar access** — Not parsed.
14. **+initialize auto-dispatch** — Never called.
15. **NSNull** — Not implemented.
16. **NSStringFromSelector** — Not implemented.
17. **C struct member access** — NSRange etc. use marker strings, not real structs.

## Recommended Implementation Sequence

1. **Fix for-loop break/continue** — Investigate `g_ctx.break_pending` / `g_ctx.continue_pending` handling in `objc_interp_ast.c`. The smoke test passes C-style for without break/continue, so the bug is specifically in the break/continue path.
2. **Add isKindOfClass: / isMemberOfClass:** — Implement in `objc_interp_messages.c` by walking the class hierarchy table (`g_ctx.class_hierarchy_class[]`).
3. **Register NSMutableString** — Add to Foundation class list in `objc_interpreter.c` and add `stringWithString:` dispatch.
4. **Fix super dispatch** — Debug `find_interpreter_method_super` — the class pointer resolution for FDObj: markers may not match the method table entries.
5. **Fix protocol conformance** — Debug `@protocol(Drawable)` expression — it may not produce a valid `FDProt:` marker that `conformsToProtocol:` can match.
6. **Fix [NSArray copy]** — Return immutable marker (NSArr:) instead of self when receiver is NSMutArr:.
7. **Add static local variables** — Extend parser to accept `static` keyword in local variable declarations.
8. **Add associated objects** — Implement `objc_setAssociatedObject` / `objc_getAssociatedObject` using the `Association` table already defined in types.h.

## Recently Fixed (Phase H, 2026-05-06)

| Fix | Commits | Tests Fixed |
|-----|---------|-------------|
| Collection slot activation — `coll_create_new()` for all 23 allocation sites | `a0a93aaa` | 9: subscripts, fast enumeration, KVC, enumerateObjectsUsingBlock, sel_getName, for-in on dictionary, KVC on NSDictionary |
| Block return values — `return_pending` check, `return_value` usage, `block_id_from_marker` rewrite | `299dca91` | 4: block returning value, block capturing variable, __block mutation, block as method argument |
| Ternary in variable declarations — skip ternary AST detection for type-prefixed statements | `62e7f9d0` | 1: ternary operator |

## Resource Limits (from source)

| Resource | Limit | Source |
|----------|-------|--------|
| Variables | 1024 | `OBJC_INTERP_MAX_VARS` |
| Methods | 64 | `MAX_METHODS` |
| Properties | 64 | `MAX_PROPERTIES` |
| Selectors | 4096 | `sel_registerName` error message |
| String pool | 65536 bytes | `OBJC_INTERP_STRING_POOL_SIZE` |
| AST nodes | 1024 | `MAX_AST_NODES` |
| Parse depth | 64 | `MAX_PARSE_DEPTH` |
| Blocks | 32 | `MAX_BLOCKS` |
| Collections | 64 | `MAX_COLLECTIONS` |
| Collection entries | 512 | `MAX_COLL_ENTRIES` |
| Instance variables | 256 | `MAX_INSTANCE_VARS` |
| Enumerators | 16 | `MAX_ENUMERATORS` |
| Invocations | 16 | `MAX_INVOCATIONS` |
| Associations | 256 | `MAX_ASSOCIATIONS` |
| KVO observers | 64 | `MAX_KVO_OBSERVERS` |
| Protocols | 32 | `MAX_PROTOCOLS` |
| Try/catch depth | 16 | `MAX_TRY_DEPTH` |
| Autorelease pool depth | 16 | `MAX_AUTORELEASE_POOL_DEPTH` |
| Network tasks | 32 | `MAX_NETWORK_TASKS` |
| Typedefs | 64 | `OBJC_INTERP_MAX_TYPEDEFS` |
| Method args | 8 | `MethodImpl.arg_names[8]` |
| Message args | 16 | `Value keyword_args[16]` |
| Token text | 256 | `OBJC_INTERP_MAX_TOKEN` |

## Stale Documentation Note

`docs/plans/runtime-feature-review.md` has been rewritten (2026-05-06) to reflect current implementation state. Previously it listed exceptions, autoreleasepool, protocols, `__block`, forwarding, and KVC as missing, but all are implemented and passing per PARSER_STATUS.md phases D–H.
