#import <Foundation/Foundation.h>
#import "Sync/Relay/EventFormatter.h"
#import "Sync/Firehose/Firehose.h"

NS_ASSUME_NONNULL_BEGIN

@interface FirehoseProtocolSession : NSObject

@property(nonatomic, assign) NSUInteger sequenceNumber;
@property(nonatomic, strong, readonly) EventFormatter *eventFormatter;

- (instancetype)initWithSequenceNumber:(NSUInteger)sequenceNumber;

- (NSData *)encodeCommitEvent:(FirehoseCommitEvent *)event;
- (NSData *)encodeIdentityEvent:(FirehoseIdentityEvent *)event;
- (NSData *)encodeAccountEvent:(FirehoseAccountEvent *)event;
- (NSData *)encodeInfoEvent:(FirehoseInfoEvent *)event;
- (NSData *)encodeErrorEvent:(FirehoseErrorEvent *)event;

@end

NS_ASSUME_NONNULL_END
