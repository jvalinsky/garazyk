/*!
 @file PDSLegacyAccountRepository.m
 @abstract Implementation of PDSAccountRepository wrapping PDSServiceDatabases.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import "PDSLegacyAccountRepository.h"
#import "Database/Service/ServiceDatabases.h"

NS_ASSUME_NONNULL_BEGIN

@implementation PDSLegacyAccountRepository {
    PDSServiceDatabases *_serviceDatabases;
}

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases {
    self = [super init];
    if (self) {
        _serviceDatabases = serviceDatabases;
    }
    return self;
}

#pragma mark - PDSAccountRepository

- (nullable PDSDatabaseAccount *)accountForDid:(NSString *)did error:(NSError **)error {
    return [_serviceDatabases getAccountByDid:did error:error];
}

- (nullable PDSDatabaseAccount *)accountForHandle:(NSString *)handle error:(NSError **)error {
    return [_serviceDatabases getAccountByHandle:handle error:error];
}

- (nullable PDSDatabaseAccount *)accountForEmail:(NSString *)email error:(NSError **)error {
    return [_serviceDatabases getAccountByEmail:email error:error];
}

- (BOOL)saveAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    // Check if account already exists to decide between create and update
    NSError *getErr = nil;
    PDSDatabaseAccount *existing = [_serviceDatabases getAccountByDid:account.did error:&getErr];
    
    if (existing) {
        return [_serviceDatabases updateAccount:account error:error];
    } else {
        return [_serviceDatabases createAccount:account error:error];
    }
}

- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error {
    return [_serviceDatabases deleteAccount:did error:error];
}

- (nullable NSArray<PDSDatabaseAccount *> *)listAccountsWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error {
    return [_serviceDatabases getAccountsWithLimit:limit cursor:cursor error:error];
}

@end

NS_ASSUME_NONNULL_END
