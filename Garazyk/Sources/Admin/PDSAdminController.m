/*!
 @file PDSAdminController.m

 @abstract Thin controller for administrative operations.

 @discussion PDSAdminController is a thin controller that delegates to PDSAdminService
 for all business logic. This class handles request parsing, validation, and response
 formatting only. All administrative operations are implemented in PDSAdminService.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PDSAdminController.h"
#import "Services/Core/PDSAdminService.h"

@interface PDSAdminController ()
@property (nonatomic, strong, readwrite) id<PDSAdminService> adminService;
@end

@implementation PDSAdminController

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

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

- (BOOL)deactivateAccount:(NSString *)did reason:(NSString *)reason error:(NSError **)error {
    if (!did || did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSAdminControllerErrorDomain"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID is required"}];
        }
        return NO;
    }
    return [_adminService deactivateAccount:did reason:reason error:error];
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

#pragma mark - Server Statistics

- (nullable NSDictionary *)getServerStatsWithError:(NSError **)error {
    return [_adminService getServerStatsWithError:error];
}

#pragma mark - Audit Logging

- (BOOL)logAdminAction:(NSString *)action
           subjectType:(nullable NSString *)subjectType
             subjectId:(nullable NSString *)subjectId
               details:(nullable NSDictionary *)details
              ipAddress:(nullable NSString *)ipAddress
               adminDid:(NSString *)adminDid
                  error:(NSError **)error {
    return [_adminService logAdminAction:action
                             subjectType:subjectType
                               subjectId:subjectId
                                 details:details
                                ipAddress:ipAddress
                                 adminDid:adminDid
                                    error:error];
}

- (nullable NSDictionary *)queryAuditLog:(NSDictionary *)filters
                                   limit:(NSInteger)limit
                                 cursor:(nullable NSString *)cursor
                                   error:(NSError **)error {
    return [_adminService queryAuditLog:filters limit:limit cursor:cursor error:error];
}

#pragma mark - Reports

- (nullable NSDictionary *)createReport:(NSDictionary *)params error:(NSError **)error {
    return [_adminService createReport:params error:error];
}

- (nullable NSDictionary *)queryReports:(NSDictionary *)filters
                                  limit:(NSInteger)limit
                                cursor:(nullable NSString *)cursor
                                  error:(NSError **)error {
    return [_adminService queryReports:filters limit:limit cursor:cursor error:error];
}

- (BOOL)resolveReport:(NSString *)reportId
               status:(NSString *)status
            resolvedBy:(nullable NSString *)resolvedBy
                notes:(nullable NSString *)notes
                error:(NSError **)error {
    return [_adminService resolveReport:reportId status:status resolvedBy:resolvedBy notes:notes error:error];
}

@end
