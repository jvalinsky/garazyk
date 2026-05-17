---
name: rewriting-code-comments
description: "Deprecated legacy Objective-C documentation cleanup workflow. Use only when explicitly asked to edit historical Objective-C comments; use tsdoc-standards for current TypeScript APIs."
---

# Rewriting Code Comments and Documentation

Use this skill to turn informal, generated, or noisy comments into precise Objective-C documentation. Preserve technical meaning while removing conversational phrasing, decorative symbols, marketing language, hedging, and redundant explanation. New Objective-C API documentation should use Doxygen block comments with HeaderDoc-style tags.

## When to Use

Use when comments or API docs contain:

- Conversational phrases such as "Let me", "I'll", or "First, let's".
- Emojis or decorative markers.
- Marketing superlatives such as "seamless", "powerful", or "revolutionary".
- Self-narrative, uncertainty hedging, or tutorial tone.
- Missing Doxygen-compatible HeaderDoc tags for public Objective-C APIs.
- Regular comments where Xcode-indexed documentation is expected.

Do not use when preserving source style matters, comments are already compliant, or the text is intentional user-facing documentation rather than code documentation.

## Rewrite Workflow

1. Identify the documentation target: file, class, method, property, enum, constant, typedef, or error domain.
2. Extract the technical facts: purpose, parameters, return value, side effects, failure modes, thread safety, availability, and related APIs.
3. Remove conversational, decorative, marketing, and redundant text.
4. Choose the smallest documentation form that preserves meaning: `///` for short API docs or `/** ... */` for multi-line Objective-C API documentation. Preserve existing `/*! ... */` blocks unless the surrounding file is already being normalized.
5. Add required tags: `@abstract`, `@discussion`, `@param`, `@return`, `@see`, `@warning`, or `@throws` when applicable.
6. Verify parameter names, nullability, generics, availability, and cross-references against the actual declaration.

## Core Rules

- Document why an API exists, what contract it exposes, and what callers must know.
- Do not restate implementation line-by-line.
- Keep summaries short and declarative.
- Use precise Objective-C terms for nullability, ownership, queues, errors, and availability.
- Preserve edge cases, side effects, constraints, and failure behavior.
- Remove emojis, filler, first-person narration, vague praise, and uncertainty hedging.
- Prefer `/** ... */` for new or touched Objective-C API docs so Doxygen, Xcode, and HeaderDoc-style readers all parse the same source.
- Use `@abstract` for the one-sentence contract. Use `@discussion` only when callers need behavior, threading, failure, or compatibility details.
- Use `@param` and `@return` only when the declaration has parameters or a return value that needs a caller-facing contract.
- Do not mechanically rewrite every legacy `/*! ... */` block during unrelated edits.

## Objective-C API Examples

Class or interface:

```objc
/**
 * @abstract Stores and retrieves repository records for one actor.
 * @discussion Instances are scoped to a single actor database and are not safe to share across unrelated actors.
 */
@interface PDSRecordRepository : NSObject
```

Method:

```objc
/**
 * @abstract Loads the record at the supplied AT URI.
 * @param uri The canonical AT URI for the requested record.
 * @param error Receives validation or storage failures.
 * @return The decoded record dictionary, or nil when the record cannot be loaded.
 */
- (nullable NSDictionary *)recordForURI:(ATURI *)uri error:(NSError **)error;
```

Property:

```objc
/**
 * @abstract Maximum number of records returned by one query.
 */
@property (nonatomic, assign) NSUInteger limit;
```

Enum:

```objc
/**
 * @abstract Result states emitted by the repository commit pipeline.
 */
typedef NS_ENUM(NSInteger, PDSCommitState) {
    /** The commit has been accepted but not persisted. */
    PDSCommitStatePending,
    /** The commit was written to durable storage. */
    PDSCommitStateStored,
};
```

Error-returning API:

```objc
/**
 * @abstract Persists a blob reference for an actor record.
 * @param blob The validated blob metadata to persist.
 * @param error Receives database, quota, or validation failures.
 * @return YES when the reference is stored.
 */
- (BOOL)storeBlob:(PDSDatabaseBlob *)blob error:(NSError **)error;
```

## References

Read only the files needed for the task:

- [headerdoc-reference.md](references/headerdoc-reference.md): HeaderDoc formats, tags, and templates.
- [nullability-generics.md](references/nullability-generics.md): `NS_ASSUME_NONNULL`, nullable parameters, and lightweight generics.
- [special-annotations.md](references/special-annotations.md): Designated initializers, availability, and thread-safety annotations.
- [pragmas-markers.md](references/pragmas-markers.md): `MARK:`, TODO/FIXME/WARNING/NOTE, and formatting rules.
- [error-domain-documentation.md](references/error-domain-documentation.md): Error constants, enums, and usage examples.
- [style-rules.md](references/style-rules.md): Best practices, lint rules, and quick conversion patterns.
- [examples.md](references/examples.md): Before/after transformations.
- [rewrite-process-and-testing.md](references/rewrite-process-and-testing.md): Step-by-step rewrite process and validation checklist.
