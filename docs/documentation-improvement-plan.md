# Objective-C Documentation Improvement Plan

**Created**: 2026-02-27
**Goal**: Standardize and improve code documentation following Apple HeaderDoc best practices

---

## Executive Summary

The codebase uses **Apple's HeaderDoc style** as the primary documentation format with ~88% coverage in header files. However, there are inconsistencies (Javadoc style in some files) and gaps (implementation files, thread safety, error handling docs).

---

## Phase 1: Standardize Documentation Format

### 1.1 Migrate Javadoc → HeaderDoc

**Files to update:**
- `ATProtoPDS/Sources/Email/PDSEmailProvider.h`
- `ATProtoPDS/Sources/Blob/PDSBlobProvider.h`

**Change:**
```objective-c
// FROM (Javadoc)
/**
 * @protocol PDSEmailProvider
 * @abstract Email sending protocol
 */

// TO (HeaderDoc)
/*!
 @protocol PDSEmailProvider
 @abstract Email sending protocol
 */
```

### 1.2 Standardize File Headers

All `.h` files should have consistent file-level documentation:

```objective-c
/*!
 @header FileName.h
 @abstract One-line summary of the module's purpose
 @discussion
    Detailed explanation of the module's responsibilities,
    design decisions, and how it fits into the larger system.

    Include usage notes, thread safety considerations, and
    any important implementation details.
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */
```

**Files missing proper headers:**
- `ATProtoPDS/Sources/PLC/*.h` (multiple files)
- `ATProtoPDS/Sources/Sync/*.h` (some files)

---

## Phase 2: Header File Documentation Standards

### 2.1 Class/Interface Documentation

**Required elements:**
```objective-c
/*!
 @class ClassName
 @abstract Brief one-line description
 @discussion
    Detailed explanation of the class purpose and behavior.

    Include:
    - Primary responsibilities
    - Key design patterns used
    - Thread safety notes (if applicable)
    - Memory management considerations

 @code
    // Usage example
    ClassName *instance = [[ClassName alloc] init];
    [instance performAction];
 @endcode

 @warning Note any important caveats
 @see RelatedClass
 */
@interface ClassName : NSObject
```

### 2.2 Method Documentation

**Required elements:**
```objective-c
/*!
 @method methodName:param1:param2:
 @abstract Brief description of what the method does
 @param param1 Description of first parameter
 @param param2 Description of second parameter
 @return Description of return value
 @discussion
    Optional detailed explanation of implementation details,
    edge cases, or performance characteristics.
 @error
    NSErrorDomain and error codes that may be returned:
    - MyErrorDomain/MyErrorCodeInvalidInput - param1 was nil
    - MyErrorDomain/MyErrorCodeNetworkFailure - connection failed
 @note Thread safety notes if applicable
 @see relatedMethod:
 */
- (ReturnType)methodName:(ParamType)param1
                   param2:(ParamType2)param2;
```

### 2.3 Property Documentation

```objective-c
/*!
 @property propertyName
 @abstract Brief description
 @discussion
    Optional detailed explanation for non-trivial properties.
    Include KVO compliance notes if applicable.
 */
@property (nonatomic, copy, nullable) NSString *propertyName;

/*! Read-only property description. */
@property (nonatomic, readonly) NSInteger count;
```

### 2.4 Enum Documentation

```objective-c
/*!
 @enum EnumName
 @abstract Brief description of the enum's purpose
 @constant EnumValueA Description of first value
 @constant EnumValueB Description of second value
 */
typedef NS_ENUM(NSInteger, EnumName) {
    /*! Description of EnumValueA */
    EnumValueA,
    /*! Description of EnumValueB */
    EnumValueB
};
```

### 2.5 Protocol Documentation

