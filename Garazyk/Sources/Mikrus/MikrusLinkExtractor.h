// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file MikrusLinkExtractor.h

 @abstract Extracts link-like scalar values and JSON paths from ATProto records.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MikrusLinkExtractor : NSObject

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)linkEntriesInRecord:(NSDictionary *)record;
+ (NSArray<NSString *> *)subjectsInRecord:(NSDictionary *)record path:(NSString *)path;
+ (BOOL)isLinkSubject:(NSString *)value;

@end

NS_ASSUME_NONNULL_END
