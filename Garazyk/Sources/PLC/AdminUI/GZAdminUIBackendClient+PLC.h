// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

/** PLC protocol operations used only by the PLC-owned admin pack. */
@interface GZAdminUIBackendClient (PLC)
- (NSDictionary *)lookupDID:(NSString *)did;
- (NSDictionary *)fetchPLCLogForDID:(NSString *)did;
- (NSDictionary *)fetchPLCHealth;
- (NSDictionary *)fetchPLCMetrics;
- (NSDictionary *)fetchPLCList;
- (NSDictionary *)fetchPLCExportWithAfter:(nullable NSString *)after count:(NSUInteger)count;
@end

NS_ASSUME_NONNULL_END
