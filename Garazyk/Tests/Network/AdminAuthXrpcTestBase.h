// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/PDSApplication.h"
#import "App/PDSController.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "PDSHttpTestUtilities.h"

NS_ASSUME_NONNULL_BEGIN

@interface AdminAuthXrpcTestBase : XCTestCase

@property (nonatomic, strong) PDSApplication *application;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, copy) NSString *adminJwt;
@property (nonatomic, copy) NSString *userDid;
@property (nonatomic, copy) NSString *userJwt;

- (NSString *)iso8601String;

- (HttpResponse *)sendJsonRequestWithPath:(NSString *)path
                                     body:(NSDictionary *)body
                                  headers:(NSDictionary<NSString *, NSString *> *)headers;

- (HttpResponse *)sendGetRequestWithPath:(NSString *)path
                             queryString:(NSString *)queryString
                             queryParams:(NSDictionary<NSString *, NSString *> *)queryParams
                                 headers:(NSDictionary<NSString *, NSString *> *)headers;

@end

NS_ASSUME_NONNULL_END
