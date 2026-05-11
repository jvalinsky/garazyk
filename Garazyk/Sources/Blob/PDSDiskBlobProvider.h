// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Blob/PDSBlobProvider.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSDiskBlobProvider : NSObject <PDSBlobProvider>

@property (nonatomic, strong, readonly) NSURL *storageDirectory;

- (instancetype)initWithStorageDirectory:(NSURL *)storageDirectory;

@end

NS_ASSUME_NONNULL_END
