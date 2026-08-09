// FuzzXrpcDispatcher.m - XRPC dispatch fuzzer harness
// Target: ATProtoHttpRequest parsing for XRPC

#import <Foundation/Foundation.h>
#import "Network/HttpRequest.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    @autoreleasepool {
        NSData *input = [NSData dataWithBytes:data length:size];
        ATProtoHttpRequest *request = [ATProtoHttpRequest requestWithData:input remoteAddress:@"127.0.0.1"];
        if (request) {
            // Touch all parsed fields to ensure full parsing coverage
            (void)request.path;
            (void)request.jsonBody;
            (void)request.method;
            (void)request.methodString;
            (void)request.queryString;
            (void)request.queryParams;
            (void)request.headers;
            (void)request.body;
            (void)request.version;
            (void)request.correlationID;
            (void)request.remoteAddress;
            (void)request.multipartFormData;
        }
    }
    return 0;
}
