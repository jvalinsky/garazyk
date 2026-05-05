# Parser Status & Known Limitations

## Overview
The Objective-C interpreter in `kernel.wasm` uses a custom recursive-descent parser for Objective-C and C syntax. This document tracks implemented features, known gaps, and in-progress fixes.

## Current Status (as of 2026-05-05)
- **Notebook Tests:** 95/101 cells passing
- **Smoke Tests:** 80+ feature blocks
- **Runtime Expansion:** Phase D-G completed (Exceptions, Protocols, Blocks, Forwarding, KVC)

## Implemented Features

### Core Language
- ✓ @interface/@implementation class definitions
- ✓ Method declarations (instance and class)
- ✓ Property declarations with @property syntax and attributes (readonly, nonatomic, etc.)
- ✓ @synthesize and automatic property synthesis
- ✓ Message sends with multi-keyword selectors
- ✓ Block declarations and invocations with __block capture
- ✓ Exception handling: @try, @catch, @finally, @throw
- ✓ Autorelease pools: @autoreleasepool scoping
- ✓ Protocol declarations and runtime conformance checking
- ✓ Message forwarding: forwardInvocation:, methodSignatureForSelector:
- ✓ Basic Key-Value Coding (KVC): valueForKey:, setValue:forKey:
- ✓ Variable declarations (int, void, id, Class, SEL, BOOL, long, char, float, double)
- ✓ Static and extern variable declarations
- ✓ typedef declarations (including NS_ENUM)
- ✓ Explicit ivar blocks in @interface { ... }
- ✓ Qualifiers: const, volatile, restrict (parsed and skipped)

### Foundation Framework
- ✓ Literal syntax: @"string", @42, @3.14, @[], @{}, @()
- ✓ NSLog output capture
- ✓ NSString: length, characterAtIndex:, substringFromIndex:, substringToIndex:, hasPrefix:, hasSuffix:, uppercaseString, lowercaseString, stringByReplacingOccurrencesOfString:withString:, componentsSeparatedByString:
- ✓ NSArray/NSMutableArray: array, addObject:, removeObjectAtIndex:, objectAtIndex:, count, enumerateObjectsUsingBlock:, objectEnumerator
- ✓ NSDictionary/NSMutableDictionary: dictionary, setObject:forKey:, objectForKey:, count, objectEnumerator
- ✓ NSSet/NSMutableSet: set, addObject:, removeObject:, containsObject:, count, objectEnumerator
- ✓ NSNumber: numberWithInt:, numberWithFloat:, numberWithBool:, intValue, floatValue, boolValue
- ✓ NSData: basic allocation and access
- ✓ Fast Enumeration: for (type var in collection) for built-ins and custom objects (via objectEnumerator)

### Control Flow
- ✓ if/else statements
- ✓ switch/case with fall-through and break
- ✓ for loops (C-style and for-in)
- ✓ while loops and do/while
- ✓ break and continue statements
- ✓ Ternary operator (?:)
- ✓ Logical and Comparison operators

### Operators
- ✓ Arithmetic, Compound assignment, Unary minus
- ✓ sizeof operator
- ✓ Pointer dereference (*) in expressions and assignment

## Implementation Progress

### Exceptions & Protocols (Phase D) ✓ COMPLETED
**Implemented:** Stack-based `TryFrame` system, exception unwinding in AST evaluator, @protocol parsing, and `conformsToProtocol:` checking.

### Property Attributes & Autoreleasepool (Phase E) ✓ COMPLETED
**Implemented:** @autoreleasepool structural scaffolding and @property attribute parsing (readonly, nonatomic, copy, strong). Synthesis now respects `readonly`.

### Advanced Blocks & Fast Enumeration (Phase F) ✓ COMPLETED
**Implemented:** `__block` storage qualifier with write-back semantics and protocol-based `for-in` iteration for custom classes.

### Message Forwarding & KVC (Phase G) ✓ COMPLETED
**Implemented:** Fallback path for unrecognized selectors, `forwardInvocation:`, `NSInvocation` simulation, and `valueForKey:` / `setValue:forKey:` property mapping.

## Type Recognition

### Builtin Types Recognized
- Primitives: int, void, char, float, double, long, BOOL
- Objective-C: id, Class, SEL, Protocol
- Foundation: NSString, NSArray, NSDictionary, NSSet, NSNumber, NSData, NSInvocation, NSEnumerator
- Classes: Any user-defined @interface class

### Type Modifiers SUPPORTED
- `unsigned`, `signed`, `long`, `short`, `static`, `extern`, `*` (pointer)
- `const`, `volatile`, `restrict` (ignored)
- `__block`, `__weak`, `__strong` (block capture control)

### Type Modifiers NOT YET SUPPORTED
- Complex types (`struct`, `union`) — not fully implemented (except via `typedef NS_ENUM`)

## Architecture

### Entries
- `objc_kernel_execute()` — Execute cell code
- `objc_kernel_inspect()` — Variable/class reflection
- `objc_kernel_complete()` — Code completion (planned)

## Testing

### Smoke Tests
Run with: `node tests/test-runtime-v2.mjs result/wasm/kernel.wasm`  
Covers: Exceptions, Protocols, Blocks, Forwarding, KVC, Autoreleasepool.

## Future Work
1. **Method Swizzling**: Support for `method_exchangeImplementations` on interpreted methods.
2. **KVO**: Key-Value Observing support for synthesized properties.
3. **Struct Support**: Parsing and memory layout for simple C structs.
4. **Variadic Methods**: Support for custom variadic method signatures.

## Code Organization
(Refer to the source files in `kernel/` for implementation details.)
