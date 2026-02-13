/*!
 @file PDSAdminController.m

 @abstract Thin controller for administrative operations.

 @discussion PDSAdminController is a thin controller that delegates to PDSAdminService
 for all business logic. This class handles request parsing, validation, and response
 formatting only. All administrative operations are implemented in PDSAdminService.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PDSAdminController.h"
#import "Services/PDSAdminService.h"

@interface PDSAdminController ()
@property (nonatomic, strong, readwrite) id<PDSAdminService> adminService;
@end

@implementation PDSAdminController

#pragma mark - Initialization

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                          accountService:(nullable id<PDSAccountService>)accountService {
    self = [super init];
    if (self) {
        PDSAdminService *service = [[PDSAdminService alloc] initWithServiceDatabases:serviceDatabases
                                                                       accountService:accountService];
        if (!service) {
            return nil;
        }
        _adminService = service;
    }
    return self;
}

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases {
    return [self initWithServiceDatabases:serviceDatabases accountService:nil];
}

- (instancetype)initWithAdminService:(id<PDSAdminService>)adminService {
    self = [super init];
    if (self) {
        _adminService = adminService;
    }
    return self;
}

#pragma mark - Account Administration

- (nullable NSArray *)getAllAccountsWithError:(NSError **)error {
    return [_adminService getAllAccountsWithError:error];
}

- (BOOL)takeDownAccount:(NSString *)did reason:(NSString *)reason error:(NSError **)error {
    if (!did || did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSAdminControllerErrorDomain"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID is required"}];
        }
        return NO;
    }
    return [_adminService takeDownAccount:did reason:reason error:error];
}

- (BOOL)reinstateAccount:(NSString *)did error:(NSError **)error {
    if (!did || did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSAdminControllerErrorDomain"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID is required"}];
        }
        return NO;
    }
    return [_adminService reinstateAccount:did error:error];
}

- (BOOL)isAccountTakedownActive:(NSString *)did error:(NSError **)error {
    if (!did || did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSAdminControllerErrorDomain"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID is required"}];
        }
        return NO;
    }
    return [_adminService isAccountTakedownActive:did error:error];
}

- (BOOL)disableInviteCodesWithCodes:(nullable NSArray<NSString *> *)codes
                           accounts:(nullable NSArray<NSString *> *)accounts
                              error:(NSError **)error {
    return [_adminService disableInviteCodesWithCodes:codes accounts:accounts error:error];
}

#pragma mark - Moderation

- (NSDictionary *)moderateAccount:(NSDictionary *)params error:(NSError **)error {
    return [_adminService moderateAccount:params error:error];
}

- (NSDictionary *)moderateRecord:(NSDictionary *)params error:(NSError **)error {
    return [_adminService moderateRecord:params error:error];
}

#pragma mark - Labeling

- (nullable NSDictionary *)createLabel:(NSDictionary *)params error:(NSError **)error {
    return [_adminService createLabel:params error:error];
}

- (nullable NSDictionary *)getLabels:(NSDictionary *)params error:(NSError **)error {
    return [_adminService getLabels:params error:error];
}

@end
