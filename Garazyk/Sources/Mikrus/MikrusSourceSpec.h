// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file MikrusSourceSpec.h
 * @abstract Parser for Microcosm Mikrus link source strings.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Error domain for source specification parsing.
 */
extern NSString * const MikrusSourceSpecErrorDomain;

/**
 * @abstract Parses and stores the specification of a Mikrus link source.
 */
@interface MikrusSourceSpec : NSObject

/** @abstract The collection associated with the source. */
@property (nonatomic, copy, readonly) NSString *collection;
/** @abstract The path associated with the source. */
@property (nonatomic, copy, readonly) NSString *path;

/**
 * @abstract Parses a source string into a specification instance.
 * @param source The source string (e.g., "collection/path").
 * @param error Receives failure details.
 * @return An initialized specification instance, or nil if parsing fails.
 */
+ (nullable instancetype)sourceSpecWithString:(NSString *)source error:(NSError **)error;

/**
 * @abstract Validates a source path string.
 * @param path The path string to validate.
 * @param error Receives validation failure details.
 * @return YES if valid.
 */
+ (BOOL)validatePath:(NSString *)path error:(NSError **)error;

/** @abstract Unavailable initializer. */
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
