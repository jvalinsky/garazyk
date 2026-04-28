## Pragmas & Markers

### MARK: Comments

```objc
#pragma mark - Initialization

- (instancetype)init { ... }

#pragma mark - Public Methods

- (void)publicMethod { ... }

#pragma mark - Private Methods

- (void)privateMethod { ... }

#pragma mark - Constants

static const NSInteger kDefaultTimeout = 30;
```

### TODO:, FIXME:, WARNING:, NOTE:

```objc
// TODO: Implement rate limiting for this endpoint
// FIXME: Memory leak in high-load scenarios
// WARNING: This method is not thread-safe
// NOTE: The algorithm assumes sorted input
// FIXME: Handle edge case for empty strings (rdar://12345678)
```

### HeaderDoc Format

```objc
/*!
 @section Formatting Guide

 This section explains the formatting used in this header.

 @warning Do not call this method directly.

 @note This class is immutable after initialization.

 @see RelatedClass
 */
```
