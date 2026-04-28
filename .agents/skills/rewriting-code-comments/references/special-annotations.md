## Special Annotations

### Designated Initializers

```objc
@interface Session : NSObject

/*! The session token. */
@property (nonatomic, copy, readonly) NSString *token;

/*!
 @abstract Creates an authenticated session.

 @discussion This is the designated initializer for Session.
 All other initializers should delegate to this method.

 @param token The authentication token (nonnull, must be valid JWT).
 @return An initialized session.
 */
- (instancetype)initWithToken:(NSString *)token NS_DESIGNATED_INITIALIZER;

/*! Unavailable - use initWithToken: instead. */
- (instancetype)init NS_UNAVAILABLE;

@end
```

### Availability Macros

```objc
/*!
 @method performModernOperation

 @abstract Performs the modern operation.

 @discussion Available on macOS 10.15+ and iOS 13.0+.
 On older platforms, use performLegacyOperation instead.

 @return The operation result.
 @code
 // Check availability before calling
 if (@available(macOS 10.15, *)) {
     [self performModernOperation];
 }
 @endcode
 */
- (id)performModernOperation API_AVAILABLE(macos(10.15), ios(13.0));

/*!
 @method deprecatedMethod

 @abstract Deprecated method.

 @discussion Use newMethod instead. This method will be removed
 in a future version.

 @warning Deprecated: Use newMethod instead.
 */
- (void)deprecatedMethod API_DEPRECATED("Use newMethod instead", macos(10.12, 10.15));
```

### Thread Safety Annotations

```objc
NS_LOCKABLE

@interface ThreadUnsafeClass : NSObject

/*!
 @method updateState

 @abstract Updates the internal state.

 @warning Not thread-safe. Must be called from the serial queue
 specified in queue property.
 */
- (void)updateState;

/*! The dispatch queue for thread-safe access. */
@property (nonatomic, strong) dispatch_queue_t queue;

@end
```

### Synchronized Documentation

```objc
/*!
 @method updateCounter

 @abstract Increments the counter.

 @discussion Uses @synchronized(self) for thread safety.
 Consider using a dedicated lock object for better performance
 in performance-critical code.

 @return The new counter value.
 */
- (NSUInteger)updateCounter {
    @synchronized (self) {
        _counter++;
        return _counter;
    }
}
```
