#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const AdminServiceErrorDomain;

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

@interface AdminService : NSObject

- (instancetype)initWithDatabase:(PDSDatabase *)database;

- (nullable NSDictionary *)getAccountInfoForDid:(NSString *)did error:(NSError **)error;
- (nullable NSArray<NSDictionary *> *)getAccountInfosForDids:(NSArray<NSString *> *)dids error:(NSError **)error;
- (nullable NSDictionary *)updateAccountHandle:(NSString *)did newHandle:(NSString *)handle error:(NSError **)error;
- (nullable NSDictionary *)updateAccountEmail:(NSString *)did email:(NSString *)email error:(NSError **)error;
- (nullable NSDictionary *)updateAccountPassword:(NSString *)did newPassword:(NSString *)password error:(NSError **)error;
- (nullable NSDictionary *)enableAccountInvites:(NSString *)did error:(NSError **)error;
- (nullable NSDictionary *)disableAccountInvites:(NSString *)did error:(NSError **)error;
- (nullable NSArray<NSDictionary *> *)getInviteCodesWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error;
- (nullable NSDictionary *)disableInviteCodesForAccount:(NSString *)did error:(NSError **)error;
- (nullable NSDictionary *)getSubjectStatus:(NSString *)subject error:(NSError **)error;
- (nullable NSDictionary *)updateSubjectStatus:(NSString *)subject takedown:(BOOL)takedown reason:(nullable NSString *)reason error:(NSError **)error;
- (nullable NSDictionary *)sendEmailToAccount:(NSString *)did subject:(NSString *)subject message:(NSString *)message error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
