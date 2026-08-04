// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoTID.h

 @abstract Timestamp Identifier (ATProtoTID) for ATProto record keys.

 @discussion Implements TIDs as 13-character base32-sortable identifiers
 encoding microsecond timestamps. TIDs provide chronological ordering
 for records and serve as unique keys within collections.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class ATProtoTID

 @abstract Time-ordered identifier for ATProto records.

 @discussion Encodes microsecond timestamps in a sortable base32 format.
 Used as record keys (rkeys) in repository collections.
 */
@interface ATProtoTID : NSObject <NSCopying, NSSecureCoding>

/*! The raw ATProtoTID string (13-character base32). */
@property (readonly, nonatomic, copy) NSString *stringValue;

/*! The timestamp component (microseconds since Unix epoch). */
@property (readonly, nonatomic) uint64_t timestamp;

/*!
 @method tid
 @abstract Create a new ATProtoTID with current timestamp.
 @return A new ATProtoTID instance.
 */
+ (instancetype)tid;

/*!
 @method tidFromString:
 @abstract Create ATProtoTID from string.
 @param string The ATProtoTID string.
 @return A new ATProtoTID instance.
 */
+ (nullable instancetype)tidFromString:(NSString *)string;

/*!
 @method tidWithTimestamp:
 @abstract Create ATProtoTID from timestamp.
 @param timestamp Microseconds since Unix epoch.
 @return A new ATProtoTID instance.
 */
+ (instancetype)tidWithTimestamp:(uint64_t)timestamp;

/*!
 @method tidWithDate:
 @abstract Create ATProtoTID from date.
 @param date The date.
 @return A new ATProtoTID instance.
 */
+ (instancetype)tidWithDate:(NSDate *)date;

/*!
 @method compare:
 @abstract Compare two TIDs chronologically.
 @param other The other ATProtoTID to compare.
 @return Comparison result.
 */
- (NSComparisonResult)compare:(ATProtoTID *)other;

/*!
 @method isBefore:
 @abstract Check if this ATProtoTID is before another.
 @param other The other ATProtoTID.
 @return YES if this ATProtoTID is before the other, NO otherwise.
 */
- (BOOL)isBefore:(ATProtoTID *)other;

/*!
 @method isAfter:
 @abstract Check if this ATProtoTID is after another.
 @param other The other ATProtoTID.
 @return YES if this ATProtoTID is after the other, NO otherwise.
 */
- (BOOL)isAfter:(ATProtoTID *)other;

@end

/*! Base32-sortable alphabet for TIDs: 234567abcdefghijklmnopqrstuvwxyz. */
static const char kTIDBase32Alphabet[] = "234567abcdefghijklmnopqrstuvwxyz";

NS_ASSUME_NONNULL_END