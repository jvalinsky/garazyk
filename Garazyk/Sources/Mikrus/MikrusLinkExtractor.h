// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file MikrusLinkExtractor.h
 * @abstract Extracts link-like scalar values and JSON paths from ATProto records.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Utility for extracting link subjects and metadata from records.
 */
@interface MikrusLinkExtractor : NSObject

/**
 * @abstract Extracts link entries from an ATProto record.
 * @param record The record dictionary.
 * @return Array of link entry dictionaries.
 */
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)linkEntriesInRecord:(NSDictionary *)record;

/**
 * @abstract Extracts subject URIs from a specific path in a record.
 * @param record The record dictionary.
 * @param path JSON path to extract from.
 * @return Array of extracted subject URIs.
 */
+ (NSArray<NSString *> *)subjectsInRecord:(NSDictionary *)record path:(NSString *)path;

/**
 * @abstract Validates if a string value represents a link subject.
 * @param value The value to validate.
 * @return YES if it is a valid link subject.
 */
+ (BOOL)isLinkSubject:(NSString *)value;

@end

NS_ASSUME_NONNULL_END
