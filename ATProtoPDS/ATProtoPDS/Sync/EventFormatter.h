#import <Foundation/Foundation.h>

@class FirehoseCommitEvent;
@class FirehoseIdentityEvent;
@class FirehoseErrorEvent;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const EventFormatterErrorDomain;
extern NSInteger const EventFormatterErrorCodeEncodingFailed;
extern NSInteger const EventFormatterErrorCodeDecodingFailed;

@interface EventFormatter : NSObject

- (nullable NSData *)encodeCommitEvent:(FirehoseCommitEvent *)event error:(NSError **)error;
- (nullable NSData *)encodeIdentityEvent:(FirehoseIdentityEvent *)event error:(NSError **)error;
- (nullable NSData *)encodeErrorEvent:(FirehoseErrorEvent *)event error:(NSError **)error;
- (nullable NSData *)encodeEventWithKind:(NSString *)kind payload:(NSDictionary *)payload error:(NSError **)error;

- (nullable id)decodeEventFromData:(NSData *)data error:(NSError **)error;

- (nullable NSData *)encodeCBORObject:(id)object error:(NSError **)error;
- (nullable id)decodeCBORData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
