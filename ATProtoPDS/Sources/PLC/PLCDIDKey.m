#import "PLCDIDKey.h"

@implementation PLCDIDKey

+ (nullable instancetype)parseFromString:(NSString *)didKey error:(NSError **)error {
    if (![didKey hasPrefix:@"did:key:"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCDIDKeyErrorDomain" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid prefix"}];
        }
        return nil;
    }
    
    // Stub implementation: just handle a dummy case or fail gracefully
    // Assuming ed25519 or p256 keys
    // For now we return a stub object if valid prefix
    PLCDIDKey *key = [[PLCDIDKey alloc] init];
    // _type = PLCDIDKeyTypeP256; // accessing ivar if declared in extension or synthesized?
    // We need to implement init or private setters.
    return key;
}

+ (BOOL)isValidDidKeyString:(NSString *)didKey error:(NSError **)error {
    return [didKey hasPrefix:@"did:key:"];
}

@end
