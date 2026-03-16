// fuzz_cbor.mm — libFuzzer entry point for CBOR/DAG-CBOR deserialization
//
// Exercises ATProtoCBORSerialization and ATProtoDagCBOR with arbitrary input.

#import <Foundation/Foundation.h>
#include "Core/ATProtoCBORSerialization.h"
#include "Core/ATProtoDagCBOR.h"
#include <stdint.h>
#include <stdlib.h>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size) {
    @autoreleasepool {
        if (Size == 0) return 0;

        NSData *inputData = [NSData dataWithBytes:Data length:Size];

        // Fuzz CBOR deserialization
        NSError *error = nil;
        id cborResult = [ATProtoCBORSerialization objectFromCBORData:inputData error:&error];
        (void)cborResult;

        // Fuzz DAG-CBOR deserialization
        NSError *dagError = nil;
        id dagResult = [ATProtoDagCBOR objectFromData:inputData error:&dagError];
        (void)dagResult;
    }
    return 0;
}
