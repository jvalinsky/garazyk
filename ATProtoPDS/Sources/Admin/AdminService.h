/*!
 @file AdminService.h

 @abstract Admin service for account and moderation management.

 @discussion Provides administrative operations for account management,
 invite codes, and content moderation. Requires admin authentication.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for admin service. */
extern NSString * const AdminServiceErrorDomain;

/*!
 @enum AdminServiceError

 @abstract Error codes for admin operations.

 @constant AdminServiceErrorNotAuthorized Not authorized for operation.
 @constant AdminServiceErrorAccountNotFound Account does not exist.
 @constant AdminServiceErrorInvalidRequest Request parameters are invalid.
 @constant AdminServiceErrorDatabaseError Database operation failed.
 @constant AdminServiceErrorInviteCodeNotFound Invite code does not exist.
 @constant AdminServiceErrorSubjectNotFound Subject does not exist.
 */
typedef NS_ENUM(NSInteger, AdminServiceError) {
    AdminServiceErrorNotAuthorized = 1000,
    AdminServiceErrorAccountNotFound,
    AdminServiceErrorInvalidRequest,
    AdminServiceErrorDatabaseError,
    AdminServiceErrorInviteCodeNotFound,
    AdminServiceErrorSubjectNotFound
};

@class PDSDatabase;
@class PDSDatabaseAccount;

/*!
 @class AdminService

 @abstract Service for administrative operations.
 */
@interface AdminService : NSObject

- (instancetype)initWithDatabase:(PDSDatabase *)database;

/*! Gets account info by DID. */
- (nullable NSDictionary *)getAccountInfoForDid:(NSString *)did error:(NSError **)error;

/*! Gets account info for multiple DIDs. */
- (nullable NSArray<NSDictionary *> *)getAccountInfosForDids:(NSArray<NSString *> *)dids error:(NSError **)error;

/*! Updates an account's handle. */
- (nullable NSDictionary *)updateAccountHandle:(NSString *)did newHandle:(NSString *)handle error:(NSError **)error;

/*! Updates an account's email. */
- (nullable NSDictionary *)updateAccountEmail:(NSString *)did email:(NSString *)email error:(NSError **)error;

/*! Updates an account's password. */
- (nullable NSDictionary *)updateAccountPassword:(NSString *)did newPassword:(NSString *)password error:(NSError **)error;

/*! Enables invite generation for an account. */
- (nullable NSDictionary *)enableAccountInvites:(NSString *)did error:(NSError **)error;

/*! Disables invite generation for an account. */
- (nullable NSDictionary *)disableAccountInvites:(NSString *)did error:(NSError **)error;

/*! Lists invite codes with pagination. */
- (nullable NSArray<NSDictionary *> *)getInviteCodesWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error;

/*! Disables all invite codes for an account. */
- (nullable NSDictionary *)disableInviteCodesForAccount:(NSString *)did error:(NSError **)error;

/*! Gets moderation status of a subject. */
- (nullable NSDictionary *)getSubjectStatus:(NSString *)subject error:(NSError **)error;

/*! Updates moderation status of a subject. */
- (nullable NSDictionary *)updateSubjectStatus:(NSString *)subject takedown:(BOOL)takedown reason:(nullable NSString *)reason error:(NSError **)error;

/*! Sends an email to an account. */
- (nullable NSDictionary *)sendEmailToAccount:(NSString *)did subject:(NSString *)subject message:(NSString *)message error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
