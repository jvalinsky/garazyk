## Nullability & Generics

### NS_ASSUME_NONNULL Patterns

```objc
NS_ASSUME_NONNULL_BEGIN

@interface MyClass : NSObject

/*! The user identifier. */
@property (nonatomic, copy) NSString *userID;

/*! The user's email, or nil if not provided. */
@property (nonatomic, copy, nullable) NSString *email;

/*!
 @method fetchUserWithID:completion:

 @abstract Retrieves a user by ID.

 @param userID The unique identifier (nonnull).
 @param completion Callback with user or error (nullable).
 */
- (void)fetchUserWithID:(NSString *)userID
             completion:(void (^)(User * _Nullable user, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
```

### Nullable/Nonnull Parameter Documentation

```objc
/*!
 @method createSessionWithToken:userID:

 @abstract Creates a new session.

 @param token The authentication token (nonnull, nonempty required).
 @param userID The user identifier (nonnull).
 @return The created session, or nil if creation failed.
 */
- (nullable Session *)createSessionWithToken:(NSString *)token
                                      userID:(NSString *)userID;
```

### Generic Type Documentation

```objc
/*! An array of resolved DIDs. */
@property (nonatomic, copy) NSArray<NSString *> *resolvedDIDs;

/*! Mapping of handles to DIDs. */
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *handleToDIDMap;
```
