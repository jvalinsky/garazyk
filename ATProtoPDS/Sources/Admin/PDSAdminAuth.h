#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @header PDSAdminAuth.h
 
 @abstract Admin authentication middleware.
 
 @discussion This header defines the PDSAdminAuth class for handling
 admin-level authentication for PDS management operations.
 
 @copyright Copyright (c) 2024 Jack Valinsky
 */

/*!
 @class PDSAdminAuth
 
 @abstract Handles admin authentication for PDS management.
 
 @discussion PDSAdminAuth provides authentication for admin API endpoints
 and management operations. It uses a shared token or password-based
 authentication to verify admin privileges.
 
 @code
 PDSAdminAuth *auth = [PDSAdminAuth sharedAuth];
 
 if ([auth authenticateWithPassword:@"adminpassword" error:nil]) {
     // Admin authenticated
 }
 @endcode
 */
@interface PDSAdminAuth : NSObject

/*!
 @method sharedAuth
 
 @abstract Returns the shared admin auth instance.
 
 @return The singleton PDSAdminAuth instance.
 */
+ (instancetype)sharedAuth;

/*!
 @method isAuthenticatedWithRequest:
 
 @abstract Checks if the request contains valid admin credentials.
 
 @param request The request object to check.
 @return YES if the request is authenticated as admin.
 */
- (BOOL)isAuthenticatedWithRequest:(NSObject *)request;

/*!
 @method authenticateWithPassword:error:
 
 @abstract Authenticates with an admin password.
 
 @param password The admin password to verify.
 @param error On return, contains an error if authentication failed.
 @return YES if authentication succeeded, NO otherwise.
 */
- (BOOL)authenticateWithPassword:(NSString *)password error:(NSError **)error;

/*!
 @method logout
 
 @abstract Clears the current admin session.
 */
- (void)logout;

/*! The current admin token, if authenticated. */
@property (nonatomic, copy, nullable) NSString *adminToken;

@end

NS_ASSUME_NONNULL_END
