// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#ifndef NSDataCompat_h
#define NSDataCompat_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#if !defined(__APPLE__)

typedef NSUInteger NSDataReadingOptions;

@interface NSData (GNUstepCompat)

+ (nullable NSData *)dataWithContentsOfFile:(NSString *)path
                                    options:(NSDataReadingOptions)readOptionsMask
                                      error:(NSError * _Nullable * _Nullable)errorPtr;

@end

#endif

NS_ASSUME_NONNULL_END

#endif
