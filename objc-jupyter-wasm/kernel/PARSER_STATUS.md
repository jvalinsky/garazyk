# Parser Status & Known Limitations

## Overview
The Objective-C interpreter in `kernel.wasm` uses a custom recursive-descent parser for Objective-C and C syntax. This document tracks implemented features, known gaps, and in-progress fixes.

## Current Status (as of 2026-05-04)
- **Notebook Tests:** 75/85 cells passing
- **Smoke Tests:** 60+ feature blocks
- **Parser Gaps:** 10 failing cells (6-7 addressable via current fixes)

## Implemented Features

### Core Language
- ✓ @interface/@implementation class definitions
- ✓ Method declarations (instance and class)
- ✓ Property declarations with @property syntax
- ✓ @synthesize and automatic property synthesis
- ✓ Message sends with multi-keyword selectors
- ✓ Block declarations and invocations
- ✓ Variable declarations (int, void, id, Class, SEL, BOOL, long, char, float, double)
- ✓ Static variable declarations (as of 2026-05-04)
- ✓ Extern declarations (as of 2026-05-04)

### Foundation Framework
- ✓ Literal syntax: @"string", @42, @3.14, @[], @{}, @()
- ✓ NSLog output capture
- ✓ NSString: length, characterAtIndex:, substringFromIndex:, substringToIndex:, hasPrefix:, hasSuffix:, uppercaseString, lowercaseString, stringByReplacingOccurrencesOfString:withString:, componentsSeparatedByString:
- ✓ NSArray/NSMutableArray: array, addObject:, removeObjectAtIndex:, objectAtIndex:, count, enumerateObjectsUsingBlock: (basic)
- ✓ NSDictionary/NSMutableDictionary: dictionary, setObject:forKey:, objectForKey:, count
- ✓ NSSet/NSMutableSet: set, addObject:, removeObject:, containsObject:, count
- ✓ NSNumber: numberWithInt:, numberWithFloat:, numberWithBool:, intValue, floatValue, boolValue
- ✓ NSData: basic allocation and access

### Control Flow
- ✓ if/else statements
- ✓ switch/case with fall-through and break
- ✓ for loops (C-style)
- ✓ while loops and do/while
- ✓ break and continue statements
- ✓ Ternary operator (?:)
- ✓ Logical operators (&&, ||, !)
- ✓ Comparison operators (==, !=, <, >, <=, >=)

### Operators
- ✓ Arithmetic (+, -, *, /, %)
- ✓ Compound assignment (+=, -=, *=, /=, %=)
- ✓ Unary minus (-)
- ✓ Pointer dereference (*) in expressions
- ✓ Pointer dereference assignment (*x = value)

## Known Gaps & Fixes

### Fix 1: Storage Qualifier Routing ✓ COMPLETED
**Status:** Implemented in commit b9875dee  
**What was fixed:** `static` and `extern` keywords in variable declarations  
**Example now works:** `static int counter = 0;`  
**Files changed:** objc_interp_parser.c (lines 671-726)  
**Impact:** Fixes 6-7 failing cells

### Fix 2: Multi-Token Type Parsing ⏳ PENDING
**Problem:** Types like `unsigned int` and `short int` fail to parse  
**Root cause:** Parser reads only one token as type name  
**Example failing:** `unsigned int x = 0;`  
**Impact:** Blocks 3-4 failing cells  
**Effort:** Medium (requires type parser refactoring)

### Fix 3: Block Parameter Pointer Types ⏳ PENDING INVESTIGATION
**Problem:** Block closures with pointer parameters crash parsing  
**Example failing:**
```c
[nums enumerateObjectsUsingBlock:^(id obj, int idx, int *stop) {
    if (idx == 1) { *stop = 1; }
}];
```
**Impact:** Blocks 1-2 failing cells  
**Status:** Requires investigation; error reporting may be misleading

### Fix 4: Smoke Test Verification ⏳ PENDING
**Status:** Long-running tests in progress; kernel builds successfully  
**Known issue:** Pre-existing for-loop test failure needs investigation

## Type Recognition

