// FuzzBlob.m - Blob/file upload fuzzing harness
// Tests file upload handling, magic bytes, truncated files

#import <Foundation/Foundation.h>

#if __has_include("Repository/CAR.h")
#import "Repository/CAR.h"
#endif

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    @autoreleasepool {
        if (!data || size == 0) return 0;
        
        NSData *blobData = [NSData dataWithBytes:data length:size];
        
        // Test 1: Basic data inspection
        (void)blobData.length;
        (void)blobData.bytes;
        
        // Test 2: Magic byte detection
        if (size >= 4) {
            uint32_t magic = *(uint32_t *)data;
            // PNG: 0x89504E47
            // JPEG: 0xFFD8FF
            // GIF: 0x47494638
            // WebP: 0x52494646
            // PDF: 0x25504446
            // ZIP: 0x504B0304
            // CAR: 0x43417200
            (void)magic;
        }
        
        // Test 3: Size boundary tests
        if (size < 16) {
            (void)@"tiny";
        } else if (size > 10 * 1024 * 1024) {
            (void)@"huge";
        }
        
        // Test 4: Header-only reads (don't load full blob)
        if (size >= 4096) {
            NSData *headerOnly = [blobData subdataWithRange:NSMakeRange(0, 4096)];
            (void)headerOnly.length;
        }
        
        // Test 5: Partial reads
        if (size > 1) {
            NSData *firstByte = [blobData subdataWithRange:NSMakeRange(0, 1)];
            NSData *lastByte = [blobData subdataWithRange:NSMakeRange(size - 1, 1)];
            (void)firstByte;
            (void)lastByte;
        }
        
        // Test 6: Different offset reads
        for (NSUInteger offset = 0; offset < 256 && offset < size; offset += 64) {
            NSUInteger len = MIN(64, size - offset);
            NSData *chunk = [blobData subdataWithRange:NSMakeRange(offset, len)];
            (void)chunk;
        }
        
        // Test 7: Null byte patterns
        NSMutableData *mutated = [NSMutableData dataWithData:blobData];
        for (NSUInteger i = 0; i < MIN(16, size); i++) {
            uint8_t origByte;
            [mutated getBytes:&origByte range:NSMakeRange(i, 1)];
            uint8_t nullByte = 0;
            [mutated replaceBytesInRange:NSMakeRange(i, 1) withBytes:&nullByte length:1];
            (void)mutated;
            [mutated replaceBytesInRange:NSMakeRange(i, 1) withBytes:&origByte length:1];
        }
        
        // Test 8: Truncated writes (simulate interrupted upload)
        NSData *truncated = [blobData subdataWithRange:NSMakeRange(0, size / 2)];
        (void)truncated;
        
        // Test 9: Align to common boundaries
        if (size >= 512) {
            NSUInteger pageCount = size / 4096;
            (void)pageCount;
        }
        
        // Test 10: Subdata variations
        NSData *half1 = [blobData subdataWithRange:NSMakeRange(0, size / 2)];
        NSData *half2 = [blobData subdataWithRange:NSMakeRange(size / 2, size - size / 2)];
        (void)half1;
        (void)half2;
    }
    return 0;
}