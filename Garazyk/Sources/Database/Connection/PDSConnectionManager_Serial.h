// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Database/Connection/PDSConnectionManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSConnectionManager_Serial : NSObject <PDSConnectionManager>

- (instancetype)initWithLabel:(NSString *)label;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
