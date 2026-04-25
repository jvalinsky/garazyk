// CBOR FUZZER HARNESS — tests both simple and offset-based decoding
#import <Foundation/Foundation.h>
#import "Repository/CBOR.h"
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    @autoreleasepool {
        NSData *input = [NSData dataWithBytes:data length:size];

        // Simple decode path (used for single-value parsing)
        CBORValue *value = [CBORDecoder decode:input];
        if (value) {
            (void)value.type;
            (void)value.unsignedInteger;
            (void)value.negativeInteger;
            (void)value.byteString;
            (void)value.textString;
            (void)value.array;
            (void)value.map;
        }

        // Offset-based decode path (used for streaming/multi-value sequences)
        NSUInteger offset = 0;
        CBORValue *offsetValue = [CBORDecoder decode:input offset:&offset];
        if (offsetValue) {
            (void)offsetValue.type;
            (void)offsetValue.simpleValue;
            (void)offsetValue.floatValue;
        }
        (void)offset; // Track final offset for coverage
    }
    return 0;
}
