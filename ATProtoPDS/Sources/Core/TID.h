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

/// The raw TID string (13-character base32)
@property (readonly, nonatomic, strong) NSString *stringValue;

/// The timestamp component (microseconds since Unix epoch)
@property (readonly, nonatomic) uint64_t timestamp;

/// Create a new TID with current timestamp
+ (instancetype)tid;

/// Create TID from string
+ (nullable instancetype)tidFromString:(NSString *)string;

/// Create TID from timestamp
+ (instancetype)tidWithTimestamp:(uint64_t)timestamp;

/// Create TID from date
+ (instancetype)tidWithDate:(NSDate *)date;

/// Compare two TIDs chronologically
- (NSComparisonResult)compare:(TID *)other;

/// Check if this TID is before another
- (BOOL)isBefore:(TID *)other;

/// Check if this TID is after another
- (BOOL)isAfter:(TID *)other;

@end

/// Base32-sortable alphabet for TIDs: 234567abcdefghijklmnopqrstuvwxyz
static const char kTIDBase32Alphabet[] = "234567abcdefghijklmnopqrstuvwxyz";

NS_ASSUME_NONNULL_END