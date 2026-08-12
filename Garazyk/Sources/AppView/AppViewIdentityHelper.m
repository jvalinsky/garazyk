// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSAppViewIdentityHelper.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/AppViewIdentityHelper.h"
#import "Core/DID.h"
#import "Core/ATProtoValidator.h"

static NSCache<NSString *, NSString *> *s_handleCache = nil;
static NSString *s_plcURL = @"https://plc.directory";
static NSTimeInterval s_cacheTTL = 300; // 5 minutes

@implementation PDSAppViewIdentityHelper

+ (void)initialize {
    if (self == [PDSAppViewIdentityHelper class]) {
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
        return nil;
    }

    if (![did hasPrefix:@"did:plc:"]) {
        // We only support PLC resolution in this helper for now.
        // Returns nil (handle not found) without error.
        return nil;
    }
    NSError *validationError = nil;
    if (![ATProtoValidator validateDID:did error:&validationError]) {
        if (error) *error = validationError;
        return nil;
    }

    NSString *cached = [s_handleCache objectForKey:did];
    if (cached) {
        return cached;
    }

    // Use Core's DID resolver capability rather than constructing the PLC
    // transport client here. AppView only needs the resolved document; keeping
    // the concrete network client in PLC avoids an AppView -> PLC module edge.
    ATProtoDIDResolver *resolver = [[ATProtoDIDResolver alloc] initWithRequestTimeout:3.0];
    resolver.plcURL = s_plcURL;
    
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
        // Do not report errors for missing or invalid DIDs during handle resolution,
        // just return nil to indicate handle couldn't be determined.
        if (error) *error = nil;
        return nil;
    }
    
    NSArray *alsoKnownAs = doc[@"alsoKnownAs"];
    if (!alsoKnownAs || ![alsoKnownAs isKindOfClass:[NSArray class]]) {
        return nil;
    }
    
    NSString *handle = nil;
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
