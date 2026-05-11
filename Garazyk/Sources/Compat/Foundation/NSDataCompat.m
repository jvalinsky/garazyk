// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "NSDataCompat.h"

#if !defined(__APPLE__)

@implementation NSData (GNUstepCompat)

+ (nullable NSData *)dataWithContentsOfFile:(NSString *)path
                                    options:(NSDataReadingOptions)readOptionsMask
                                      error:(NSError * _Nullable * _Nullable)errorPtr {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil && errorPtr != NULL) {
        *errorPtr = [NSError errorWithDomain:NSCocoaErrorDomain
                                        code:NSFileReadNoSuchFileError
                                    userInfo:@{NSFilePathErrorKey: path ?: @""}];
    }
    return data;
}

@end

#endif