```objective-c
/*!
 @protocol ProtocolName
 @abstract Brief description of the protocol's purpose
 @discussion
    Detailed explanation of the contract and expected behavior.
    Include notes about required vs optional methods.

 @required
    All conforming classes must implement these methods.

 @optional
    These methods provide optional functionality.
 */
@protocol ProtocolName <NSObject>

/*! Required method description */
- (void)requiredMethod;

@optional
/*! Optional method description */
- (void)optionalMethod;

@end
```

---

## Phase 3: Implementation File Documentation Standards

### 3.1 File-Level Headers

```objective-c
//
//  FileName.m
//  ATProtoPDS
//
//  Implementation of ClassName functionality.
//  See FileName.h for public API documentation.
//

#import "FileName.h"

// Private constants
static NSString * const kPrivateConstant = @"value";

// Private interface
@interface ClassName ()
// Private properties
@end

@implementation ClassName
```

### 3.2 Pragma Mark Organization

Use `#pragma mark` consistently to organize implementation:

```objective-c
@implementation ClassName

#pragma mark - Lifecycle

- (instancetype)init {
    // ...
}

- (void)dealloc {
    // ...
}

#pragma mark - Public Methods

- (void)publicMethod {
    // ...
}

#pragma mark - Private Methods

- (void)privateMethod {
    // ...
}

#pragma mark - Property Accessors

- (void)setProperty:(id)property {
    // ...
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    // ...
}

@end
```

### 3.3 Inline Comment Standards

**DO comment:**
- Non-obvious algorithm decisions
- Workarounds for system bugs
- Performance-critical code
- Complex business logic
- Edge cases being handled

**DON'T comment:**
- Obvious code operations
- Self-documenting code

**Format:**
```objective-c
// WHY: Explain the reason for non-obvious code
// NOTE: Important information for maintainers
// FIXME: Known issue that should be addressed
// TODO: Future improvement
// WARNING: Dangerous code that needs care

// Calculate the MST hash using the specified algorithm.
// The order of operations is critical here - we must process
// children before parents to ensure correct CID calculation.
NSString *hash = [self computeMSTHash:node];
```

### 3.4 Method Implementation Comments

For complex methods, add a brief header:

```objective-c
#pragma mark - Private Methods

/*!
 @brief Process the incoming request and route to handler.
 @discussion
    This method implements the routing algorithm:
    1. Parse the NSID from the path
    2. Look up the registered handler
    3. Validate authentication if required
    4. Execute the handler

    Performance: O(1) lookup using the handler dictionary.
    Thread Safety: Uses @synchronized for handler registration.
 */
- (void)processRequest:(HttpRequest *)request {
    // Implementation...
}
```

---

## Phase 4: Special Documentation Categories

### 4.1 Thread Safety Documentation

Add thread safety notes to classes/methods with concurrency:

```objective-c
/*!
 @class HttpRouter
 @discussion
    Thread Safety: This class is thread-safe for read operations.
    Handler registration uses @synchronized to prevent race conditions.

    All public methods may be called from any thread.
 */
@interface HttpRouter : NSObject

/*!
 @method registerHandler:forMethod:
 @discussion
    Thread Safety: This method is thread-safe and may be called
    from any thread. Uses @synchronized for mutual exclusion.
 */
- (void)registerHandler:(Handler)handler forMethod:(NSString *)method;

@end
```

### 4.2 Memory Management Documentation

Document memory management for non-ARC code or complex retain cycles:

```objective-c
/*!
 @class WebSocketConnection
 @discussion
    Memory Management:
    - The delegate is held weakly to prevent retain cycles
    - Call -disconnect to release all resources
    - The connection retains itself during async operations
 */
@interface WebSocketConnection : NSObject

/*!
 @property delegate
 @discussion
    Weak reference to prevent retain cycles.
    The delegate is not retained.
 */
@property (nonatomic, weak) id<WebSocketDelegate> delegate;

@end
```

### 4.3 Error Documentation

Document error domains and codes:

