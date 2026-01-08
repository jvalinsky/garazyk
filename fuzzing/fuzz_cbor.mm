//
//  fuzz_cbor.mm
//  Comprehensive CBOR/CAR fuzzing harness for ATProto PDS
//
//  Tests:
//  1. CBOR decode/encode round-trip
//  2. CAR file parsing
//  3. CID construction and parsing
//  4. Edge cases and malformed inputs
//  5. Large inputs and boundary conditions
//

#import <Foundation/Foundation.h>
#import "Repository/CBOR.h"
#import "Repository/CAR.h"
#import "Core/CID.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0 || size > 100000) {
        return 0;
    }

    @autoreleasepool {
        NSData *inputData = [NSData dataWithBytes:data length:size];
        NSError *error = nil;

        // Test 1: Basic CBOR decode/encode round-trip
        CBORValue *decoded = [CBORDecoder decode:inputData];
        if (decoded && !error) {
            NSData *encoded = [CBOREncoder encode:decoded];
            if (encoded && encoded.length > 0) {
                CBORValue *decodedAgain = [CBORDecoder decode:encoded];
                (void)decodedAgain;
            }
        }

        // Test 2: CBOR decode with offset
        NSUInteger offset = 0;
        CBORValue *decodedOffset = [CBORDecoder decode:inputData offset:&offset];
        (void)decodedOffset;

        // Test 3: CAR file parsing
        CARReader *reader = [CARReader readFromData:inputData error:&error];
        if (reader && !error) {
            CID *rootCID = reader.rootCID;
            (void)rootCID;

            NSArray<CARBlock *> *blocks = reader.blocks;
            (void)blocks;

            if (blocks.count > 0) {
                for (CARBlock *block in blocks) {
                    (void)block.cid;
                    (void)block.data;
                    (void)block.data.length;
                }
            }

            // Test CID lookups
            if (size >= 32) {
                NSData *cidData = [NSData dataWithBytes:data length:32];
                CID *cid = [CID cidWithMultihash:cidData codec:0x71];
                (void)cid;

                if (cid && reader) {
                    CARBlock *foundBlock = [reader blockWithCID:cid];
                    (void)foundBlock;
                }
            }
        }

        // Test 4: CID construction from various inputs
        if (size >= 16) {
            NSUInteger testLength = MIN(size, 64);
            NSData *multihash = [NSData dataWithBytes:data length:testLength];

            // Try various codecs
            CID *cid0x70 = [CID cidWithMultihash:multihash codec:0x70];
            CID *cid0x71 = [CID cidWithMultihash:multihash codec:0x71];
            CID *cid0x72 = [CID cidWithMultihash:multihash codec:0x72];
            CID *cid0x55 = [CID cidWithMultihash:multihash codec:0x55];
            (void)cid0x70;
            (void)cid0x71;
            (void)cid0x72;
            (void)cid0x55;

            // Test string conversion
            if (cid0x71) {
                NSString *stringVal = cid0x71.stringValue;
                (void)stringVal;

                // Test CID from string
                if (stringVal.length > 0) {
                    CID *fromString = [CID cidFromString:stringVal];
                    (void)fromString;
                }
            }
        }

        // Test 5: Edge cases - minimal inputs
        NSData *singleByte = [NSData dataWithBytes:data length:1];
        CBORValue *single = [CBORDecoder decode:singleByte];
        (void)single;

        // Test 6: Edge cases - maximal valid CBOR
        if (size > 0) {
            uint8_t maxType[] = {0xFF};  // Break
            NSData *maxData = [NSData dataWithBytes:maxType length:1];
            CBORValue *maxVal = [CBORDecoder decode:maxData];
            (void)maxVal;
        }

        // Test 7: Very large but valid CBOR structures
        if (size > 1000 && size < 10000) {
            NSData *largeData = [NSData dataWithBytes:data length:size];
            CBORValue *large = [CBORDecoder decode:largeData];
            if (large) {
                NSData *encoded = [CBOREncoder encode:large];
                (void)encoded;
            }
        }

        // Test 8: CAR with multiple roots
        if (size >= 64) {
            NSMutableData *multiRoot = [NSMutableData dataWithData:inputData];
            [multiRoot appendData:inputData];  // Duplicate

            CARReader *multiReader = [CARReader readFromData:multiRoot error:&error];
            (void)multiReader;
        }

        // Test 9: CBOR type-specific tests
        CBORValue *testUnsigned = [CBORValue unsignedInteger:NSUIntegerMax];
        CBORValue *testNegative = [CBORValue negativeInteger:NSIntegerMin];
        CBORValue *testNil = [CBORValue nilValue];
        CBORValue *testSimple = [CBORValue simple:255];
        CBORValue *testFloat = [CBORValue floatingPoint:3.14159265358979];

        (void)testUnsigned;
        (void)testNegative;
        (void)testNil;
        (void)testSimple;
        (void)testFloat;

        // Test 10: Round-trip with all constructed values
        NSArray *testValues = @[
            testUnsigned,
            testNegative,
            testNil,
            testSimple,
            testFloat
        ];

        for (CBORValue *val in testValues) {
            if (val) {
                NSData *enc = [CBOREncoder encode:val];
                if (enc) {
                    CBORValue *dec = [CBORDecoder decode:enc];
                    (void)dec;
                }
            }
        }

        return 0;
    }
}

#ifndef LIBFUZZER
int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <input_file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        fprintf(stderr, "Cannot open file: %s\n", argv[0]);
        return 1;
    }

    fseek(f, 0, SEEK_END);
    long fileSize = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t *data = (uint8_t *)malloc(fileSize);
    size_t readSize = fread(data, 1, fileSize, f);
    fclose(f);

    int result = LLVMFuzzerTestOneInput(data, readSize);
    free(data);

    return result;
}
#endif
