// fuzz_http.mm — libFuzzer entry point for HTTP/1.1 request parsing
//
// Exercises Http1Parser with arbitrary input bytes.

#import <Foundation/Foundation.h>
#include "Network/Http1Parser.h"
#include "Network/HttpParsing.h"
#include <stdint.h>
#include <stdlib.h>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size) {
    @autoreleasepool {
        if (Size == 0) return 0;

        NSData *inputData = [NSData dataWithBytes:Data length:Size];
        NSString *inputString = [[NSString alloc] initWithData:inputData
                                                      encoding:NSUTF8StringEncoding];
        if (!inputString) return 0;

        // Feed raw bytes into the HTTP parser
        Http1Parser *parser = [[Http1Parser alloc] init];
        [parser parseData:inputData];
    }
    return 0;
}
