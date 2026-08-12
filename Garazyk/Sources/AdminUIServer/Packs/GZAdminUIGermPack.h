// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Admin UI pack for the Germ E2EE mailbox surface.
 * @discussion Privacy-first dashboard — never renders ciphertext, mailbox
 * addresses, agent references, DID mappings, or row-level message history.
 * All counters are aggregate-only. Read-only in the first release.
 */
@interface GZAdminUIGermPack : NSObject <GZAdminUIPack>

/** @abstract Renders the Germ overview dashboard with privacy-safe aggregate counters. */
+ (NSString *)renderGermOverviewHTML;

/** @abstract Renders Germ health status. */
+ (NSString *)renderGermHealthPartial:(NSDictionary *)result;

@end

NS_ASSUME_NONNULL_END
