// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class UIServiceConfig;
@class HttpRequest;
@class HttpResponse;

NS_ASSUME_NONNULL_BEGIN

@interface UIServerRuntime : NSObject

@property(nonatomic, strong, readonly) UIServiceConfig *configuration;
@property(nonatomic, assign, readonly, getter=isRunning) BOOL running;

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration;
- (BOOL)startWithError:(NSError **)error;
- (void)stop;
- (HttpResponse *)dispatchRequestForTesting:(HttpRequest *)request;

@end

NS_ASSUME_NONNULL_END
