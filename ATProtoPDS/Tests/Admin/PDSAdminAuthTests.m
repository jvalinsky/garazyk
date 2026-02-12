#import <XCTest/XCTest.h>
#import "Admin/PDSAdminAuth.h"
#import "Auth/JWT.h"
#import "App/PDSController.h"
#include <stdlib.h>

@interface PDSAdminAuthTests : XCTestCase
@property (nonatomic, strong) NSDictionary<NSString *, id> *savedEnvValues;
@end

@implementation PDSAdminAuthTests

- (NSArray<NSString *> *)managedEnvKeys {
    return @[
        @"PDS_ADMIN_PASSWORD",
        @"PDS_ADMIN_PASSWORD_FILE",
        @"PDS_ISSUER",
        @"PDS_REQUIRE_ISSUER",
        @"PDS_ENV",
        @"PDS_ADMIN_TOKEN_TTL_SECONDS",
        @"PDS_DISABLE_X_ADMIN_TOKEN_HEADER"
    ];
}

- (void)setUp {
    [super setUp];

    NSMutableDictionary<NSString *, id> *saved = [NSMutableDictionary dictionary];
    for (NSString *key in [self managedEnvKeys]) {
        const char *value = getenv(key.UTF8String);
        if (value != NULL) {
            saved[key] = [NSString stringWithUTF8String:value];
        } else {
            saved[key] = [NSNull null];
        }
    }
    self.savedEnvValues = [saved copy];

    (void)[PDSController sharedController];
    [[PDSAdminAuth sharedAuth] logout];
}

- (void)tearDown {
    for (NSString *key in [self managedEnvKeys]) {
        id originalValue = self.savedEnvValues[key];
        if ([originalValue isKindOfClass:[NSString class]]) {
            setenv(key.UTF8String, [(NSString *)originalValue UTF8String], 1);
        } else {
            unsetenv(key.UTF8String);
        }
    }
    [[PDSAdminAuth sharedAuth] logout];
    [super tearDown];
}

- (void)setEnv:(NSString *)key value:(nullable NSString *)value {
    if (value.length > 0) {
        setenv(key.UTF8String, value.UTF8String, 1);
    } else {
        unsetenv(key.UTF8String);
    }
}

- (void)testAuthenticateWithPasswordSucceedsWithDefaultIssuer {
    [self setEnv:@"PDS_ADMIN_PASSWORD" value:@"secret-password"];
    [self setEnv:@"PDS_ISSUER" value:nil];
    [self setEnv:@"PDS_REQUIRE_ISSUER" value:nil];
    [self setEnv:@"PDS_ENV" value:nil];
    [self setEnv:@"PDS_ADMIN_TOKEN_TTL_SECONDS" value:nil];

    NSError *error = nil;
    BOOL success = [[PDSAdminAuth sharedAuth] authenticateWithPassword:@"secret-password" error:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);
    XCTAssertTrue([PDSAdminAuth sharedAuth].adminToken.length > 0);

    NSError *jwtError = nil;
    JWT *jwt = [JWT jwtWithToken:[PDSAdminAuth sharedAuth].adminToken error:&jwtError];
    XCTAssertNotNil(jwt);
    XCTAssertNil(jwtError);
    XCTAssertEqualObjects(jwt.payload.iss, @"https://pds.local:8443");
}

- (void)testAuthenticateWithPasswordFailsWhenIssuerRequiredButMissing {
    [self setEnv:@"PDS_ADMIN_PASSWORD" value:@"secret-password"];
    [self setEnv:@"PDS_ISSUER" value:nil];
    [self setEnv:@"PDS_REQUIRE_ISSUER" value:@"1"];
    [self setEnv:@"PDS_ENV" value:nil];

    NSError *error = nil;
    BOOL success = [[PDSAdminAuth sharedAuth] authenticateWithPassword:@"secret-password" error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 503);
    XCTAssertTrue([error.localizedDescription containsString:@"PDS_ISSUER"]);
}

