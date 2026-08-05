// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSPLCAccountOperationProvider.h

 @abstract PLC-owned implementation of the Core account-operation provider.

 @discussion
    Runtime composition injects this class into PDSAccountService so Services
    never depends upward on PLCRotationKeyManager or PLCOperation.
 */

#import <Foundation/Foundation.h>
#import "Core/PDSPLCAccountOperationProvider.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSPLCAccountOperationProvider

 @abstract Signs PLC genesis operations with the server rotation key.
 */
@interface PDSPLCAccountOperationProvider : NSObject <PDSPLCAccountOperationProvider>
@end

NS_ASSUME_NONNULL_END
