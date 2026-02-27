# Documentation Style Guide

This guide defines the documentation standards for the September ATProtoPDS codebase.

## Format: Apple HeaderDoc

All documentation uses Apple's HeaderDoc format with `/*!` delimiters.

```objective-c
/*!
 @header FileName.h
 @abstract Brief summary
 @discussion Detailed explanation.
 */
```

## File Headers

Every `.h` file must have a file header:

```objective-c
/*!
 @header FileName.h

 @abstract One-line summary of the module's purpose.

 @discussion
    Detailed explanation of the module's responsibilities,
    design decisions, and how it fits into the larger system.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */
```

## Class Documentation

```objective-c
/*!
 @class ClassName

 @abstract Brief one-line description.

 @discussion
    Detailed explanation of the class purpose and behavior.

    Include:
    - Primary responsibilities
    - Key design patterns used
    - Thread safety notes (if applicable)

 @code
    ClassName *instance = [[ClassName alloc] init];
    [instance performAction];
 @endcode
 */
@interface ClassName : NSObject
```

## Method Documentation

```objective-c
/*!
 @method methodName:param1:param2:

 @abstract Brief description of what the method does.

 @param param1 Description of first parameter.
 @param param2 Description of second parameter.

 @return Description of return value.

 @discussion
    Optional detailed explanation of implementation details,
    edge cases, or performance characteristics.

 @error
    NSErrorDomain and error codes that may be returned:
    - MyErrorDomain/MyErrorCodeInvalidInput - param1 was nil

 @note Thread safety notes if applicable.
 */
- (ReturnType)methodName:(ParamType)param1 param2:(ParamType2)param2;
```

## Property Documentation

```objective-c
/*!
 @property propertyName

 @abstract Brief description.

 @discussion
    Optional detailed explanation for non-trivial properties.
    Include KVO compliance notes if applicable.
 */
@property (nonatomic, copy, nullable) NSString *propertyName;

/*! Read-only property description. */
@property (nonatomic, readonly) NSInteger count;
```

## Enum Documentation

```objective-c
/*!
 @enum EnumName

 @abstract Brief description of the enum's purpose.

 @constant EnumValueA Description of first value.
 @constant EnumValueB Description of second value.
 */
typedef NS_ENUM(NSInteger, EnumName) {
    /*! Description of EnumValueA */
    EnumValueA,
    /*! Description of EnumValueB */
    EnumValueB
};
```

## Protocol Documentation

```objective-c
/*!
 @protocol ProtocolName

 @abstract Brief description of the protocol's purpose.

 @discussion
    Detailed explanation of the contract and expected behavior.
 */
@protocol ProtocolName <NSObject>

/*! Required method description. */
- (void)requiredMethod;

@optional
/*! Optional method description. */
- (void)optionalMethod;

@end
```

## Error Documentation

Define error domains and codes with documentation:

```objective-c
/*! Error domain for AT Protocol operations. */
extern NSString * const ATProtoErrorDomain;

/*!
 @enum ATProtoErrorCode

 @abstract Error codes for AT Protocol operations.

 @constant ATProtoErrorInvalidDID The DID format was invalid.
 @constant ATProtoErrorResolutionFailed DID resolution failed.
 */
typedef NS_ENUM(NSInteger, ATProtoErrorCode) {
    ATProtoErrorInvalidDID = 1,
    ATProtoErrorResolutionFailed = 2
};
```

## Thread Safety Documentation

Document thread safety for concurrent classes:

```objective-c
/*!
 @class HttpRouter

 @discussion
    Thread Safety: This class is thread-safe for read operations.
    Handler registration uses @synchronized for mutual exclusion.

    All public methods may be called from any thread.
 */
```

## Implementation Files (.m)

### Pragma Marks

Organize implementation with `#pragma mark`:

```objective-c
@implementation ClassName

#pragma mark - Lifecycle

- (instancetype)init { }

#pragma mark - Public Methods

- (void)publicMethod { }

#pragma mark - Private Methods

- (void)privateMethod { }

#pragma mark - Property Accessors

- (void)setProperty:(id)property { }

@end
```

### Inline Comments

**DO comment:**
- Non-obvious algorithm decisions
- Workarounds for system bugs
- Performance-critical code
- Complex business logic

**DON'T comment:**
- Obvious code operations
- Self-documenting code

```objective-c
// WHY: We must process children before parents to ensure correct CID calculation.
// NOTE: This is a workaround for rdar://12345678.
// FIXME: Known issue that should be addressed before v2.0.
```

## Quick Reference

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

## Validation

Generate HTML documentation:

```bash
headerdoc2html -o docs/api ATProtoPDS/Sources
resolveLinks docs/api
```
