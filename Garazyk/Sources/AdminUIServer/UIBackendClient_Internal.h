// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/UIBackendClient.h"
#import "Debug/GZLogger.h"

NS_ASSUME_NONNULL_BEGIN

@class UIServiceConfig;
@class ATProtoSafeHTTPClient;

@interface UIBackendClient ()

@property(nonatomic, strong) UIServiceConfig *configuration;
@property(nonatomic, strong, nullable) ATProtoSafeHTTPClient *httpClient;

- (NSURL *)URLByAppendingPath:(NSString *)path queryItems:(nullable id)queryItems baseURL:(NSURL *)baseURL;
- (NSDictionary *)performPDSRequestWithURL:(NSURL *)url method:(NSString *)method body:(nullable NSDictionary *)body statusCode:(nullable NSInteger *)statusCode error:(NSError **)error;
- (NSDictionary *)performJSONRequestWithURL:(NSURL *)url method:(NSString *)method body:(nullable NSDictionary *)body bearerToken:(nullable NSString *)token statusCode:(nullable NSInteger *)statusCode error:(NSError **)error;
- (NSData *)performRequestWithURL:(NSURL *)url method:(NSString *)method body:(nullable NSData *)body contentType:(nullable NSString *)contentType bearerToken:(nullable NSString *)token statusCode:(nullable NSInteger *)statusCode error:(NSError **)error;
- (NSData *)performStringRequestWithURL:(NSURL *)url method:(NSString *)method bearerToken:(nullable NSString *)token statusCode:(nullable NSInteger *)statusCode error:(NSError **)error;

- (NSArray<NSDictionary *> *)serviceProbeSpecifications;
- (NSString *)pathWithSegments:(NSArray<NSString *> *)segments;
- (NSDictionary *)probeServiceNamed:(NSString *)name
                            baseURL:(nullable NSURL *)baseURL
                           xrpcPath:(nullable NSString *)xrpcPath
                        bearerToken:(nullable NSString *)token;

@end

NS_ASSUME_NONNULL_END
