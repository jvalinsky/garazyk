## Best Practices

### Document "Why", Not "What"

```objc
// ❌ BAD: States what the code does (redundant)
/* Check if username is empty */
if ([username length] == 0) {
    return NO;
}

// ✅ GOOD: Explains why the check exists
/* Reject empty usernames to prevent duplicate accounts */
if ([username length] == 0) {
    return NO;
}

// ❌ BAD: Explains what (code already shows this)
/* Sort the array using insertion sort */
[array sortUsingSelector:@selector(compare:)];

// ✅ GOOD: Explains why we need sorted data
/* Sort for binary search optimization */
[array sortUsingSelector:@selector(compare:)];
```

### Use @abstract for Summaries

```objc
/*!
 @abstract Creates an authenticated user session.

 @discussion Initializes a new session for the given username
 and password credentials.
 */
- (Session *)createSessionWithUsername:(NSString *)username
                              password:(NSString *)password;
```

### Use @discussion for Details

```objc
/*!
 @abstract Computes the Merkle Search Tree key depth.

 @discussion MST uses the SHA-256 hash of the key to determine
 the tree level. It counts leading zero 2-bit pairs in the hash,
 creating a probabilistic balanced tree structure where:
 - ~50% of keys land at level 0
 - ~25% at level 1
 - ~12.5% at level 2
 This distribution ensures efficient tree operations.

 @param key The key string to compute depth for.
 @return The depth (0-255), number of leading zero 2-bit pairs.
 */
+ (uint32_t)keyDepth:(NSString *)key;
```

### Include @code Examples

```objc
/*!
 @abstract Creates an OAuth2 authorization request.

 @code
 OAuth2AuthorizationRequest *request = [[OAuth2AuthorizationRequest alloc] init];
 request.clientID = @"com.example.app";
 request.redirectURI = @"https://example.com/callback";
 request.scope = @"identify email";

 NSURL *authURL = [request authorizationURL];
 // Redirect user to authURL
 @endcode

 @return The authorization URL to redirect the user to.
 */
- (NSURL *)authorizationURL;
```

### Cross-Reference with @see

```objc
/*!
 @abstract Verifies a JWT token.

 @discussion Validates the signature, expiration, and claims
 of the provided JWT. See JWTVerifier for detailed validation rules.

 @param jwt The token to verify.
 @param error On return, contains an error if verification failed.
 @return YES if valid, NO otherwise.

 @see JWT
 @see JWTHeader
 @see JWTPayload
 */
- (BOOL)verifyJWT:(JWT *)jwt error:(NSError **)error;
```

### Avoid Redundancy

```objc
/* ❌ BAD: Redundant comment repeats the code */
/* Get the user array count */
NSUInteger count = [userArray count];

/* ✅ GOOD: Comments explain non-obvious logic */
/* O(1) lookup - count cached during add/remove */
NSUInteger count = [userArray count];

/* ❌ BAD: Obvious documentation */
/* Set the name property to the value of nameParameter */
self.name = nameParameter;

/* ✅ GOOD: Comments explain intent or constraints */
/* Name is validated before assignment (see validateName:error:) */
self.name = nameParameter;
```

## Linter Rules

### Rule Set for HeaderDoc Compliance

| Rule | Severity | Description |
|------|----------|-------------|
| HDR001 | Error | Public API must have documentation comment |
| HDR002 | Error | `@param` must document all parameters |
| HDR003 | Error | Methods with non-void return must have `@return` |
| HDR004 | Warning | Include `@abstract` for all class/method docs |
| HDR005 | Warning | Include `@see` for related APIs |
| HDR006 | Warning | Use `/**` or `/*!` for documentation comments |
| HDR007 | Warning | Match parameter names in `@param` to signature |
| HDR008 | Warning | Use `@code` blocks for code examples |
| HDR009 | Info | Include `@throws` for throwing methods |
| HDR010 | Info | Document nullable parameters explicitly |

### Bad Patterns (Fail Linting)

```objc
// ❌ Missing documentation
- (NSString *)getValue;

// ❌ Incomplete documentation
/* Gets the value */
- (NSString *)getValue;

// ❌ Wrong parameter name
/*!
 @method getValueForKey:

 @param key1 The key to look up.  // Wrong name!
 @return The value.
 */
- (NSString *)getValueForKey:(NSString *)key;

// ❌ Missing return documentation
/*!
 @abstract Does something.

 @param input The input value.
 */
- (NSString *)processInput:(NSString *)input;
```

### Good Patterns (Pass Linting)

```objc
/*!
 @method getValue

 @abstract Retrieves the stored value.

 @discussion Returns the value previously set via setValue:,
 or nil if no value has been set.

 @return The stored value, or nil if not set.
 */
- (nullable NSString *)getValue;

/*!
 @method getValueForKey:

 @abstract Retrieves a value by key.

 @param key The key to look up (nonnull).
 @return The associated value, or nil if not found.
 */
- (nullable NSString *)getValueForKey:(NSString *)key;
```

## Quick Reference

### Remove/Replace Patterns

| Remove | Replace With |
|--------|-------------|
| "Let me..." | Direct statement of action |
| "I'll..." | Remove or rephrase as imperative |
| "First, let's..." | Sequence of steps or direct action |
| "Actually..." | Revised statement or remove |
| "Hmm, I wonder..." | Remove or replace with problem statement |
| "✅", "❌", "🚀", etc. | Remove entirely |
| "seamlessly", "powerful", "revolutionary" | Specific technical benefits |
| "just", "simply", "basically" | Remove or provide precise detail |
| "I think", "maybe", "perhaps" | State requirements or logic directly |
| "!)", ":)", ":(" | Remove entirely |

### Objective-C Specific Conversions

| Before (LLM) | After (HeaderDoc) |
|--------------|-------------------|
| `// This method does X` | `/*! @abstract Does X. */` |
| `// Get the user` | `/*! @return The user object. */` |
| `// We need to check if...` | `/*! Validates that... */` |
| `// 🚀 Create user now!` | `/*! Creates a new user. */` |
| `// Let me handle this...` | `/*! @abstract Handles the operation. */` |
