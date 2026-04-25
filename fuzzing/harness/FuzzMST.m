// FuzzMST.m - Merkle Search Tree fuzzer harness
// Target: MST/CAR parsing and CBOR deserialization

#import <Foundation/Foundation.h>
#import "Repository/CAR.h"
#import "Repository/MST.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    @autoreleasepool {
        NSData *input = [NSData dataWithBytes:data length:size];
        NSError *error = nil;

        CARReader *reader = [CARReader readFromData:input error:&error];
        if (reader) {
            (void)reader.rootCID;
            (void)reader.blocks;
        }

        MST *mst = [MST deserializeFromCBOR:input];
        if (mst) {
            (void)mst.root;
            (void)mst.rootCID;
            (void)[mst allEntries];
        }
    }
    return 0;
}
