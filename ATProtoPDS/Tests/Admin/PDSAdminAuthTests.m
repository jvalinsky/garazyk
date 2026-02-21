#import <XCTest/XCTest.h>
#import "Admin/PDSAdminAuth.h"
#import "App/PDSConfiguration.h"
#import "App/PDSController.h"
#import "Auth/JWT.h"

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

- (NSString *)expectedIssuer {
    NSString *configuredIssuer = [[NSProcessInfo processInfo] environment][@"PDS_ISSUER"];
    if ([configuredIssuer isKindOfClass:[NSString class]] && configuredIssuer.length > 0) {
        return configuredIssuer;
    }
    return @"https://pds.local:8443";
}

- (nullable NSString *)mintAdminTokenWithIssuer:(nullable NSString *)issuer
                                       audience:(nullable NSString *)audience
                                          scope:(NSString *)scope
                                          error:(NSError **)error {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSInteger issuedAt = (NSInteger)now;
    NSInteger expiresAt = issuedAt + 600;
    NSMutableDictionary *claims = [NSMutableDictionary dictionary];
    claims[@"sub"] = @"did:web:administrator.pds.example";
    claims[@"scope"] = scope ?: @"admin";
    if (issuer.length > 0) {
        claims[@"iss"] = issuer;
    }
    if (audience.length > 0) {
        claims[@"aud"] = audience;
    }
    claims[@"iat"] = @(issuedAt);
    claims[@"exp"] = @(expiresAt);

    PDSController *controller = [PDSController sharedController];
    return [controller.jwtMinter signPayload:claims error:error];
}

- (void)testAuthenticateWithPasswordSucceedsWithFallbackIssuer {
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
    XCTAssertNotNil(jwt.payload.iss, @"Should have an issuer");
    NSString *expectedIssuer = [[PDSConfiguration sharedConfiguration] canonicalIssuerWithPortHint:0];
    XCTAssertTrue([jwt.payload.iss hasPrefix:expectedIssuer], @"Fallback issuer should start with canonical issuer");
}

- (void)testAuthenticateWithPasswordUsesExplicitIssuer {
    [self setEnv:@"PDS_ADMIN_PASSWORD" value:@"secret-password"];
    [self setEnv:@"PDS_ISSUER" value:@"https://pds.local:8443"];
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
    [self setEnv:@"PDS_ISSUER" value:@"https://administrator.pds.example"];
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
    [self setEnv:@"PDS_ISSUER" value:@"https://administrator.pds.example"];
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
    [self setEnv:@"PDS_ISSUER" value:@"https://administrator.pds.example"];
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
    [self setEnv:@"PDS_ISSUER" value:@"https://administrator.pds.example"];

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

- (void)testIsAuthenticatedWithRequestRejectsTokenMissingIssuerClaim {
    [self setEnv:@"PDS_ISSUER" value:@"https://administrator.pds.example"];

    NSError *error = nil;
    NSString *token = [self mintAdminTokenWithIssuer:nil
                                             audience:[self expectedIssuer]
                                                scope:@"admin"
                                                error:&error];
    XCTAssertNotNil(token);
    XCTAssertNil(error);

    NSDictionary *bearerHeaders = @{@"Authorization": [NSString stringWithFormat:@"Bearer %@", token]};
    XCTAssertFalse([[PDSAdminAuth sharedAuth] isAuthenticatedWithRequest:bearerHeaders]);
}

- (void)testIsAuthenticatedWithRequestRejectsTokenMissingAudienceClaim {
    [self setEnv:@"PDS_ISSUER" value:@"https://administrator.pds.example"];

    NSError *error = nil;
    NSString *token = [self mintAdminTokenWithIssuer:[self expectedIssuer]
                                             audience:nil
                                                scope:@"admin"
                                                error:&error];
    XCTAssertNotNil(token);
    XCTAssertNil(error);

    NSDictionary *bearerHeaders = @{@"Authorization": [NSString stringWithFormat:@"Bearer %@", token]};
    XCTAssertFalse([[PDSAdminAuth sharedAuth] isAuthenticatedWithRequest:bearerHeaders]);
}

@end
