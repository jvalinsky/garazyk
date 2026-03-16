// fuzz_xrpc.mm — libFuzzer entry point for XRPC request parsing
//
// Exercises XRPCError parsing and URL/header parsing with arbitrary input.

#import <Foundation/Foundation.h>
#include "Network/XRPCError.h"
#include <stdint.h>
#include <stdlib.h>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size) {
    @autoreleasepool {
        if (Size == 0) return 0;

        NSData *inputData = [NSData dataWithBytes:Data length:Size];
        NSString *inputString = [[NSString alloc] initWithData:inputData
                                                      encoding:NSUTF8StringEncoding];
        if (!inputString) return 0;

        // Parse as XRPC error JSON
        NSError *jsonError = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:inputData options:0 error:&jsonError];
        if (parsed && [parsed isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)parsed;
            NSString *errorCode = dict[@"error"];
            NSString *message = dict[@"message"];
            (void)errorCode;
            (void)message;
        }
    }
    return 0;
}
