// FuzzMimeTypeValidator.m - MIME type validation fuzzer harness
// Target: MIME type format validation and magic number checking

#import <Foundation/Foundation.h>
#import "Blob/MimeTypeValidator.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    @autoreleasepool {
        NSString *mimeType = [[NSString alloc] initWithBytes:data
                                                      length:size
                                                    encoding:NSUTF8StringEncoding];
        if (!mimeType) {
            mimeType = [[NSString alloc] initWithBytes:data
                                                length:size
                                              encoding:NSASCIIStringEncoding];
        }
        if (!mimeType) {
            return 0;
        }

        NSError *error = nil;
        MimeTypeValidator *validator = [MimeTypeValidator sharedValidator];

        // Validate the format of the MIME type
        [validator isValidMimeType:mimeType error:&error];

        // Check if the MIME type is supported
        [validator isSupportedMimeType:mimeType error:&error];

        // Test magic number validation with the fuzz-derived MIME type
        NSData *blobData = [NSData dataWithBytes:data length:size];
        [validator validateMagicNumbers:blobData
                           forMimeType:mimeType
                                error:&error];

        // Test MIME type sniffing (auto-detection) with the binary data
        NSString *sniffedType = [validator sniffMimeTypeFromData:blobData];
        (void)sniffedType;

        // Also test with common MIME types to exercise different magic paths
        NSArray *testTypes = @[@"image/jpeg", @"image/png", @"image/gif", @"image/webp",
                               @"video/mp4", @"audio/mpeg", @"application/pdf"];
        for (NSString *testType in testTypes) {
            [validator validateMagicNumbers:blobData
                               forMimeType:testType
                                    error:nil];
        }
    }
    return 0;
}
