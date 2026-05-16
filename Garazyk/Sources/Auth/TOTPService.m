// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/TOTPService.h"
#import "Auth/TOTPGenerator.h"
#import "Auth/Base32Utils.h"
#import "Auth/CryptoUtils.h"
#import "Auth/YubiKeyOATH.h"
#import "Security/PDSSecurityCompare.h"


#if defined(GNUSTEP)
#import <qrencode.h>
#else
#import <CoreImage/CoreImage.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#endif

@implementation TOTPService

@synthesize yubiKeyManager = _yubiKeyManager;
@synthesize secret = _secret;
@synthesize counter = _counter;

- (instancetype)initWithSecret:(NSData *)secret {
    self = [super init];
    if (self) {
        _secret = [secret copy];
        _counter = 0; // For future HOTP support
        _yubiKeyManager = [[YubiKeyOATHManager alloc] init];
    }
    return self;
}

+ (NSString *)generateSecret {
    NSData *randomBytes = [CryptoUtils randomBytes:20]; // 160 bits (recommended min)
    return [Base32Utils base32StringFromData:randomBytes];
}

+ (BOOL)verifyCode:(NSString *)code secret:(NSString *)secret {
    NSData *secretData = [Base32Utils dataFromBase32String:secret];
    if (!secretData) return NO;
    
    TOTPGenerator *generator = [[TOTPGenerator alloc] initWithSecret:secretData];
    
    // Check current time window and previous one (allow 30s drift)
    NSString *otpCurrent = [generator generateOTP];
    NSString *otpPrev = [generator generateOTPForDate:[NSDate dateWithTimeIntervalSinceNow:-30]];
    NSString *otpNext = [generator generateOTPForDate:[NSDate dateWithTimeIntervalSinceNow:30]];

    return [PDSSecurityCompare constantTimeEqualString:code string:otpCurrent] || 
           [PDSSecurityCompare constantTimeEqualString:code string:otpPrev] || 
           [PDSSecurityCompare constantTimeEqualString:code string:otpNext];
}

+ (nullable NSData *)generateQRCodeImageForSecret:(NSString *)secret 
                                        accountName:(NSString *)accountName 
                                             issuer:(NSString *)issuer {
    // otpauth://totp/Issuer:Account?secret=SECRET&issuer=Issuer
    NSString *label = [NSString stringWithFormat:@"%@:%@", issuer, accountName];
    NSString *urlString = [NSString stringWithFormat:@"otpauth://totp/%@?secret=%@&issuer=%@", 
                           [label stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]],
                           secret,
                           [issuer stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    
#if defined(GNUSTEP)
    QRcode *qrcode = QRcode_encodeString([urlString UTF8String], 0, QR_ECLEVEL_M, QR_MODE_8, 1);
    if (!qrcode) return nil;
    
    // Generate a simple PBM (Portable BitMap) P4 format
    int width = qrcode->width;
    int rowBytes = (width + 7) / 8;
    NSMutableData *pbmData = [NSMutableData data];
    NSString *header = [NSString stringWithFormat:@"P4\n%d %d\n", width, width];
    [pbmData appendData:[header dataUsingEncoding:NSASCIIStringEncoding]];
    
    unsigned char *p = qrcode->data;
    for (int y = 0; y < width; y++) {
        for (int x = 0; x < rowBytes; x++) {
            unsigned char byte = 0;
            for (int bit = 0; bit < 8; bit++) {
                int xx = x * 8 + bit;
                if (xx < width) {
                    if (p[y * width + xx] & 1) {
                        byte |= (1 << (7 - bit));
                    }
                }
            }
            [pbmData appendBytes:&byte length:1];
        }
    }
    
    QRcode_free(qrcode);
    return pbmData;
#else
    NSData *stringData = [urlString dataUsingEncoding:NSISOLatin1StringEncoding];
    
    CIFilter *qrFilter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [qrFilter setValue:stringData forKey:@"inputMessage"];
    [qrFilter setValue:@"M" forKey:@"inputCorrectionLevel"];
    
    CIImage *image = qrFilter.outputImage;
    if (!image) return nil;
    
    // Scale up the image (QRCode is 1pt per module)
    CGAffineTransform transform = CGAffineTransformMakeScale(10.0, 10.0);
    CIImage *scaledImage = [image imageByApplyingTransform:transform];
    
    CIContext *context = [CIContext contextWithOptions:nil];
    // Create CGImage to convert to PNG data (simplest way without import UIKit/AppKit)
    CGImageRef cgImage = [context createCGImage:scaledImage fromRect:scaledImage.extent];
    
    if (!cgImage) return nil;
    
    CFMutableDataRef pngData = CFDataCreateMutable(NULL, 0);
    CGImageDestinationRef destination = CGImageDestinationCreateWithData(pngData, (__bridge CFStringRef)@"public.png", 1, NULL);
    CGImageDestinationAddImage(destination, cgImage, NULL);
    
    BOOL success = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    CGImageRelease(cgImage);
    
    if (success) {
        return (__bridge_transfer NSData *)pngData;
    } else {
        CFRelease(pngData);
        return nil;
    }
#endif
}

- (nullable NSString *)generateTOTPToken:(NSError **)error {
    // YubiKeyOATHManager is software-only in the PDS process.
    NSString *token = [self.yubiKeyManager generateTOTPForSecret:self.secret counter:self.counter error:error];
    if (token) {
        return token;
    } else {
        // Fallback to direct software generation if hardware manager fails
        return [self generateSoftwareToken];
    }
}

- (nullable NSString *)generateSoftwareToken {
    TOTPGenerator *generator = [[TOTPGenerator alloc] initWithSecret:self.secret];
    return [generator generateOTP];
}

@end
