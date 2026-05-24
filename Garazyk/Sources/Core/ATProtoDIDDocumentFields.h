// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

@class DIDDocument;

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoDIDDocumentFields : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (nullable NSString *)normalizedHandleFromDocument:(DIDDocument *)document;
+ (nullable NSString *)pdsEndpointFromDocument:(DIDDocument *)document;
+ (nullable NSString *)atprotoSigningKeyMultibaseFromDocument:(DIDDocument *)document;

@end

NS_ASSUME_NONNULL_END
