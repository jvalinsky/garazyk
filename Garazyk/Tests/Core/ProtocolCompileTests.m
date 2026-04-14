#import <XCTest/XCTest.h>
#import "Core/Repositories/PDSAccountRepository.h"
#import "Core/Repositories/PDSBlobRepository.h"
#import "Core/Repositories/PDSSessionRepository.h"
#import "App/Services/PDSAccountService.h"

// Mock class implementing PDSAccountRepository to verify protocol conformance
@interface MockAccountRepository : NSObject <PDSAccountRepository>
@end

@implementation MockAccountRepository
- (nullable PDSDatabaseAccount *)accountForDid:(nonnull NSString *)did error:(NSError *__autoreleasing  _Nullable * _Nullable)error { return nil; }
- (nullable PDSDatabaseAccount *)accountForEmail:(nonnull NSString *)email error:(NSError *__autoreleasing  _Nullable * _Nullable)error { return nil; }
- (nullable PDSDatabaseAccount *)accountForHandle:(nonnull NSString *)handle error:(NSError *__autoreleasing  _Nullable * _Nullable)error { return nil; }
- (BOOL)deleteAccount:(nonnull NSString *)did error:(NSError *__autoreleasing  _Nullable * _Nullable)error { return YES; }
- (nullable NSArray<PDSDatabaseAccount *> *)listAccountsWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError *__autoreleasing  _Nullable * _Nullable)error { return @[]; }
- (BOOL)saveAccount:(nonnull PDSDatabaseAccount *)account error:(NSError *__autoreleasing  _Nullable * _Nullable)error { return YES; }
@end

// Mock class implementing PDSAccountService protocol
@interface MockAccountService : NSObject <PDSAccountService>
@end

@implementation MockAccountService
- (nullable NSDictionary *)createAccountForEmail:(nonnull NSString *)email password:(nonnull NSString *)password handle:(nonnull NSString *)handle did:(nullable NSString *)did error:(NSError *__autoreleasing  _Nullable * _Nullable)error { return nil; }
- (BOOL)deleteAccount:(nonnull NSString *)did password:(nonnull NSString *)password error:(NSError *__autoreleasing  _Nullable * _Nullable)error { return YES; }
- (nullable NSDictionary *)getAccountForDid:(nonnull NSString *)did error:(NSError *__autoreleasing  _Nullable * _Nullable)error { return nil; }
- (nullable NSArray *)getAllAccountsWithError:(NSError *__autoreleasing  _Nullable * _Nullable)error { return @[]; }
- (nullable NSDictionary *)loginWithHandle:(nonnull NSString *)handle password:(nonnull NSString *)password error:(NSError *__autoreleasing  _Nullable * _Nullable)error { return nil; }
- (nullable NSDictionary *)loginWithIdentifier:(nonnull NSString *)identifier password:(nonnull NSString *)password error:(NSError *__autoreleasing  _Nullable * _Nullable)error { return nil; }
- (nullable NSDictionary *)refreshAccessToken:(nonnull NSString *)refreshToken error:(NSError *__autoreleasing  _Nullable * _Nullable)error { return nil; }
@end


@interface ProtocolCompileTests : XCTestCase
@end

@implementation ProtocolCompileTests

- (void)testProtocolsExist {
    XCTAssertTrue(@protocol(PDSAccountRepository) != nil);
    XCTAssertTrue(@protocol(PDSBlobRepository) != nil);
    XCTAssertTrue(@protocol(PDSSessionRepository) != nil);
    XCTAssertTrue(@protocol(PDSAccountService) != nil);
}

@end
