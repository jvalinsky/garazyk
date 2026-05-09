/*!
 @file PDSOAuthOnlyRegistrationGate.h

 @abstract OAuth-only registration gate.

 @discussion
    Rejects direct API account creation (createAccount XRPC), requiring
    registration to go through the OAuth2 flow. This is used when the
    PDS operator wants all signups to go through a specific OAuth client
    (e.g., a branded app or web portal) rather than allowing direct
    programmatic account creation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Registration/PDSRegistrationGate.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSOAuthOnlyRegistrationGate

 @abstract Rejects direct API signups, requiring OAuth2-based registration.
 */
@interface PDSOAuthOnlyRegistrationGate : NSObject <PDSRegistrationGate>
@end

NS_ASSUME_NONNULL_END
