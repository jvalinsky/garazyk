#import <Foundation/Foundation.h>
#import "Blob/MimeTypeValidator.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        MimeTypeValidator *validator = [MimeTypeValidator sharedValidator];
        int passed = 0;
        int failed = 0;

        NSLog(@"🧪 MimeTypeValidator Unit Tests");
        NSLog(@"================================\n");

        #define TEST(name, condition) do { \
            if (condition) { \
                NSLog(@"✅ %s: PASSED", name); \
                passed++; \
            } else { \
                NSLog(@"❌ %s: FAILED", name); \
                failed++; \
            } \
        } while(0)

        NSLog(@"📋 Format Validation Tests");
        NSLog(@"----------------------------");

        TEST("Valid JPEG", [validator isValidMimeType:@"image/jpeg" error:nil]);
        TEST("Valid PNG", [validator isValidMimeType:@"image/png" error:nil]);
        TEST("Valid with subtype", [validator isValidMimeType:@"application/pdf" error:nil]);
        TEST("Invalid - no slash", ![validator isValidMimeType:@"imagejpeg" error:nil]);
        TEST("Invalid - empty type", ![validator isValidMimeType:@"/jpeg" error:nil]);
        TEST("Invalid - empty subtype", ![validator isValidMimeType:@"image/" error:nil]);
        TEST("Invalid - nil", ![validator isValidMimeType:nil error:nil]);
        TEST("Invalid - empty", ![validator isValidMimeType:@"" error:nil]);
        TEST("Case normalization", [validator isValidMimeType:@"IMAGE/JPEG" error:nil]);
        TEST("Whitespace trimming", [validator isValidMimeType:@"  image/jpeg  " error:nil]);

        NSLog(@"\n📋 Support Validation Tests");
        NSLog(@"----------------------------");

        TEST("Supported image/jpeg", [validator isSupportedMimeType:@"image/jpeg" error:nil]);
        TEST("Supported image/png", [validator isSupportedMimeType:@"image/png" error:nil]);
        TEST("Supported video/mp4", [validator isSupportedMimeType:@"video/mp4" error:nil]);
        TEST("Supported audio/mpeg", [validator isSupportedMimeType:@"audio/mpeg" error:nil]);
        TEST("Supported text/plain", [validator isSupportedMimeType:@"text/plain" error:nil]);
        TEST("Supported application/json", [validator isSupportedMimeType:@"application/json" error:nil]);
        TEST("Unsupported type", ![validator isSupportedMimeType:@"application/x-custom" error:nil]);
        TEST("Unsupported image/x-icon", ![validator isSupportedMimeType:@"image/x-icon" error:nil]);

        NSLog(@"\n📋 Category Tests");
        NSLog(@"------------------");

        TEST("Category image", [validator categoryForMimeType:@"image/jpeg"] == MimeCategoryImage);
        TEST("Category video", [validator categoryForMimeType:@"video/mp4"] == MimeCategoryVideo);
        TEST("Category audio", [validator categoryForMimeType:@"audio/mpeg"] == MimeCategoryAudio);
        TEST("Category text", [validator categoryForMimeType:@"text/plain"] == MimeCategoryText);
        TEST("Category font", [validator categoryForMimeType:@"font/woff2"] == MimeCategoryFont);
        TEST("Category model", [validator categoryForMimeType:@"model/gltf-binary"] == MimeCategoryModel);
        TEST("Category application", [validator categoryForMimeType:@"application/json"] == MimeCategoryApplication);
        TEST("Category unknown", [validator categoryForMimeType:@"x-custom/type"] == MimeCategoryOther);

        NSLog(@"\n📋 Size Validation Tests");
        NSLog(@"------------------------");

        TEST("Valid small size", [validator validateSize:1024 forMimeType:@"image/jpeg" error:nil]);
        TEST("Valid boundary size", [validator validateSize:5 * 1024 * 1024 forMimeType:@"image/jpeg" error:nil]);
        TEST("Too large image", ![validator validateSize:6 * 1024 * 1024 forMimeType:@"image/jpeg" error:nil]);
        TEST("Valid large video", [validator validateSize:10 * 1024 * 1024 forMimeType:@"video/mp4" error:nil]);
        TEST("Too large video", ![validator validateSize:51 * 1024 * 1024 forMimeType:@"video/mp4" error:nil]);

        NSLog(@"\n📋 Max Size Tests");
        NSLog(@"-----------------");

        TEST("Image max size", [validator maxSizeForMimeType:@"image/jpeg"] == 5 * 1024 * 1024);
        TEST("Video max size", [validator maxSizeForMimeType:@"video/mp4"] == 50 * 1024 * 1024);
        TEST("Audio max size", [validator maxSizeForMimeType:@"audio/mpeg"] == 10 * 1024 * 1024);
        TEST("Unknown max size", [validator maxSizeForMimeType:@"x-custom/type"] == 5 * 1024 * 1024);

        NSLog(@"\n📋 Extension Conversion Tests");
        NSLog(@"------------------------------");

        TEST("Extension for jpeg", [[validator fileExtensionForMimeType:@"image/jpeg"] isEqualToString:@"jpg"]);
        TEST("Extension for png", [[validator fileExtensionForMimeType:@"image/png"] isEqualToString:@"png"]);
        TEST("Extension for mp4", [[validator fileExtensionForMimeType:@"video/mp4"] isEqualToString:@"mp4"]);
        TEST("Extension for glb", [[validator fileExtensionForMimeType:@"model/gltf-binary"] isEqualToString:@"glb"]);
        TEST("MIME type for jpg", [[validator mimeTypeForFileExtension:@"jpg"] isEqualToString:@"image/jpeg"]);
        TEST("MIME type for jpeg", [validator mimeTypeForFileExtension:@"jpeg"] == nil);
        TEST("MIME type for pdf", [[validator mimeTypeForFileExtension:@"pdf"] isEqualToString:@"application/pdf"]);
        TEST("MIME type for dot extension", [[validator mimeTypeForFileExtension:@".jpg"] isEqualToString:@"image/jpeg"]);
        TEST("Invalid extension", [validator mimeTypeForFileExtension:@"xyzxyz"] == nil);

        NSLog(@"\n📋 Type Checking Tests");
        NSLog(@"----------------------");

        TEST("Is image", [validator isImageMimeType:@"image/jpeg"]);
        TEST("Is not video as image", ![validator isImageMimeType:@"video/mp4"]);
        TEST("Is video", [validator isVideoMimeType:@"video/mp4"]);
        TEST("Is audio", [validator isAudioMimeType:@"audio/mpeg"]);
        TEST("Is text plain", [validator isTextMimeType:@"text/plain"]);
        TEST("Is text css", [validator isTextMimeType:@"text/css"]);
        TEST("Is not text json", ![validator isTextMimeType:@"application/json"]);

        NSLog(@"\n📋 Description Tests");
        NSLog(@"--------------------");

        TEST("Description jpeg", [[validator descriptionForMimeType:@"image/jpeg"] isEqualToString:@"JPEG Image"]);
        TEST("Description pdf", [[validator descriptionForMimeType:@"application/pdf"] isEqualToString:@"PDF Document"]);
        TEST("Description unknown image", [[validator descriptionForMimeType:@"image/unknown"] isEqualToString:@"Image File"]);

        NSLog(@"\n📋 Accept List Matching Tests");
        NSLog(@"-----------------------------");

        TEST("Accept */* matches jpeg", [validator matchesAccept:@"*/*" mimeType:@"image/jpeg"]);
        TEST("Accept */* matches video", [validator matchesAccept:@"*/*" mimeType:@"video/mp4"]);
        TEST("Accept image/* matches jpeg", [validator matchesAccept:@"image/*" mimeType:@"image/jpeg"]);
        TEST("Accept image/* matches png", [validator matchesAccept:@"image/*" mimeType:@"image/png"]);
        TEST("Accept image/* does not match video", ![validator matchesAccept:@"image/*" mimeType:@"video/mp4"]);
        TEST("Accept exact match", [validator matchesAccept:@"image/jpeg" mimeType:@"image/jpeg"]);
        TEST("Accept does not match", ![validator matchesAccept:@"image/png" mimeType:@"image/jpeg"]);
        TEST("Accept video/* matches mp4", [validator matchesAccept:@"video/*" mimeType:@"video/mp4"]);

        NSLog(@"\n📋 Accept List Tests");
        NSLog(@"--------------------");

        NSArray *imageAccept = @[@"image/*", @"video/mp4"];
        TEST("Accept list matches image/*", [validator matchesAnyAccept:imageAccept mimeType:@"image/jpeg"]);
        TEST("Accept list matches exact", [validator matchesAnyAccept:imageAccept mimeType:@"video/mp4"]);
        TEST("Accept list does not match", ![validator matchesAnyAccept:imageAccept mimeType:@"audio/mpeg"]);
        TEST("Empty accept list", ![validator matchesAnyAccept:@[] mimeType:@"image/jpeg"]);

        NSLog(@"\n📋 Magic Number Detection Tests");
        NSLog(@"--------------------------------");

        uint8_t pngHeader[] = {0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D};
        NSData *pngData = [NSData dataWithBytes:pngHeader length:sizeof(pngHeader)];
        NSString *pngSniffed = [validator sniffMimeTypeFromData:pngData];
        TEST("Detect PNG magic", pngSniffed != nil && [pngSniffed isEqualToString:@"image/png"]);

        uint8_t jpegHeader[] = {0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01};
        NSData *jpegData = [NSData dataWithBytes:jpegHeader length:sizeof(jpegHeader)];
        NSString *jpegSniffed = [validator sniffMimeTypeFromData:jpegData];
        TEST("Detect JPEG magic", jpegSniffed != nil && [jpegSniffed isEqualToString:@"image/jpeg"]);

        uint8_t pdfHeader[] = {'%', 'P', 'D', 'F', 0x31, 0x2E, 0x30, 0x0A, 0x25, 0x25, 0xE0, 0x0A};
        NSData *pdfData = [NSData dataWithBytes:pdfHeader length:sizeof(pdfHeader)];
        NSString *pdfSniffed = [validator sniffMimeTypeFromData:pdfData];
        TEST("Detect PDF magic", pdfSniffed != nil && [pdfSniffed isEqualToString:@"application/pdf"]);

        uint8_t smallData[] = {0x01, 0x02, 0x03};
        NSData *small = [NSData dataWithBytes:smallData length:sizeof(smallData)];
        TEST("Small data returns nil", [validator sniffMimeTypeFromData:small] == nil);

        NSLog(@"\n📋 Magic Number Validation Tests");
        NSLog(@"--------------------------------");

        NSError *magicError = nil;
        TEST("Valid PNG magic", [validator validateMagicNumbers:pngData forMimeType:@"image/png" error:&magicError]);
        TEST("Category match allowed PNG vs JPEG", [validator validateMagicNumbers:pngData forMimeType:@"image/jpeg" error:&magicError]);
        TEST("Category match allowed", [validator validateMagicNumbers:pngData forMimeType:@"image/webp" error:&magicError]);

        NSLog(@"\n=================================");
        NSLog(@"🎯 MimeTypeValidator Test Results: %d/%d passed", passed, passed + failed);
        NSLog(@"=================================");

        if (failed > 0) {
            NSLog(@"❌ %d tests FAILED", failed);
            return 1;
        } else {
            NSLog(@"🎉 All tests PASSED!");
            return 0;
        }
    }
}
