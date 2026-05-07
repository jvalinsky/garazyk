#import <XCTest/XCTest.h>
#import "App/PDSApplication.h"
#import "App/PDSController.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

@interface RepoAuthXrpcTestBase : XCTestCase

@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) PDSApplication *application;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, copy) NSString *did1;
@property (nonatomic, copy) NSString *did2;
@property (nonatomic, copy) NSString *accessJwt1;
@property (nonatomic, copy) NSString *refreshJwt1;
@property (nonatomic, copy) NSString *adminAccessJwt;

- (BOOL)requiresAdminAuthFixture;

- (PDSServiceDatabases *)serviceDatabases;

- (NSString *)iso8601String;

- (HttpResponse *)sendJsonRequestWithPath:(NSString *)path
                                     body:(NSDictionary *)body
                                  headers:(NSDictionary<NSString *, NSString *> *)headers;

- (HttpResponse *)sendGetRequestWithPath:(NSString *)path
                                 headers:(NSDictionary<NSString *, NSString *> *)headers;

- (HttpResponse *)sendGetRequestWithPath:(NSString *)path
                             queryParams:(NSDictionary<NSString *, NSString *> *)queryParams
                                 headers:(NSDictionary<NSString *, NSString *> *)headers;

- (HttpResponse *)sendRawPostRequestWithPath:(NSString *)path
                                    bodyData:(NSData *)bodyData
                                     headers:(NSDictionary<NSString *, NSString *> *)headers;

- (nullable NSData *)drainResponseBody:(HttpResponse *)response error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
