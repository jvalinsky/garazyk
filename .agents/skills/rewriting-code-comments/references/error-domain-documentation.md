## Error Domain Documentation

### Error Domain Constant

```objc
/*!
 @header Errors.h

 @abstract Error types for the network module.

 @discussion This header defines error codes and domain constants
 for network operations.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

extern NSString * const NetworkErrorDomain;
```

### Error Enum with Documentation

```objc
/*!
 @enum NetworkError

 @abstract Error codes for network operations.

 @constant NetworkErrorUnknown An unspecified error occurred.
 @constant NetworkErrorTimeout The request timed out.
 @constant NetworkErrorNoConnection No network connection available.
 @constant NetworkErrorInvalidResponse The server response was invalid.
 */
typedef NS_ENUM(NSInteger, NetworkError) {
    NetworkErrorUnknown = 1000,
    NetworkErrorTimeout,
    NetworkErrorNoConnection,
    NetworkErrorInvalidResponse
};
```

### Error Usage Example

```objc
NSError *error = nil;
id result = [self performOperation:&error];

if (!result) {
    if ([error.domain isEqualToString:NetworkErrorDomain]) {
        switch (error.code) {
            case NetworkErrorTimeout:
                // Handle timeout
                break;
            case NetworkErrorNoConnection:
                // Handle offline
                break;
            default:
                // Handle unknown error
                break;
        }
    }
}
```