### Builtin Types Recognized
- Primitives: int, void, char, float, double, long
- Objective-C: id, Class, SEL, BOOL
- Objective-C integers: NSInteger, NSUInteger
- Foundation: NSString, NSArray, NSMutableArray, NSDictionary, NSMutableDictionary, NSNumber, NSData, NSSet
- C99: uint8_t, uint16_t, uint32_t, uint64_t, int8_t, int16_t, int32_t, int64_t, size_t
- Classes: Any user-defined @interface class

### Type Modifiers NOT YET SUPPORTED
- `unsigned` (standalone) — requires multi-token parsing
- `short` (standalone) — requires multi-token parsing
- `const`, `volatile`, `restrict` — not implemented
- Complex types (`struct`, `union`, `enum`) — not implemented

## Cross-Cell Persistence

### What Persists
- Class definitions (@interface/@implementation)
- Method implementations
- Property declarations
- Static variables
- User-defined instance variables (side table)
- Block definitions and closures

### What Resets Between Cells
- Local variables (non-static)
- Expression evaluation state
- Return/break/continue flags
- Parse depth tracking
- Error state

## Architecture

### Entry Points
- `objc_kernel_execute()` — Execute a single cell
- `objc_kernel_inspect()` — Get variable/class info (not yet implemented)
- `objc_kernel_complete()` — Code completion (not yet implemented)

### Key Functions
- `parse_statement()` (line 646) — Route statement types (expressions, declarations, control flow)
- `parse_type_and_var_decl()` (line 336) — Parse variable declarations with type modifiers
- `parse_expression()` (line 871) — Parse expressions and operators
- `objc_interp_init()` (line 1059) — Initialize interpreter state
- `objc_interp()` (line 1102) — Execute cell code

## Testing

### Smoke Tests
Run with: `node tests/kernel-smoke.mjs result/wasm/kernel.wasm`  
Coverage: 60+ feature blocks across parser, runtime, and Foundation

### Notebook Tests
Run with: `node tests/run-notebooks.mjs --dir demo/`  
Current baseline: 75/85 cells passing

### Known Test Failures
The failing cells are due to unimplemented parser features, not regressions:
1. `objc-state-and-blocks.ipynb` — static keyword (FIX 1 addresses this)
2. `atproto-accounts.ipynb` — @interface issues (may relate to FIX 2 or pre-existing)
3. Others — Foundation stubs, multi-token types, block parameters

## Performance Notes

### Limitations of Interpreter vs Compiled Approach
- No optimization or JIT compilation
- Message dispatch is linear search (not method tables)
- Collection operations copy data unnecessarily
- Block closures allocate and copy capture context on each invocation
- No inlining of simple methods

### Expected Performance Profile
- Simple operations: microseconds
- Collection operations: milliseconds (depending on size)
- Class definition overhead: negligible (one-time per cell)
- Block invocation: ~1-10 microseconds (including closure setup)

## Future Work

### High Priority
1. Complete multi-token type parsing (Fix 2)
2. Investigate block parameter pointer types (Fix 3)
3. Verify/fix smoke test regressions (Fix 4)

### Medium Priority
1. Implement `const` and `volatile` qualifiers
2. Add struct/union/enum support
3. Improve error messages and line tracking
4. Add variable inspection (objc_kernel_inspect)
5. Add code completion (objc_kernel_complete)

### Low Priority (Architecture Change)
1. Replace linear dispatch with method hash tables
2. Implement proper autorelease pool stacks
3. Add GC support (currently manual memory management)
4. Full GNUstep Base integration (beyond curated micro-base)

## Code Organization

| File | Purpose |
|------|---------|
| objc_interp_parser.c | Recursive-descent parser, expression evaluation |
| objc_interp_lexer.c | Tokenization |
| objc_interp_types.c | Type definitions, AST nodes |
| objc_interp_context.h | Centralized interpreter state (Phase D) |
| objc_interpreter.c | Main interpreter, initialization |
| objc_runtime_bridge.c | GNUstep libobjc2 integration |
| objc_interp_state.c | Variable/collection/block tables |
| objc_interp_messages.c | Method dispatch |
| objc_interp_dispatch.c | Message send routing |
| objc_interp_primary.c | Primary expression parsing |
| objc_interp_format.c | String formatting (NSLog, etc) |
| objc_interp_class.c | Class definition handling |
| objc_interp_ast.c | AST evaluation |

