// fuzz_blob.mm — libFuzzer entry point for blob MIME type and magic number validation
//
// Exercises MimeTypeValidator with arbitrary byte sequences to catch
// parser edge cases in magic number detection.

#import <Foundation/Foundation.h>
#include "Blob/MimeTypeValidator.h"
#include <stdint.h>
#include <stdlib.h>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size) {
    @autoreleasepool {
        if (Size == 0) return 0;

        NSData *inputData = [NSData dataWithBytes:Data length:Size];

        // Validate MIME type from magic bytes
        NSString *detectedType = [MimeTypeValidator mimeTypeFromMagicBytes:inputData];
        (void)detectedType;

        // Test MIME type string validation if input looks like text
        if (Size <= 256) {
            NSString *mimeString = [[NSString alloc] initWithData:inputData
                                                         encoding:NSUTF8StringEncoding];
            if (mimeString) {
                BOOL valid = [MimeTypeValidator isValidMimeType:mimeString];
                (void)valid;
            }
        }
    }
    return 0;
}
