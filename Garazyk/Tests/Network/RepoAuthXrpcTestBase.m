#import "RepoAuthXrpcTestBase.h"
#import "App/PDSConfiguration.h"
#import "Database/Service/ServiceDatabases.h"
#import "Admin/PDSAdminAuth.h"

@interface PDSConfiguration (Test)
- (void)applyConfig:(NSDictionary *)config;
@end

@implementation RepoAuthXrpcTestBase

- (BOOL)requiresAdminAuthFixture {
    return NO;
}

- (void)setUp {
    [super setUp];

    setenv("PDS_AVAILABLE_USER_DOMAINS", "test", 1);
    setenv("PDS_ADMIN_PASSWORD", "password", 1);
    setenv("PDS_MASTER_SECRET", "test-master-secret-123", 1);
    setenv("PDS_PLC_URL", "mock", 1);
    [[PDSConfiguration sharedConfiguration] applyConfig:@{@"server": @{}}];

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:self.tempURL.path];
    self.application = app;
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

    if ([self requiresAdminAuthFixture]) {
        NSDictionary *adminAccount = [self.controller createAccountForEmail:@"adminrepo@example.com"
                                                                   password:@"password"
                                                                     handle:@"administrator.repoauth.test"
                                                                        did:nil
                                                                      error:&error];
        XCTAssertNil(error);
        XCTAssertNotNil(adminAccount[@"did"]);

        [PDSAdminAuth sharedAuth].dataDirectory = self.tempURL.path;
        [PDSAdminAuth sharedAuth].controller = self.controller;
        NSError *authError = nil;
        BOOL adminAuthSuccess = [[PDSAdminAuth sharedAuth] authenticateWithPassword:@"password" error:&authError];
        XCTAssertTrue(adminAuthSuccess, @"Admin authentication failed: %@", authError);
        self.adminAccessJwt = [PDSAdminAuth sharedAuth].adminToken;
        XCTAssertNotNil(self.adminAccessJwt);
    }
}

- (void)tearDown {
    // Stop the application to close database connections and release file descriptors
    [self.application stop];
    [PDSAdminAuth sharedAuth].controller = nil;
    self.controller = nil;
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

- (PDSServiceDatabases *)serviceDatabases {
    // PDSApplication's serviceDatabases is assigned to _serviceDatabases
    // Since we don't have a direct reference to the app in the base, 
    // we can get it from the controller if we added it there, 
    // but in RepoAuthXrpcTestBase.m setUp, it's not saved.
    // However, the controller has a reference to the application.
    return self.controller.application.serviceDatabases;
}

@end
