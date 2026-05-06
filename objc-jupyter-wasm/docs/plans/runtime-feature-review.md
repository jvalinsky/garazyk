# Objective-C Runtime Features Review — WASM Kernel

**Last updated:** 2026-05-06
**Current test status:** 84/84 runtime gap probes passing
**Cross-reference:** `kernel/PARSER_STATUS.md`, `docs/runtime-gap-report.md`

## Overview

This document summarizes the current state of Objective-C runtime features in the WASM kernel. The kernel implements a custom recursive-descent interpreter for Objective-C 2.0 syntax, compiled to WebAssembly via wasi-sdk.

## Implemented Features

### Core Language

| Feature | Status | Notes |
|---------|--------|-------|
| @interface / @implementation | ✓ Supported | Class definitions with instance and class methods |
| @property with dot syntax | ✓ Supported | Synthesized getter/setter, auto-synthesis, custom ivar names via @synthesize |
| @property(readonly) | ✓ Supported | Read-only enforcement |
| Multi-keyword selectors | ✓ Supported | `addObject:atIndex:` etc. |
| Block declarations and invocations | ✓ Supported | Return values, by-value capture, `__block` write-back, block-as-argument |
| Exception handling | ✓ Supported | `@try`, `@catch`, `@finally`, `@throw`, nested try/catch |
| Autorelease pools | ✓ Supported | `@autoreleasepool` scoping, nested pools |
| Protocol declarations | ✓ Supported | `@protocol`, conformance lists, protocol inheritance |
| Message forwarding | ✓ Supported | `forwardInvocation:`, `methodSignatureForSelector:` |
| Key-Value Coding | ✓ Supported | `valueForKey:`, `setValue:forKey:`, KVC on dictionaries |
| Categories | ✓ Supported | Custom and Foundation class categories |
| nil messaging | ✓ Supported | `[nil anyMethod]` returns nil/0 |
| @selector() | ✓ Supported | Compile-time and runtime selector references |
| performSelector: | ✓ Supported | Dynamic message dispatch |
| respondsToSelector: | ✓ Supported | Runtime method introspection |
| typedef | ✓ Supported | Including NS_ENUM |
| Variable declarations | ✓ Supported | int, void, id, Class, SEL, BOOL, long, char, float, double, static, extern |
| Qualifiers | ✓ Supported | const, volatile, restrict (parsed and skipped), `__block`, `__weak`, `__strong` |

### Foundation Framework

| Feature | Status | Notes |
|---------|--------|-------|
| Literal syntax | ✓ Supported | `@"string"`, `@42`, `@3.14`, `@[]`, `@{}`, `@()` |
| NSLog | ✓ Supported | Output capture via host stream |
| NSString | ✓ Supported | length, characterAtIndex:, substringFromIndex:, substringToIndex:, hasPrefix:, hasSuffix:, uppercaseString, lowercaseString, stringByReplacingOccurrencesOfString:withString:, componentsSeparatedByString:, compare: |
| NSArray / NSMutableArray | ✓ Supported | array, addObject:, removeObjectAtIndex:, objectAtIndex:, count, enumerateObjectsUsingBlock:, objectEnumerator |
| NSDictionary / NSMutableDictionary | ✓ Supported | dictionary, setObject:forKey:, objectForKey:, count, objectEnumerator |
| NSSet / NSMutableSet | ✓ Supported | set, addObject:, removeObject:, containsObject:, count, objectEnumerator |
| NSNumber | ✓ Supported | numberWithInt:, numberWithFloat:, numberWithBool:, intValue, floatValue, boolValue |
| NSData | ✓ Supported | Creation, access, isEqualToData: |
| Fast enumeration | ✓ Supported | `for (type var in collection)` for built-ins and custom objects |
| NSNumber boxing/unboxing | ✓ Supported | `@()` boxed expressions |
| NSCopying + copy | ✓ Stub | Returns self for Foundation types (no deep copy) |
| retain/release/autorelease | ✓ Stub | No-ops — interpreter uses string pool GC |

### Control Flow

