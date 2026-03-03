#import "EventFormatter.h"

@implementation FirehoseCommitEvent
@end

@implementation EventFormatter

- (nullable NSData *)encodeCommitEvent:(FirehoseCommitEvent *)event error:(NSError **)error {
    // Build event dictionary
    NSMutableDictionary *eventDict = [@{
        @"$type": @"#commit",
        @"seq": @(event.seq),
        @"rebase": @NO,
        @"tooBig": @NO,
        @"repo": event.repo,
        @"commit": [event.commit base64EncodedStringWithOptions:0],
        @"rev": event.rev,
        @"blocks": [event.blocks base64EncodedStringWithOptions:0],
        @"ops": event.ops,
        @"blobs": event.blobs,
        @"time": event.time
    } mutableCopy];
    
    if (event.since) {
        eventDict[@"since"] = event.since;
    }
    
    // Encode as JSON (simplified - use DAG-CBOR in production)
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:eventDict options:0 error:error];
    if (!jsonData) return nil;
    
    // Build frame: [header][body]
    NSDictionary *header = @{@"op": @1, @"t": @"#commit"};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:error];
    if (!headerData) return nil;
    
    NSMutableData *frame = [NSMutableData data];
    [frame appendData:headerData];
    [frame appendData:jsonData];
    
    return frame;
}

@end
