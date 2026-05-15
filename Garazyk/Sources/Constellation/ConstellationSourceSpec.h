// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ConstellationSourceSpec.h

 @abstract Parser for Microcosm Constellation link source strings.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const ConstellationSourceSpecErrorDomain;

@interface ConstellationSourceSpec : NSObject

@property (nonatomic, copy, readonly) NSString *collection;
@property (nonatomic, copy, readonly) NSString *path;

+ (nullable instancetype)sourceSpecWithString:(NSString *)source error:(NSError **)error;
+ (BOOL)validatePath:(NSString *)path error:(NSError **)error;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
