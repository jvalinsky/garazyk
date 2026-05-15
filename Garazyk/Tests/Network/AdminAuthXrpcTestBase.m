// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminAuthXrpcTestBase.h"
#import "Admin/PDSAdminAuth.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Database/Service/ServiceDatabases.h"

@interface ATProtoServiceConfiguration (Test)
- (void)applyConfig:(NSDictionary *)config;
@end

@implementation AdminAuthXrpcTestBase

- (void)setUp {
    [super setUp];

    // Clear any proxy/upstream env vars that would cause PDSApplication
    // to try connecting to external services during tests
    unsetenv("PDS_APPVIEW_URL");
    unsetenv("PDS_CHAT_URL");
    unsetenv("PDS_ISSUER");

    // Set required environment variables before creating PDSApplication
    // (matching RepoAuthXrpcTestBase setup which works correctly)
    setenv("PDS_AVAILABLE_USER_DOMAINS", "test", 1);
    setenv("PDS_ADMIN_PASSWORD", "password", 1);
    setenv("PDS_MASTER_SECRET", "test-master-secret-123", 1);
    setenv("PDS_PLC_URL", "mock", 1);
    [[ATProtoServiceConfiguration sharedConfiguration] applyConfig:@{@"server": @{}}];

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSError *dirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:&dirError];
    XCTAssertNil(dirError, @"Failed to create temp directory: %@", dirError);

    self.application = [[PDSApplication alloc] initWithDataDirectory:self.tempURL.path];
    self.dispatcher = [[XrpcDispatcher alloc] init];
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher application:self.application];

    NSError *error = nil;
    NSDictionary *adminAccount = [self.application.legacyController createAccountForEmail:@"admin-app@example.com"
                                                                                  password:@"password"
                                                                                    handle:@"administrator.app.test"
                                                                                       did:nil
                                                                                     error:&error];
    XCTAssertNil(error, @"Failed to create admin account: %@", error);

    NSError *adminAuthError = nil;
    [PDSAdminAuth sharedAuth].dataDirectory = self.tempURL.path;
    [PDSAdminAuth sharedAuth].controller = self.application.legacyController;
    BOOL adminAuthSuccess = [[PDSAdminAuth sharedAuth] authenticateWithPassword:@"password" error:&adminAuthError];
    XCTAssertTrue(adminAuthSuccess, @"Admin authentication failed: %@", adminAuthError);
    XCTAssertNil(adminAuthError);
    self.adminJwt = [PDSAdminAuth sharedAuth].adminToken;
    XCTAssertTrue(self.adminJwt.length > 0);
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    XCTAssertTrue([[PDSAdminAuth sharedAuth] isAuthenticatedWithRequest:@{@"authorization": adminAuthHeader}]);

    NSDictionary *userAccount = [self.application.legacyController createAccountForEmail:@"user-app@example.com"
                                                                                 password:@"password"
                                                                                   handle:@"user.app.test"
                                                                                      did:nil
                                                                                    error:&error];
    XCTAssertNil(error, @"Failed to create user account: %@", error);
    self.userDid = userAccount[@"did"];
    self.userJwt = userAccount[@"accessJwt"];
    XCTAssertTrue(self.userDid.length > 0, @"userDid should not be nil");
    XCTAssertTrue(self.userJwt.length > 0, @"userJwt should not be nil");
}

- (void)tearDown {
    [self.application stop];
    [PDSAdminAuth sharedAuth].dataDirectory = nil;
    [PDSAdminAuth sharedAuth].controller = nil;
    self.dispatcher = nil;
    self.application = nil;
    [[NSFileManager defaultManager] removeItemAtURL:self.tempURL error:nil];
    [super tearDown];
}

- (NSString *)iso8601String {
    if (@available(macOS 10.12, iOS 10.0, *)) {
        NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        return [formatter stringFromDate:[NSDate date]];
    }
    return [[NSDate date] description];
}

- (HttpResponse *)sendJsonRequestWithPath:(NSString *)path
                                     body:(NSDictionary *)body
                                  headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body ?: @{} options:0 error:nil];
    NSMutableDictionary *allHeaders = [@{@"content-type": @"application/json"} mutableCopy];
    if (headers) {
        [allHeaders addEntriesFromDictionary:headers];
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:path
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:allHeaders
                                                          body:bodyData
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

- (HttpResponse *)sendGetRequestWithPath:(NSString *)path
                              queryString:(NSString *)queryString
                              queryParams:(NSDictionary<NSString *, NSString *> *)queryParams
                                  headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSMutableDictionary *allHeaders = [NSMutableDictionary dictionary];
    if (headers) {
        [allHeaders addEntriesFromDictionary:headers];
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:path
                                                   queryString:queryString ?: @""
                                                   queryParams:queryParams ?: @{}
                                                       version:@"1.1"
                                                       headers:allHeaders
                                                          body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

@end
