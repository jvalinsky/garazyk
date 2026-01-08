//
//  fuzz_cbor.mm
//  Fuzzing harness for CAR/CBOR parsing
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

        CBORValue *cborValue = [CBORDecoder decode:inputData];
        (void)cborValue;

        if (cborValue && error == nil) {
            NSData *encoded = [CBOREncoder encode:cborValue];
            if (encoded && error == nil) {
                CBORValue *decodedAgain = [CBORDecoder decode:encoded];
                (void)decodedAgain;
            }
        }

        CARReader *reader = [CARReader readFromData:inputData error:&error];
        (void)reader;

        if (reader && error == nil) {
            CID *rootCID = reader.rootCID;
            (void)rootCID;

            NSArray<CARBlock *> *blocks = reader.blocks;
            (void)blocks;

            if (size >= 32) {
                NSData *multihash = [NSData dataWithBytes:data length:MIN(size, 64)];
                CID *cid = [CID cidWithMultihash:multihash codec:0x71];
                (void)cid;

                if (cid && reader) {
                    CARBlock *block = [reader blockWithCID:cid];
                    (void)block;
                }
            }
        }

        if (size >= 32) {
            NSData *multihash = [NSData dataWithBytes:data length:MIN(size, 64)];
            CID *cid = [CID cidWithMultihash:multihash codec:0x71];
            (void)cid;

            if (cid) {
                NSString *cidString = cid.stringValue;
                (void)cidString;

                CID *parsed = [CID cidFromString:cidString];
                (void)parsed;
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
        fprintf(stderr, "Cannot open file: %s\n", argv[1]);
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
