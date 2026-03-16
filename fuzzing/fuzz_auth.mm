// fuzz_auth.mm — libFuzzer entry point for authentication token parsing
//
// Exercises JWT parsing and Base32 decoding with arbitrary input.

#import <Foundation/Foundation.h>
#include "Auth/JWT.h"
#include "Auth/Base32Utils.h"
#include <stdint.h>
#include <stdlib.h>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size) {
    @autoreleasepool {
        if (Size == 0) return 0;

        NSData *inputData = [NSData dataWithBytes:Data length:Size];
        NSString *inputString = [[NSString alloc] initWithData:inputData
                                                      encoding:NSUTF8StringEncoding];
        if (!inputString) return 0;

        // Attempt to parse as a JWT token (3 base64url parts separated by '.')
        NSError *jwtError = nil;
        JWT *jwt = [JWT tokenFromString:inputString error:&jwtError];
        (void)jwt;

        // Attempt Base32 decoding
        NSData *decoded = [Base32Utils dataFromBase32String:inputString];
        (void)decoded;
    }
    return 0;
}