```objective-c
/*!
 @const ATProtoErrorDomain
 @abstract Error domain for AT Protocol operations
 */
extern NSString * const ATProtoErrorDomain;

/*!
 @enum ATProtoErrorCode
 @abstract Error codes for AT Protocol operations
 @constant ATProtoErrorInvalidDID The DID format was invalid
 @constant ATProtoErrorResolutionFailed DID resolution failed
 @constant ATProtoErrorNetworkFailure Network request failed
 */
typedef NS_ENUM(NSInteger, ATProtoErrorCode) {
    ATProtoErrorInvalidDID = 1,
    ATProtoErrorResolutionFailed = 2,
    ATProtoErrorNetworkFailure = 3
};
```

### 4.4 API Stability Documentation

Mark API stability:

```objective-c
/*!
 @method experimentalMethod
 @discussion
    API Stability: This method is experimental and may change
    or be removed in future versions without notice.
 */
- (void)experimentalMethod;

/*!
 @method deprecatedMethod
 @deprecated Use newMethod instead. Will be removed in v2.0.
 */
- (void)deprecatedMethod __attribute__((deprecated("Use newMethod instead")));
```

---

## Phase 5: Documentation Coverage Goals

### Priority 1: Public API Headers (Critical)

| Module | Current | Target | Status |
|--------|---------|--------|--------|
| Auth | 95% | 100% | Minor gaps |
| Core | 95% | 100% | Minor gaps |
| Database | 98% | 100% | Good |
| Network | 90% | 100% | Needs work |
| Repository | 85% | 100% | Needs work |
| PLC | 60% | 100% | Critical |
| Sync | 70% | 100% | Critical |

### Priority 2: Implementation Files (Important)

- Add file headers to all `.m` files
- Add `#pragma mark` sections consistently
- Document complex algorithms
- Add inline comments for non-obvious logic

### Priority 3: Internal Documentation (Nice to Have)

- Document private methods
- Add architecture diagrams
- Create module-level README files

---

## Phase 6: Implementation Checklist

### Week 1: Standardization
- [ ] Convert Javadoc comments to HeaderDoc in Email/Blob modules
- [ ] Add missing file headers to PLC module
- [ ] Add missing file headers to Sync module
- [ ] Create DOCUMENTATION.md style guide

### Week 2: Core Modules
- [ ] Review and enhance Auth module documentation
- [ ] Review and enhance Core module documentation
- [ ] Add thread safety notes where applicable
- [ ] Add error documentation for public methods

### Week 3: Network & Repository
- [ ] Review Network module documentation
- [ ] Review Repository module documentation
- [ ] Document MST algorithm thoroughly
- [ ] Add usage examples for complex APIs

### Week 4: Implementation Files
- [ ] Add `#pragma mark` sections consistently
- [ ] Document complex algorithms in `.m` files
- [ ] Add inline comments for non-obvious logic
- [ ] Review and update copyright dates

---

## Tools & Validation

### HeaderDoc Generation
```bash
# Generate HTML documentation
headerdoc2html -o docs/api ATProtoPDS/Sources

# Resolve cross-references
resolveLinks docs/api
```

### Validation Script
```bash
# Check for undocumented public methods
./scripts/check-documentation.sh
```

---

## Style Guide Quick Reference

| Element | Format |
|---------|--------|
| File header | `/*! @header ... */` |
| Class | `/*! @class ... */` |
| Method | `/*! @method ... @param ... @return */` |
| Property | `/*! Brief description. */` |
| Enum | `/*! @enum ... @constant ... */` |
| Protocol | `/*! @protocol ... */` |
| Inline comment | `// Single line` |
| Section marker | `#pragma mark - Section Name` |

---

## References

- [Apple HeaderDoc User Guide](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/HeaderDoc/tags/tags.html)
- [Apple API Design Guidelines](https://developer.apple.com/documentation/swift/api_design_guidelines)
- [Objective-C Coding Conventions](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ProgrammingWithObjectiveC/Conventions/Conventions.html)
