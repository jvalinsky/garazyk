// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GermMailboxService.h

 @abstract Service layer for Germ E2EE mailbox transport.

 @discussion Manages ephemeral and rendezvous mailbox addresses and
 their ciphertext messages. Addresses are opaque strings assigned to
 agents (not DIDs) to protect metadata. The server never learns which
 DID owns which address, nor can it decrypt message content.

 Models after Germ's current shipping 1:1 E2EE DM product.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@protocol PDSQueryDatabase;

NS_ASSUME_NONNULL_BEGIN

@interface GermMailboxService : NSObject

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database;

#pragma mark - Ephemeral Addresses

/*!
 @method claimAddresses:count:error:

 @abstract Claims a batch of ephemeral mailbox addresses for an agent.

 @param agentRef Opaque agent reference (not a DID).
 @param count Number of addresses to claim (1-100).
 @param error Output parameter for errors.

 @return Array of claimed address strings, or nil on error.

 @discussion Addresses are random opaque strings. The server cannot
 link them to a DID or conversation. Addresses expire after a
 configurable TTL.
 */
- (nullable NSArray<NSString *> *)claimAddressesForAgent:(NSString *)agentRef
                                                   count:(NSInteger)count
                                                   error:(NSError **)error;

#pragma mark - Mailbox Delivery

/*!
 @method deliverCiphertext:toAddress:error:

 @abstract Delivers an E2EE ciphertext to a mailbox address.

 @param ciphertext The encrypted message blob.
 @param address The target mailbox address.
 @param error Output parameter for errors.

 @return YES if delivery succeeded, NO otherwise.

 @discussion The server stores only ciphertext — it cannot decrypt
 or inspect message content. Delivery fails if the address does not
 exist or has expired.
 */
- (BOOL)deliverCiphertext:(NSData *)ciphertext
               toAddress:(NSString *)address
                    error:(NSError **)error;

#pragma mark - Mailbox Polling

/*!
 @method pollMessagesForAgent:error:

 @abstract Retrieves and deletes all pending ciphertexts for an agent.

 @param agentRef The agent reference to poll for.
 @param error Output parameter for errors.

 @return Array of dictionaries with "ciphertext" (NSData) and "address" (NSString) keys.

 @discussion Messages are deleted after polling (single-read semantics).
 The server cannot decrypt the ciphertexts.
 */
- (nullable NSArray<NSDictionary *> *)pollMessagesForAgent:(NSString *)agentRef
                                                     error:(NSError **)error;

#pragma mark - Rendezvous Addresses

/*!
 @method registerRendezvousAddress:forAgent:epoch:error:

 @abstract Registers a rendezvous address for an agent.

 @param address The rendezvous address (derived from epoch secrets).
 @param agentRef Opaque agent reference.
 @param epoch The MLS epoch this address is valid for.
 @param error Output parameter for errors.

 @return YES if registration succeeded, NO otherwise.

 @discussion Rendezvous addresses are stable within an MLS epoch
 for reconnection. They rotate with each epoch.
 */
- (BOOL)registerRendezvousAddress:(NSString *)address
                         forAgent:(NSString *)agentRef
                           epoch:(NSInteger)epoch
                           error:(NSError **)error;

/*!
 @method deliverToRendezvous:address:error:

 @abstract Delivers ciphertext to a rendezvous address.

 @param ciphertext The encrypted message blob.
 @param address The rendezvous address.
 @param error Output parameter for errors.

 @return YES if delivery succeeded, NO otherwise.
 */
- (BOOL)deliverToRendezvous:(NSData *)ciphertext
                    address:(NSString *)address
                     error:(NSError **)error;

/*!
 @method pollRendezvousForAgent:error:

 @abstract Retrieves and deletes pending ciphertexts from an agent's
 rendezvous address.

 @param agentRef The agent reference.
 @param error Output parameter for errors.

 @return Array of dictionaries with "ciphertext" and "address" keys.
 */
- (nullable NSArray<NSDictionary *> *)pollRendezvousForAgent:(NSString *)agentRef
                                                       error:(NSError **)error;

#pragma mark - Maintenance

/*!
 @method expireStaleAddresses

 @abstract Removes expired ephemeral addresses and their messages.

 @discussion Should be called periodically. Addresses past their
 expires_at are deleted along with any undelivered messages.
 */
- (void)expireStaleAddresses;

@end

NS_ASSUME_NONNULL_END
