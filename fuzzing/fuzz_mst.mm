// fuzz_mst.mm — libFuzzer entry point for the Merkle Search Tree
//
// Exercises MST node deserialization with arbitrary CBOR-encoded data,
// catching integer overflows, OOB reads, and invalid tree structure handling.

#import <Foundation/Foundation.h>
#include "Repository/MST.h"
#include "Core/ATProtoCBORSerialization.h"
#include <stdint.h>
#include <stdlib.h>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size) {
    @autoreleasepool {
        if (Size == 0) return 0;

        NSData *inputData = [NSData dataWithBytes:Data length:Size];

        // Attempt CBOR decode (MST nodes are serialized as DAG-CBOR)
        NSError *error = nil;
        id cborObject = [ATProtoCBORSerialization objectFromCBORData:inputData error:&error];
        if (!cborObject) return 0;

        // Attempt to deserialize as an MST node
        if ([cborObject isKindOfClass:[NSDictionary class]]) {
            NSError *mstError = nil;
            MSTNode *node = [MSTNode nodeFromCBORDictionary:(NSDictionary *)cborObject
                                                      error:&mstError];
            (void)node;
        }
    }
    return 0;
}
