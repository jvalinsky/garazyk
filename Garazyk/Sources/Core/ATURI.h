// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  ATURI.h
//  ATProtoPDS
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ATURIErrorDomain;

/**
 * @abstract Declares the ATURI public API.
 */
@interface ATURI : NSObject

/**
 * @abstract Exposes the uri string value.
 */
@property (nonatomic, copy, readonly) NSString *uriString;
@property (nonatomic, copy, readonly) NSString *did;
@property (nonatomic, copy, readonly) NSString *collection;
@property (nonatomic, copy, readonly) NSString *rkey;

/**
 * @abstract Performs the uriWithString operation.
 */
+ (nullable instancetype)uriWithString:(NSString *)string error:(NSError **)error;
/**
 * @abstract Returns the operation result.
 */
- (instancetype)init NS_UNAVAILABLE;

@end

/**
 * @abstract Declares the ATDID public API.
 */
@interface ATDID : NSObject

/**
 * @abstract Exposes the did string value.
 */
@property (nonatomic, copy, readonly) NSString *didString;
@property (nonatomic, copy, readonly) NSString *method;
@property (nonatomic, copy, readonly) NSString *identifier;

/**
 * @abstract Performs the didWithString operation.
 */
+ (nullable instancetype)didWithString:(NSString *)string error:(NSError **)error;
/**
 * @abstract Returns the operation result.
 */
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
