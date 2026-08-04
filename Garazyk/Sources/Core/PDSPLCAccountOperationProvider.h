// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @protocol PDSPLCAccountOperationProvider
 * @brief Protocol-backed PLC operation signing for account creation.
 *
 * Account services need a signed genesis operation, but must not depend on the
 * PLC module's rotation-key storage or operation model. The application injects
 * a PLC-owned implementation at composition time.
 */
@protocol PDSPLCAccountOperationProvider <NSObject>

/** The server rotation public key in did:key form. */
@property (nonatomic, copy, readonly, nullable) NSString *rotationKeyDidKey;

/** Loads the persistent key or creates it when absent. */
- (BOOL)loadOrGenerateKeyWithError:(NSError **)error;

/** Signs the unsigned operation and returns the complete signed dictionary. */
- (nullable NSDictionary *)signedOperationForUnsignedData:(NSDictionary *)unsignedData
                                                   error:(NSError **)error;

/** Derives a did:plc from the complete signed operation dictionary. */
- (nullable NSString *)didForSignedOperation:(NSDictionary *)signedOperation
                                       error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
