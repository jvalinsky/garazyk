#import "RepoAuthXrpcTestBase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Admin/PDSAdminAuth.h"

@implementation RepoAuthXrpcTestBase

- (void)setUp {
    [super setUp];

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:self.tempURL.path];
    self.controller = app.legacyController;
    self.dispatcher = [[XrpcDispatcher alloc] init];
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher application:app];

    NSError *error = nil;
    NSDictionary *account1 = [self.controller createAccountForEmail:@"repoauth1@example.com"
                                                          password:@"password"
                                                            handle:@"repoauth1.test"
                                                               did:nil
                                                             error:&error];
    XCTAssertNil(error);
    self.did1 = account1[@"did"];

    NSDictionary *account2 = [self.controller createAccountForEmail:@"repoauth2@example.com"
                                                          password:@"password"
                                                            handle:@"repoauth2.test"
                                                               did:nil
                                                             error:&error];
    XCTAssertNil(error);
    self.did2 = account2[@"did"];

    NSDictionary *session = [self.controller loginWithHandle:@"repoauth1.test" password:@"password" error:&error];
    XCTAssertNil(error);
    self.accessJwt1 = session[@"accessJwt"];
    self.refreshJwt1 = session[@"refreshJwt"];
    XCTAssertNotNil(self.accessJwt1);
    XCTAssertNotNil(self.refreshJwt1);

    NSDictionary *adminAccount = [self.controller createAccountForEmail:@"adminrepo@example.com"
                                                               password:@"password"
                                                                 handle:@"administrator.repoauth.test"
                                                                    did:nil
                                                                  error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(adminAccount[@"did"]);

    setenv("PDS_ADMIN_PASSWORD", "password", 1);
    [PDSAdminAuth sharedAuth].dataDirectory = self.tempURL.path;
    [PDSAdminAuth sharedAuth].controller = self.controller;
    NSError *authError = nil;
    BOOL adminAuthSuccess = [[PDSAdminAuth sharedAuth] authenticateWithPassword:@"password" error:&authError];
    XCTAssertTrue(adminAuthSuccess, @"Admin authentication failed: %@", authError);
    self.adminAccessJwt = [PDSAdminAuth sharedAuth].adminToken;
    XCTAssertNotNil(self.adminAccessJwt);
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
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
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
                                 headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSMutableDictionary *allHeaders = [NSMutableDictionary dictionary];
    if (headers) {
        [allHeaders addEntriesFromDictionary:headers];
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:path
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:allHeaders
                                                          body:nil
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

- (HttpResponse *)sendGetRequestWithPath:(NSString *)path
                             queryParams:(NSDictionary<NSString *, NSString *> *)queryParams
                                 headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSMutableDictionary *allHeaders = [NSMutableDictionary dictionary];
    if (headers) {
        [allHeaders addEntriesFromDictionary:headers];
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:path
                                                   queryString:@""
                                                   queryParams:queryParams ?: @{}
                                                       version:@"1.1"
                                                       headers:allHeaders
                                                          body:nil
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

- (HttpResponse *)sendRawPostRequestWithPath:(NSString *)path
                                    bodyData:(NSData *)bodyData
                                     headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSMutableDictionary *allHeaders = [NSMutableDictionary dictionary];
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

- (nullable NSData *)drainResponseBody:(HttpResponse *)response error:(NSError **)error {
    if (response.bodyChunkProducer) {
        NSMutableData *buffer = [NSMutableData data];
        while (YES) {
            NSError *chunkError = nil;
            NSData *chunk = response.bodyChunkProducer(&chunkError);
            if (chunkError) {
                if (error) {
                    *error = chunkError;
                }
                return nil;
            }
            if (!chunk) {
                break;
            }
            [buffer appendData:chunk];
        }
        return [buffer copy];
    }

    return response.body;
}

@end
