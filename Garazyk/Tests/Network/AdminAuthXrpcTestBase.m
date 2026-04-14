#import "AdminAuthXrpcTestBase.h"
#import "Admin/PDSAdminAuth.h"

@implementation AdminAuthXrpcTestBase

- (void)setUp {
    [super setUp];

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];

    self.application = [[PDSApplication alloc] initWithDataDirectory:self.tempURL.path];
    self.dispatcher = [[XrpcDispatcher alloc] init];
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher application:self.application];

    NSError *error = nil;
    NSDictionary *adminAccount = [self.application.legacyController createAccountForEmail:@"admin-app@example.com"
                                                                                  password:@"password"
                                                                                    handle:@"administrator.app.test"
                                                                                       did:nil
                                                                                     error:&error];
    XCTAssertNil(error);

    setenv("PDS_ADMIN_PASSWORD", "password", 1);
    NSError *adminAuthError = nil;
    BOOL adminAuthSuccess = [[PDSAdminAuth sharedAuth] authenticateWithPassword:@"password" error:&adminAuthError];
    XCTAssertTrue(adminAuthSuccess);
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
    XCTAssertNil(error);
    self.userDid = userAccount[@"did"];
    self.userJwt = userAccount[@"accessJwt"];
    XCTAssertTrue(self.userDid.length > 0);
    XCTAssertTrue(self.userJwt.length > 0);
}

- (void)tearDown {
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
