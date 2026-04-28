## Apple HeaderDoc Reference

### Documentation Comment Formats

| Format | Usage | Xcode Quick Help |
|--------|-------|------------------|
| `/** ... */` | Multi-line documentation (Doxygen compatible) | ✅ Supported |
| `/*! ... */` | HeaderDoc style (Apple's original) | ✅ Supported |
| `///` | Single-line documentation | ✅ Supported |
| `//` | Regular inline comment | ❌ Not indexed |

**Use `/**` for new code** - Better Doxygen compatibility and broader tooling support.

**Use `/*!` for Apple-style** - Traditional HeaderDoc format used in Apple frameworks.

### HeaderDoc Tag Reference

| Tag | Purpose | Example |
|-----|---------|---------|
| `@header` | File-level documentation | `@header OAuth2.h` |
| `@abstract` | Brief one-line summary | `@abstract OAuth 2.0 with DPoP implementation` |
| `@discussion` | Detailed explanation | `@discussion Multi-paragraph details...` |
| `@class` | Class documentation | `@class OAuth2Server` |
| `@method` | Method documentation | `@method handleAuthorizationRequest:completion:` |
| `@enum` | Enumeration documentation | `@enum OAuth2Error` |
| `@typedef` | Type definition documentation | `@typedef OAuth2AuthorizationCompletion` |
| `@constant` | Constant/documentation | `@constant OAuth2ScopeIdentify` |
| `@property` | Property documentation | `@property (nonatomic, copy) NSString *issuer` |
| `@param` | Parameter description | `@param request The authorization request parameters.` |
| `@return` | Return value description | `@return The authorization code.` |
| `@result` | Return value (alternative) | `@result YES if successful` |
| `@see` | Cross-reference | `@see handleTokenRequest:completion:` |
| `@code` | Code example block | `@code ... @endcode` |
| `@warning` | Important caveats | `@warning Thread-unsafe method` |
| `@throws` | Exception documentation | `@throws NSInvalidArgumentException` |
| `@copyright` | Copyright notice | `@copyright Copyright (c) 2024 Jack Valinsky` |

### Header Block Template

```objc
/*!
 @header Filename.h

 @abstract Brief one-line summary of the file.

 @discussion Detailed explanation of the file's purpose,
 including:
 - What the module provides
 - Key classes and their relationships
 - Usage requirements and constraints

 @copyright Copyright (c) 2024 Jack Valinsky
 */
```

### Class Documentation Template

```objc
/*!
 @class ClassName

 @abstract Brief summary of the class purpose.

 @discussion Extended explanation of the class, its responsibilities,
 and how it fits into the overall architecture.

 @code
 // Example usage
 ClassName *instance = [[ClassName alloc] init];
 [instance doSomething];
 @endcode

 @see RelatedClass
 */
@interface ClassName : NSObject
@end
```

### Method Documentation Template

```objc
/*!
 @method methodName:param1:param2:

 @abstract One-line summary of what the method does.

 @discussion Detailed explanation including:
 - What the operation accomplishes
 - Preconditions and constraints
 - Side effects and state changes
 - Error conditions and how they're handled

 @param param1 Description of first parameter (constraints, required/optional).
 @param param2 Description of second parameter.
 @return Description of return value and error cases.
 @throws NSInvalidArgumentException If parameters are invalid.
 @see relatedMethod:
 */
- (ReturnType)methodName:(Param1Type)param1 param1:(Param2Type)param2;
```

### Property Documentation Template

```objc
/*! The issuer identifier for this server. */
@property (nonatomic, copy) NSString *issuer;

/*!
 @property issuer

 @abstract Property summary.

 @discussion Extended explanation of the property,
 including any threading or ownership considerations.
 */
@property (nonatomic, copy) NSString *issuer;
```

### Enum Documentation Template

```objc
/*!
 @enum ErrorCode

 @abstract Error codes for the operation.

 @constant ErrorCodeNone No error occurred.
 @constant ErrorCodeFailed The operation failed.
 */
typedef NS_ENUM(NSInteger, ErrorCode) {
    ErrorCodeNone = 0,
    ErrorCodeFailed = 1
};
```
