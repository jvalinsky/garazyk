// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;

@interface ChatAuthManager : NSObject

@property (nonatomic, copy) NSString *pdsUrl;

+ (instancetype)sharedManager;

/**
 * Validates the ATProto JWT in the Authorization header.
 * Resolves the DID and verifies the signature.
 */
- (nullable NSString *)authenticateRequest:(HttpRequest *)request
                                  response:(nullable HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END
