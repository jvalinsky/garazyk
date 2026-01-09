#import "Auth/TOTPService.h"
#import "Auth/TOTPGenerator.h"
#import "Auth/Base32Utils.h"
#import "Auth/CryptoUtils.h"
#import <CoreImage/CoreImage.h>

@implementation TOTPService

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

    return [code isEqualToString:otpCurrent] || 
           [code isEqualToString:otpPrev] || 
           [code isEqualToString:otpNext];
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
}

@end
