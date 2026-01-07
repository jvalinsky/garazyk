#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Timestamp Identifier (TID) implementation for ATProto
/// TIDs are sortable, time-ordered identifiers for records
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