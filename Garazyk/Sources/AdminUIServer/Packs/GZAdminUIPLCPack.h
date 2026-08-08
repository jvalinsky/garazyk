// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

NS_ASSUME_NONNULL_BEGIN

/** @abstract Admin UI pack for the PLC surface. */
@interface GZAdminUIPLCPack : NSObject <GZAdminUIPack>

/** @abstract Renders a PLC DID lookup result. */
+ (NSString *)renderPLCDIDPartial:(NSDictionary *)result;
/** @abstract Renders PLC operation-log entries. */
+ (NSString *)renderPLCLogPartial:(NSDictionary *)result;
/** @abstract Renders PLC health. */
+ (NSString *)renderPLCHealthPartial:(NSDictionary *)result;
/** @abstract Renders PLC metrics. */
+ (NSString *)renderPLCMetricsPartial:(NSDictionary *)result;
/** @abstract Renders a paginated PLC listing using the supplied cursor. */
+ (NSString *)renderPLCListPartial:(NSDictionary *)result cursor:(nullable NSString *)cursor;

@end

NS_ASSUME_NONNULL_END
