/*!
 @file AppViewIdentityHelper.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/AppViewIdentityHelper.h"
#import "PLC/DIDPLCResolver.h"

static NSCache<NSString *, NSString *> *s_handleCache = nil;
static NSString *s_plcURL = @"https://plc.directory";
static NSTimeInterval s_cacheTTL = 300; // 5 minutes

@implementation AppViewIdentityHelper

+ (void)initialize {
    if (self == [AppViewIdentityHelper class]) {
        s_handleCache = [[NSCache alloc] init];
    }
}

+ (void)configureWithPlcURL:(NSString *)plcURL
            cacheTTLSeconds:(NSTimeInterval)cacheTTL {
    if (plcURL) {
        s_plcURL = plcURL;
    }
    if (cacheTTL > 0) {
        s_cacheTTL = cacheTTL;
    }
}

+ (nullable NSString *)resolveHandleForDID:(NSString *)did 
                                     error:(NSError **)error {
    if (!did || did.length == 0) {
        return @"invalid.handle";
    }

    NSString *cached = [s_handleCache objectForKey:did];
    if (cached) {
        return cached;
    }

    DIDPLCResolver *resolver = [[DIDPLCResolver alloc] initWithPlcUrl:s_plcURL];
    resolver.timeout = 3.0; // Short timeout for admin UI responsiveness
    
    // Create a semaphore for sync resolution
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block NSDictionary *doc = nil;
    __block NSError *resolveErr = nil;
    
    [resolver resolveDID:did completion:^(NSDictionary * _Nullable document, NSError * _Nullable e) {
        doc = document;
        resolveErr = e;
        dispatch_semaphore_signal(sema);
    }];
    
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC));
    long waitResult = dispatch_semaphore_wait(sema, timeout);
    
    if (waitResult != 0 || resolveErr || !doc) {
        if (error && resolveErr) {
            *error = resolveErr;
        }
        return @"invalid.handle";
    }
    
    NSArray *alsoKnownAs = doc[@"alsoKnownAs"];
    if (!alsoKnownAs || ![alsoKnownAs isKindOfClass:[NSArray class]]) {
        return @"invalid.handle";
    }
    
    NSString *handle = @"invalid.handle";
    for (id value in alsoKnownAs) {
        if ([value isKindOfClass:[NSString class]]) {
            NSString *candidate = (NSString *)value;
            if ([candidate hasPrefix:@"at://"]) {
                candidate = [candidate substringFromIndex:5];
            }
            if ([candidate hasSuffix:@"/"]) {
                candidate = [candidate substringToIndex:candidate.length - 1];
            }
            if (candidate.length > 0) {
                handle = [candidate lowercaseString];
                break;
            }
        }
    }
    
    if (handle) {
        // Cache the result
        [s_handleCache setObject:handle forKey:did];
    }
    
    return handle;
}

@end