- (void)testAuthenticateWithPasswordUsesConfiguredTokenTTL {
    [self setEnv:@"PDS_ADMIN_PASSWORD" value:@"secret-password"];
    [self setEnv:@"PDS_ISSUER" value:@"https://admin.pds.example"];
    [self setEnv:@"PDS_ADMIN_TOKEN_TTL_SECONDS" value:@"120"];

    NSError *error = nil;
    BOOL success = [[PDSAdminAuth sharedAuth] authenticateWithPassword:@"secret-password" error:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);

    NSError *jwtError = nil;
    JWT *jwt = [JWT jwtWithToken:[PDSAdminAuth sharedAuth].adminToken error:&jwtError];
    XCTAssertNotNil(jwt);
    XCTAssertNil(jwtError);

    NSTimeInterval ttlSeconds = [jwt.payload.exp timeIntervalSinceDate:jwt.payload.iat];
    XCTAssertGreaterThanOrEqual(ttlSeconds, 119.0);
    XCTAssertLessThanOrEqual(ttlSeconds, 121.0);
}

- (void)testIsAuthenticatedWithRequestRejectsXAdminTokenWhenDisabled {
    [self setEnv:@"PDS_ADMIN_PASSWORD" value:@"secret-password"];
    [self setEnv:@"PDS_ISSUER" value:@"https://admin.pds.example"];
    [self setEnv:@"PDS_DISABLE_X_ADMIN_TOKEN_HEADER" value:@"1"];

    NSError *error = nil;
    BOOL authenticated = [[PDSAdminAuth sharedAuth] authenticateWithPassword:@"secret-password" error:&error];
    XCTAssertTrue(authenticated);
    XCTAssertNil(error);

    NSString *token = [PDSAdminAuth sharedAuth].adminToken;
    NSDictionary *xAdminTokenOnlyHeaders = @{@"X-Admin-Token": token};
    XCTAssertFalse([[PDSAdminAuth sharedAuth] isAuthenticatedWithRequest:xAdminTokenOnlyHeaders]);

    NSDictionary *bearerHeaders = @{@"Authorization": [NSString stringWithFormat:@"Bearer %@", token]};
    XCTAssertTrue([[PDSAdminAuth sharedAuth] isAuthenticatedWithRequest:bearerHeaders]);
}

- (void)testIsAuthenticatedWithRequestAllowsXAdminTokenByDefault {
    [self setEnv:@"PDS_ADMIN_PASSWORD" value:@"secret-password"];
    [self setEnv:@"PDS_ISSUER" value:@"https://admin.pds.example"];
    [self setEnv:@"PDS_DISABLE_X_ADMIN_TOKEN_HEADER" value:nil];

    NSError *error = nil;
    BOOL authenticated = [[PDSAdminAuth sharedAuth] authenticateWithPassword:@"secret-password" error:&error];
    XCTAssertTrue(authenticated);
    XCTAssertNil(error);

    NSString *token = [PDSAdminAuth sharedAuth].adminToken;
    NSDictionary *xAdminTokenOnlyHeaders = @{@"x-admin-token": token};
    XCTAssertTrue([[PDSAdminAuth sharedAuth] isAuthenticatedWithRequest:xAdminTokenOnlyHeaders]);
}

- (void)testLogoutInvalidatesPreviouslyMintedAdminToken {
    [self setEnv:@"PDS_ADMIN_PASSWORD" value:@"secret-password"];
    [self setEnv:@"PDS_ISSUER" value:@"https://admin.pds.example"];

    NSError *error = nil;
    BOOL authenticated = [[PDSAdminAuth sharedAuth] authenticateWithPassword:@"secret-password" error:&error];
    XCTAssertTrue(authenticated);
    XCTAssertNil(error);

    NSString *token = [PDSAdminAuth sharedAuth].adminToken;
    NSDictionary *bearerHeaders = @{@"Authorization": [NSString stringWithFormat:@"Bearer %@", token]};
    XCTAssertTrue([[PDSAdminAuth sharedAuth] isAuthenticatedWithRequest:bearerHeaders]);

    [[PDSAdminAuth sharedAuth] logout];
    XCTAssertNil([PDSAdminAuth sharedAuth].adminToken);
    XCTAssertFalse([[PDSAdminAuth sharedAuth] isAuthenticatedWithRequest:bearerHeaders]);
}

@end