| Feature | Status | Notes |
|---------|--------|-------|
| if/else | ✓ Supported | |
| switch/case/default | ✓ Supported | With fall-through and break |
| for loops (C-style) | ⚠ Partial | Works without break/continue; break/continue cause uncaught exceptions |
| for-in loops | ✓ Supported | Fixed in Phase H (coll_create_new) |
| while / do-while | ⚠ Partial | do/while throws exception after first iteration |
| break / continue | ✗ Broken | Sets pending flags but loop bodies don't check them properly |
| Ternary operator (?:) | ✓ Supported | Including in variable declarations (fixed in Phase H) |
| Logical short-circuit (&&, \|\|) | ✓ Supported | AST-based short-circuit evaluation |

### Operators

| Feature | Status | Notes |
|---------|--------|-------|
| Arithmetic | ✓ Supported | +, -, *, /, % |
| Compound assignment | ✓ Supported | +=, -=, *=, /=, %= |
| Bitwise | ✓ Supported | <<, >>, &, \|, ^, ~ |
| Unary minus | ✓ Supported | |
| sizeof | ✓ Supported | |
| Pointer dereference (*) | ✓ Supported | In expressions and assignment |

## Partial — Implemented with Known Gaps

| Feature | Gap | Evidence |
|---------|-----|----------|
| Inheritance chain | Method dispatch on subclass instances returns 0 | `[Leaf ident]` returns 0, not 3 |
| [super message] | Returns 0 instead of superclass result | `[Child val]` returns 0, not 15 |
| @protocol + conformsToProtocol: | Returns 0 for conforming classes | `@protocol(Drawable)` may not produce valid marker |
| C-style for loop | break/continue cause uncaught exceptions | Loop continuation conflicts with exception handling |
| do/while loop | Throws exception after first iteration | Same root cause as for-loop break/continue |

## Stub — Placeholder Implementations

| Feature | Notes |
|---------|-------|
| KVO (addObserver:forKeyPath:options:context:) | Accepts message but does nothing |
| retain/release/autorelease | No-ops (correct for GC architecture) |
| NSCopying / copy | Returns self, no deep copy |
| NSMethodSignature | Returns fixed marker, doesn't parse type encodings |
| NSInvocation | Partial: setSelector:, setTarget:, invoke with 0–1 args |
| NSAutoreleasePool drain | No-op |

## Missing — Not Implemented

| Feature | Severity | Notes |
|---------|----------|-------|
| isKindOfClass: / isMemberOfClass: | HIGH | Throws "does not respond to selector" |
| NSMutableString | HIGH | Not registered as Foundation class |
| @encode() | MEDIUM | Parser doesn't recognize |
| @synchronized | MEDIUM | Parser doesn't recognize |
| -> (arrow) ivar access | MEDIUM | Parse error or infinite loop |
| static local variables | MEDIUM | Parse error in function body |
| objc_setAssociatedObject / objc_getAssociatedObject | MEDIUM | Not in runtime bridge |
| +initialize auto-dispatch | MEDIUM | Never called automatically |
| NSNull | LOW | `[NSNull null]` not implemented |
| NSStringFromSelector | LOW | Not implemented |
| C struct member access | LOW | NSRange etc. use marker strings |
| sortedArrayUsingSelector: | LOW | Not on NSArray |
| dataUsingEncoding: | LOW | Not on NSString |
| NSJSONSerialization (full) | LOW | Circular dependency with NSData |

## Implementation History

| Phase | Features | Status |
|-------|----------|--------|
| A–C | Core class/method/property support, literals, basic control flow | ✓ Complete |
| D | Exceptions & protocols | ✓ Complete |
| E | Property attributes & autoreleasepool | ✓ Complete |
| F | `__block` & fast enumeration | ✓ Complete |
| G | Message forwarding & KVC | ✓ Complete |
| H | Collection/block/ternary fixes (84/84 probes) | ✓ Complete |

## Next Priorities

1. Fix for-loop break/continue (P0)
2. Add isKindOfClass: / isMemberOfClass: (P0)
3. Register NSMutableString (P0)
4. Fix super dispatch returning 0 (P0)
5. Fix protocol conformance check (P1)
