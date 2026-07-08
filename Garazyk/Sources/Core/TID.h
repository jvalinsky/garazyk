// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file TID.h

 @abstract Timestamp Identifier (TID) for ATProto record keys.

 @discussion Implements TIDs as 13-character base32-sortable identifiers
 encoding microsecond timestamps. TIDs provide chronological ordering
 for records and serve as unique keys within collections.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class TID

 @abstract Time-ordered identifier for ATProto records.

 @discussion Encodes microsecond timestamps in a sortable base32 format.
 Used as record keys (rkeys) in repository collections.
 */
@interface TID : NSObject <NSCopying, NSSecureCoding>

/*! The raw TID string (13-character base32). */
@property (readonly, nonatomic, copy) NSString *stringValue;

/*! The timestamp component (microseconds since Unix epoch). */
@property (readonly, nonatomic) uint64_t timestamp;

/*!
 @method tid
 @abstract Create a new TID with current timestamp.
 @return A new TID instance.
 */
+ (instancetype)tid;

/*!
 @method tidFromString:
 @abstract Create TID from string.
 @param string The TID string.
 @return A new TID instance.
 */
+ (nullable instancetype)tidFromString:(NSString *)string;

/*!
 @method tidWithTimestamp:
 @abstract Create TID from timestamp.
 @param timestamp Microseconds since Unix epoch.
 @return A new TID instance.
 */
+ (instancetype)tidWithTimestamp:(uint64_t)timestamp;

/*!
 @method tidWithDate:
 @abstract Create TID from date.
 @param date The date.
 @return A new TID instance.
 */
+ (instancetype)tidWithDate:(NSDate *)date;

/*!
 @method compare:
 @abstract Compare two TIDs chronologically.
 @param other The other TID to compare.
 @return Comparison result.
 */
- (NSComparisonResult)compare:(TID *)other;

/*!
 @method isBefore:
 @abstract Check if this TID is before another.
 @param other The other TID.
 @return YES if this TID is before the other, NO otherwise.
 */
- (BOOL)isBefore:(TID *)other;

/*!
 @method isAfter:
 @abstract Check if this TID is after another.
 @param other The other TID.
 @return YES if this TID is after the other, NO otherwise.
 */
- (BOOL)isAfter:(TID *)other;

@end

/*! Base32-sortable alphabet for TIDs: 234567abcdefghijklmnopqrstuvwxyz. */
static const char kTIDBase32Alphabet[] = "234567abcdefghijklmnopqrstuvwxyz";

NS_ASSUME_NONNULL_END