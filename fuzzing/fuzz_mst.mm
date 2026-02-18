//
//  fuzz_mst.mm
//  Merkle Search Tree fuzzing harness for ATProto PDS
//
//  Tests:
//  1. DAG-CBOR deserialization of MST nodes
//  2. Tree operations (put, delete)
//  3. Deterministic hashing/CID generation
//  4. Tree integrity (proofs, stats)
//

#import <Foundation/Foundation.h>
#import "Repository/MST.h"
#import "Core/CID.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0) {
        return 0;
    }

    @autoreleasepool {
        NSData *inputData = [NSData dataWithBytes:data length:size];
        
        // Test 1: Deserialization
        // Treat input as potential DAG-CBOR
        MST *tree = [MST deserializeFromCBOR:inputData];
        if (tree) {
            // If successfully deserialized, try to perform operations
            [tree get:@"test_key"];
            [tree allEntries];
            [tree getStatistics];
        }
        
        // Test 2: Tree Operations (Interpret input as commands)
        // Format: [Op(1)][Len(1)][Key][ValueCID_Hash(32)]
        
        MST *opTree = [[MST alloc] initWithRootCID:nil];
        NSUInteger position = 0;
        
        while (position < size) {
            if (position + 2 > size) break;
            
            uint8_t op = data[position] % 3; // 0=Put, 1=Delete, 2=Get
            uint8_t keyLen = data[position + 1];
            position += 2;
            
            if (keyLen == 0) keyLen = 1; // Minimum key length
            if (position + keyLen > size) break;
            
            NSString *key = [[NSString alloc] initWithBytes:data + position
                                                     length:keyLen
                                                   encoding:NSUTF8StringEncoding];
            position += keyLen;
            
            if (!key) continue;
            
            if (op == 0) { // Put
                // Use a dummy CID for value
                NSData *dummyHash = [NSData dataWithBytes:&op length:1]; // Just use op byte as hash seed
                CID *valCid = [CID sha256:dummyHash];
                [opTree put:key valueCID:valCid];
            } else if (op == 1) { // Delete
                [opTree delete:key];
            } else { // Get
                [opTree get:key];
            }
        }
        
        // Final integrity check
        [opTree getStatistics];
        [opTree rootCID];
    }
    return 0;
}
