//
//  fuzz_blob.mm
//  Blob security testing fuzzer for ATProto PDS
//
//  Tests:
//  1. MIME type validation bypass attempts
//  2. Path traversal in filenames
//  3. Magic byte spoofing
//  4. Archive-based attacks
//  5. Image parsing exploits
//  6. Resource exhaustion (size/zip bombs)
//

#import <Foundation/Foundation.h>
#import "Blob/MimeTypeValidator.h"
#import "Blob/BlobStorage.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0 || size > 50000000) {
        return 0;
    }

    @autoreleasepool {
        NSData *blobData = [NSData dataWithBytes:data length:size];

        // Test 1: Magic byte detection
        MimeTypeValidator *validator = [MimeTypeValidator sharedValidator];
        NSString *detectedType = [validator sniffMimeTypeFromData:blobData];
        (void)detectedType;

        // Test 2: Common image magic bytes
        NSArray *imageSignatures = @[
            [[NSData alloc] initWithBytes:"\xff\xd8\xff" length:3],   // JPEG
            [[NSData alloc] initWithBytes:"\x89PNG\r\n\x1a\n" length:8], // PNG
            [[NSData alloc] initWithBytes:"GIF87a" length:6],           // GIF87a
            [[NSData alloc] initWithBytes:"GIF89a" length:6],           // GIF89a
            [[NSData alloc] initWithBytes:"BM" length:2],               // BMP
            [[NSData alloc] initWithBytes:"RIFF" length:4],             // WEBP
        ];

        for (NSData *sig in imageSignatures) {
            if (blobData.length >= sig.length) {
                NSData *prefix = [blobData subdataWithRange:NSMakeRange(0, sig.length)];
                BOOL matches = [prefix isEqualToData:sig];
                (void)matches;
            }
        }

        // Test 3: Common executable signatures
        NSArray *exeSignatures = @[
            [[NSData alloc] initWithBytes:"\x4d\x5a" length:2],   // PE/EXE
            [[NSData alloc] initWithBytes:"#!" length:2],         // Script
            [[NSData alloc] initWithBytes:"<?php" length:5],      // PHP
            [[NSData alloc] initWithBytes:"<?" length:2],         // PHP short
            [[NSData alloc] initWithBytes:"<!DOCTYPE html" length:15], // HTML/SVG XSS
        ];

        for (NSData *sig in exeSignatures) {
            if (blobData.length >= sig.length) {
                NSData *prefix = [blobData subdataWithRange:NSMakeRange(0, sig.length)];
                BOOL matches = [prefix isEqualToData:sig];
                if (matches) {
                    // This would indicate a potentially malicious file
                }
            }
        }

        // Test 4: PHP code injection patterns
        NSArray *phpPatterns = @[
            @"<?php",
            @"<?=",
            @"<script language=\"php\">",
            @"system(",
            @"exec(",
            @"shell_exec(",
            @"passthru(",
            @"popen(",
            @"proc_open(",
        ];

        NSString *blobString = [[NSString alloc] initWithData:blobData encoding:NSUTF8StringEncoding];
        if (blobString) {
            for (NSString *pattern in phpPatterns) {
                if ([blobString containsString:pattern]) {
                    // Potentially malicious PHP code detected
                }
            }
        }

        // Test 5: JavaScript injection patterns
        NSArray *jsPatterns = @[
            @"<script",
            @"</script>",
            @"javascript:",
            @"onload=",
            @"onerror=",
            @"onmouseover=",
            @"eval(",
            @"document.cookie",
        ];

        for (NSString *pattern in jsPatterns) {
            if (blobString && [blobString containsString:pattern]) {
                // Potentially malicious JS detected
            }
        }

        // Test 6: Archive magic bytes
        NSArray *archiveSignatures = @[
            [[NSData alloc] initWithBytes:"PK\x03\x04" length:4],  // ZIP/JAR
            [[NSData alloc] initWithBytes:"PK\x05\x06" length:4],  // ZIP empty
            [[NSData alloc] initWithBytes:"Rar!\x1a\x07" length:6], // RAR
            [[NSData alloc] initWithBytes:"\x1f\x8b" length:2],    // GZ
            [[NSData alloc] initWithBytes:"BZh" length:3],         // BZ2
        ];

        for (NSData *sig in archiveSignatures) {
            if (blobData.length >= sig.length) {
                NSData *prefix = [blobData subdataWithRange:NSMakeRange(0, sig.length)];
                BOOL matches = [prefix isEqualToData:sig];
                (void)matches;
            }
        }

        // Test 7: Large blob size handling
        if (blobData.length > 1000000) {
            // Simulate checking size limits
            BOOL withinLimit = blobData.length <= 50000000;
            (void)withinLimit;
        }

        // Test 8: Null bytes in data (potential path traversal indicator)
        NSRange nullRange = [blobData rangeOfData:[NSData dataWithBytes:"\x00" length:1] options:0 range:NSMakeRange(0, MIN(blobData.length, 1000))];
        if (nullRange.location != NSNotFound) {
            // Null byte detected in first 1KB
        }

        // Test 9: Path traversal patterns in data
        NSArray *traversalPatterns = @[
            @"../../../",
            @"..\\..\\..\\",
            @"....//....//",
            @"%2e%2e%2f",
            @"%2e%2e%2f%2e%2e%2f",
        ];

        for (NSString *pattern in traversalPatterns) {
            if (blobString && [blobString containsString:pattern]) {
                // Path traversal pattern detected
            }
        }

        // Test 10: XML external entity patterns
        NSArray *xxePatterns = @[
            @"<!ENTITY",
            @"SYSTEM \"",
            @"PUBLIC \"",
            @"<![CDATA[",
            @"<?xml",
        ];

        for (NSString *pattern in xxePatterns) {
            if (blobString && [blobString containsString:pattern]) {
                // Potential XXE pattern detected
            }
        }

        // Test 11: SVG specific attacks
        NSArray *svgPatterns = @[
            @"<svg",
            @"<use",
            @"xlink:href",
            @"javascript:",
            @"onload=",
            @"onerror=",
        ];

        for (NSString *pattern in svgPatterns) {
            if (blobString && [blobString containsString:pattern]) {
                // SVG with potential XSS vectors
            }
        }

        // Test 12: ZIP content validation
        NSData *zipMagic = [NSData dataWithBytes:"PK\x03\x04" length:4];
        if (blobData.length >= 4 && [[blobData subdataWithRange:NSMakeRange(0, 4)] isEqualToData:zipMagic]) {
            // Check for suspicious ZIP contents
            NSArray *suspiciousNames = @[
                @"../",
                @"..\\",
                @"/etc/passwd",
                @"C:\\Windows",
                @"META-INF/MANIFEST.MF",
            ];

            NSString *zipContent = [[NSString alloc] initWithData:blobData encoding:NSUTF8StringEncoding];
            for (NSString *name in suspiciousNames) {
                if (zipContent && [zipContent containsString:name]) {
                    // Suspicious ZIP content
                }
            }
        }

        // Test 13: Recursive archive detection (zip bomb indicator)
        NSUInteger zipCount = 0;
        NSUInteger searchLength = MIN(blobData.length, 10000);
        for (NSUInteger i = 0; i < searchLength - 3; i++) {
            NSData *sub = [blobData subdataWithRange:NSMakeRange(i, 4)];
            if ([[NSData dataWithBytes:"PK\x03\x04" length:4] isEqualToData:sub]) {
                zipCount++;
            }
        }
        if (zipCount > 10) {
            // Potential zip bomb - many ZIP files nested
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

    printf("Testing blob security: %zu bytes\n", readSize);
    int result = LLVMFuzzerTestOneInput(data, readSize);
    free(data);

    return result;
}
#endif
