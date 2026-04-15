# Documentation and Comment Style Guide

This guide defines writing standards for September PDS maintainer docs, Objective-C HeaderDoc, and inline comments. Use it with the [Contributor Guide](docs/index.md), [Build Guide](BUILD.md), and the repository rewrite skill in [skills/rewrite-dev-docs-comments](skills/rewrite-dev-docs-comments/SKILL.md).

## Scope

Use different formats for different readers:

| Surface | Format | Reader question |
| --- | --- | --- |
| `docs/` Markdown | GitHub-flavored Markdown and VitePress frontmatter where needed | "How do I understand, change, or operate this subsystem?" |
| public `.h` declarations | Apple HeaderDoc-style comments with `/*!` delimiters | "What contract does this symbol expose to callers?" |
| `.m` implementation comments | short comments near non-obvious logic | "What invariant or tradeoff would be easy to miss?" |

Do not put operational runbooks in code comments. Link to the relevant doc instead.

## Markdown Docs

Contributor-facing docs belong under `docs/`, with the numbered VitePress sections as the primary path:

- `docs/01-getting-started/` for onboarding and repository navigation
- `docs/10-tutorials/` for guided workflows
- `docs/11-reference/` for lookup material and operations references
- `docs/tests/`, `docs/security/`, `docs/oauth2/`, and `docs/architecture/` for deeper catalogs or historical detail

Write docs for the task the reader is doing. Tutorials teach one validated path, how-to pages solve one task, reference pages provide lookup material, and explanation pages preserve design tradeoffs.

## Writing Rules

- Start with the concrete behavior, decision, or constraint.
- Preserve API names, command names, paths, config keys, error behavior, and security assumptions exactly.
- Replace vague quality claims with scope, mechanisms, and limits.
- Avoid time-sensitive phrasing unless the date is part of a dated report.
- Add crosslinks when another doc owns setup, testing, deployment, security, or subsystem detail.
- When code and docs disagree, trust the code and update the docs.

## HeaderDoc Format

Public Objective-C API documentation uses Apple's HeaderDoc format with `/*!` delimiters.

```objective-c
/*!
 @header FileName.h
 @abstract Brief summary
 @discussion Detailed explanation.
 */
```

## File Headers

Public `.h` files should have a file header when it clarifies the module boundary:

```objective-c
/*!
 @header FileName.h

 @abstract One-line summary of the module's purpose.

 @discussion
    Explain responsibilities, caller-visible constraints, and the subsystem
    boundary. Move long architecture discussion to docs/.

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
    Add caller-visible edge cases, side effects, threading requirements, or
    performance constraints. Keep private implementation details in the .m file.

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
- Lock ordering, parser assumptions, and protocol invariants

**DON'T comment:**
- Obvious code operations
- Self-documenting code
- Claims that should live in tests or docs

```objective-c
// WHY: We must process children before parents to ensure correct CID calculation.
// NOTE: This is a workaround for rdar://12345678.
// FIXME: This path accepts duplicate records until MST diff reconciliation owns tombstones.
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
headerdoc2html -o docs/api Garazyk/Sources
resolveLinks docs/api
```

For docs changes, run the smallest useful verification:

```bash
python3 skills/rewrite-dev-docs-comments/scripts/scan_llm_speak.py README.md docs/index.md docs/01-getting-started docs/11-reference
cd docs
npm run docs:build
```

The scanner is a filter, not a substitute for checking facts against source files. Generated VitePress cache files and historical reports can produce noisy results; verify edited docs directly.

## Related Docs

- [Contributor Guide](docs/index.md)
- [Docs Workspace Guide](docs/README.md)
- [Setup Guide](docs/01-getting-started/setup.md)
- [Testing Map](docs/11-reference/testing-map.md)
- [Documentation Update Checklist](docs/DOCUMENTATION_UPDATE_CHECKLIST.md)
