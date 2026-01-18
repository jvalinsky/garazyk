/*!
 @file PDSAdminController.m

 @abstract Implementation of administrative operations controller.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PDSAdminController.h"
#import "../Database/Service/ServiceDatabases.h"
#import "../Database/PDSDatabase.h"
#import "../App/Services/PDSAccountService.h"
#import "../Debug/PDSLogger.h"
#import "../Core/NSDateFormatter+ATProto.h"

@implementation PDSAdminController

#pragma mark - Initialization

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                          accountService:(nullable id<PDSAccountService>)accountService {
    self = [super init];
    if (self) {
        _serviceDatabases = serviceDatabases;
        _accountService = accountService;
    }
    return self;
}

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases {
    return [self initWithServiceDatabases:serviceDatabases accountService:nil];
}

#pragma mark - Private Helpers

- (nullable PDSDatabase *)serviceDatabaseWithError:(NSError **)error {
    return [_serviceDatabases serviceDatabaseWithError:error];
}

#pragma mark - Account Administration

- (nullable NSArray *)getAllAccountsWithError:(NSError **)error {
    if (_accountService) {
        return [_accountService getAllAccountsWithError:error];
    }
    
    // Fallback: direct database query if no account service
    PDSDatabase *db = [self serviceDatabaseWithError:error];
    if (!db) return nil;
    
    return [db getAllAccountsWithError:error];
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
    
    PDSDatabase *db = [self serviceDatabaseWithError:error];
    if (!db) return NO;
    
    PDS_LOG_INFO(@"Taking down account: %@ reason: %@", did, reason);
    
    // Use generic reference/reason if simplified
    return [db takeDownAccount:did reason:reason takedownRef:nil error:error];
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
    
    PDSDatabase *db = [self serviceDatabaseWithError:error];
    if (!db) return NO;
    
    PDS_LOG_INFO(@"Reinstating account: %@", did);
    
    return [db reinstateAccount:did error:error];
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
    
    PDSDatabase *db = [self serviceDatabaseWithError:error];
    if (!db) return NO;
    
    return [db isAccountTakedownActive:did error:error];
}

#pragma mark - Moderation

- (NSDictionary *)moderateAccount:(NSDictionary *)params error:(NSError **)error {
    // Stub implementation: Log the moderation action but return success
    // TODO: Implement full moderation logic
    PDS_LOG_INFO(@"Moderating account: %@", params);
    
    NSString *did = params[@"did"];
    NSString *action = params[@"action"];
    
    if (!did || !action) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSAdminControllerErrorDomain"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required fields: did, action"}];
        }
        return @{@"status": @"error", @"message": @"Missing required fields"};
    }
    
    return @{
        @"status": @"success",
        @"did": did,
        @"action": action,
        @"timestamp": [NSDateFormatter atproto_stringFromDate:[NSDate date]]
    };
}

- (NSDictionary *)moderateRecord:(NSDictionary *)params error:(NSError **)error {
    // Stub implementation: Log the moderation action but return success
    // TODO: Implement full moderation logic
    PDS_LOG_INFO(@"Moderating record: %@", params);
    
    NSString *uri = params[@"uri"];
    NSString *action = params[@"action"];
    
    if (!uri || !action) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSAdminControllerErrorDomain"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required fields: uri, action"}];
        }
        return @{@"status": @"error", @"message": @"Missing required fields"};
    }
    
    return @{
        @"status": @"success",
        @"uri": uri,
        @"action": action,
        @"timestamp": [NSDateFormatter atproto_stringFromDate:[NSDate date]]
    };
}

#pragma mark - Labeling

- (nullable NSDictionary *)createLabel:(NSDictionary *)params error:(NSError **)error {
    PDSDatabase *db = [self serviceDatabaseWithError:error];
    if (!db) return nil;
    
    // Validate required fields
    NSString *uri = params[@"uri"];
    NSString *val = params[@"val"];
    
    if (!uri || !val) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSAdminControllerErrorDomain"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required fields: uri, val"}];
        }
        return nil;
    }
    
    PDS_LOG_INFO(@"Creating label: uri=%@ val=%@", uri, val);
    
    if ([db createLabel:params error:error]) {
        return @{
            @"src": params[@"src"] ?: [NSNull null],
            @"uri": params[@"uri"] ?: [NSNull null],
            @"val": params[@"val"] ?: [NSNull null],
            @"cts": params[@"cts"] ?: [NSDateFormatter atproto_stringFromDate:[NSDate date]]
        };
    }
    return nil;
}

- (nullable NSDictionary *)getLabels:(NSDictionary *)params error:(NSError **)error {
    PDSDatabase *db = [self serviceDatabaseWithError:error];
    if (!db) return nil;
    
    NSArray *uriPatterns = params[@"uriPatterns"];
    NSArray *sources = params[@"sources"];
    NSInteger limit = [params[@"limit"] integerValue];
    if (limit <= 0) limit = 10;
    NSString *cursor = params[@"cursor"];
    
    NSArray *labels = [db getLabelsWithPatterns:uriPatterns sources:sources limit:limit cursor:cursor error:error];
    if (!labels) return nil;
    
    return @{
        @"labels": labels,
        @"cursor": (labels.count > 0) ? [NSString stringWithFormat:@"%@", labels.lastObject[@"id"]] : [NSNull null]
    };
}

@end