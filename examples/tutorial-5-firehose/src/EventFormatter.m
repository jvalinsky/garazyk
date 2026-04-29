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

    // SIMPLIFICATION: The production PDS uses DAG-CBOR encoding for firehose events.
    // This tutorial uses JSON for simplicity. The frame format is also simplified:
    //   Production: [varint header_len][DAG-CBOR header][DAG-CBOR body]
    //   Tutorial:   [JSON header bytes][JSON body bytes]
    //
    // To use real DAG-CBOR, you would need a CBOR encoder (e.g., cbor-x or
    // a custom encoder) and encode the header/body separately.

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
