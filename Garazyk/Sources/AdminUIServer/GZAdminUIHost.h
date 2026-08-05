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
 * @discussion Holds no compile-time knowledge of any service. Route registration is supplied
 * entirely by the @c packs the caller composes it with; see @c GZAdminUIPack.
 */
@interface GZAdminUIHost : NSObject <GZServiceRuntimeProtocol>

@property(nonatomic, strong, readonly) UIServiceConfig *configuration;
@property(nonatomic, copy, readonly) NSArray<Class> *packs;
@property(nonatomic, assign, readonly, getter=isRunning) BOOL running;

/**
 * @abstract Composes a host from configuration and the packs it should serve.
 * @param packs Classes conforming to @c GZAdminUIPack, registered in the order given.
 */
- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration
                                 packs:(NSArray<Class> *)packs NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
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
