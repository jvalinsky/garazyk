# Objective-C Runtime Features Review - WASM Kernel

## Overview
This document summarizes the current state of Objective-C runtime features in the WASM kernel and identifies gaps compared to a full Objective-C environment.

## Implemented Features
- **Classes:** `@interface` and `@implementation` are supported.
- **Methods:** Instance and class methods are supported with multi-keyword selectors.
- **Properties:** Basic `@property` and `@synthesize` are supported.
- **Blocks:** Block literals and invocations are supported with basic variable capture (by value).
- **Literals:** NSString, NSNumber, NSArray, and NSDictionary literals are supported.
- **Control Flow:** C-style loops and `for-in` (for NSArray and NSString) are supported.
- **Categories:** `@implementation` of categories is supported for adding methods to existing classes.

## Missing or Partially Implemented Features

### 1. Exceptions (@try, @catch, @finally, @throw)
- **Status:** Lexically recognized but functionally **missing**.
- **Gaps:** The parser skips `@try`/`@catch`/`@finally` blocks with "no-op semantics". No actual exception throwing or catching logic exists in the AST evaluator.

### 2. Autorelease Pools (@autoreleasepool)
- **Status:** **Missing**.
- **Gaps:** Recognized by the lexer but not implemented in the parser or evaluator. Memory management for interpreted objects is currently manual or lacks proper autorelease stack semantics.

### 3. Protocols
- **Status:** **Partially Implemented**.
- **Gaps:** `@protocol` declarations are parsed and stored. Conformance lists in `@interface` are parsed. However, protocol conformance is not enforced at runtime, and there is no integration with `conformsToProtocol:`.

### 4. Property Attributes
- **Status:** **Missing**.
- **Gaps:** Attributes like `copy`, `strong`, `weak`, `atomic`, `nonatomic`, `assign`, `readonly` are not parsed. The parser skips parentheses in `@property (...)`.

### 5. Advanced Block Features
- **Status:** **Missing `__block`**.
- **Gaps:** Variable capture is by value only. The `__block` storage qualifier for sharing state between a block and its enclosing scope is not supported.

### 6. Message Forwarding
- **Status:** **Missing**.
- **Gaps:** No support for `forwardInvocation:` or `methodSignatureForSelector:` for interpreted methods.

### 7. Key-Value Coding (KVC) / Key-Value Observing (KVO)
- **Status:** **Missing**.
- **Gaps:** Interpreted properties and ivars are not automatically accessible via `valueForKey:` or observable via KVO.

### 8. Fast Enumeration (Full Support)
- **Status:** **Limited**.
- **Gaps:** `for-in` is hardcoded for `NSArray` and `NSString`. It does not support the `NSFastEnumeration` protocol for custom classes.

### 9. Method Swizzling
- **Status:** **Missing**.
- **Gaps:** The interpreter uses a custom dispatch mechanism that does not integrate with standard `objc_method` swizzling.

## Recommendations
1. **Implement Autorelease Pools:** High priority for better memory management in notebooks.
2. **Implement Exception Handling:** Necessary for robust error handling in user-defined classes.
3. **Enhance Property Parsing:** Support at least `nonatomic` and `assign`/`strong` to match common Objective-C patterns.
4. **Protocol Runtime Support:** Hook `conformsToProtocol:` to the interpreter's protocol table.
5. **__block Support:** Improve block utility for algorithms requiring state modification.
