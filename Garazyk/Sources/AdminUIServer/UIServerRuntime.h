// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Runtime/GZServiceLifecycle.h"

@class UIServiceConfig;
@class HttpRequest;
@class HttpResponse;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Runs the Admin UI HTTP service lifecycle.
 */
@interface UIServerRuntime : NSObject <GZServiceRuntimeProtocol>

@property(nonatomic, strong, readonly) UIServiceConfig *configuration;
@property(nonatomic, assign, readonly, getter=isRunning) BOOL running;

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration;
- (BOOL)startWithError:(NSError **)error;
- (void)stop;
/**
 * @abstract Dispatch request for testing.
 * @param request HTTP request to authenticate or dispatch.
 * @return Result produced by the operation.
 */
- (HttpResponse *)dispatchRequestForTesting:(HttpRequest *)request;

@end

NS_ASSUME_NONNULL_END
