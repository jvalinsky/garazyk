// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Embedded admin UI pack for the Germ E2EE mailbox service.
 * @discussion Privacy-first dashboard — never renders ciphertext, mailbox
 * addresses, agent references, or row-level message history.
 */
@interface GermAdminUIPack : NSObject <GZAdminUIPack>

@end

NS_ASSUME_NONNULL_END
