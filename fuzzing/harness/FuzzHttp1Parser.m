// FuzzHttp1Parser.m - HTTP/1.1 parsing fuzzer harness
// Target: Http1Parser feedData: (both success and error paths)

#import <Foundation/Foundation.h>
#import "Network/Http1Parser.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    @autoreleasepool {
        NSData *input = [NSData dataWithBytes:data length:size];
        Http1Parser *parser = [[Http1Parser alloc] init];
        parser.remoteAddress = @"127.0.0.1";

        BOOL didFeed = [parser feedData:input];
        if (didFeed) {
            // Check both success and error paths
            HttpRequest *req = [parser completedRequest];
            if (req) {
                (void)req.path;
                (void)req.jsonBody;
                (void)req.method;
                (void)req.headers;
            } else {
                // Success=YES but no request means it's an error
                Http1ParserError *parseErr = [parser parseError];
                if (parseErr) {
                    (void)parseErr.statusCode;
                    (void)parseErr.errorCode;
                    (void)parseErr.message;
                }
            }

            // Check state machine
            Http1ParserState state = parser.state;
            (void)state;

            // Test unconsumedData for pipelined requests
            NSData *unconsumed = [parser unconsumedData];
            (void)unconsumed;

            // If parser reached error state, the error method should be non-nil
            if (parser.state == Http1ParserStateError) {
                Http1ParserError *err = [parser parseError];
                (void)err;
            }
        }

        // Test chunk feeding: if state allows, feed the same data again
        if (parser.state != Http1ParserStateComplete && parser.state != Http1ParserStateError && size > 0) {
            [parser reset];
            NSData *half1 = [NSData dataWithBytes:data length:size/2];
            NSData *half2 = [NSData dataWithBytes:((uint8_t*)data + size/2) length:size - size/2];
            [parser feedData:half1];
            [parser feedData:half2];
        }
    }
    return 0;
}
