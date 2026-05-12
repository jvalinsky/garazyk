// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "GermMailboxService.h"
#import "Database/PDSDatabase.h"
#import "Debug/GZLogger.h"

// Default TTL for ephemeral addresses (24 hours in seconds)
static const NSTimeInterval kGermMailboxDefaultTTL = 86400.0;

// Maximum number of addresses claimable in a single batch
static const NSInteger kGermMailboxMaxClaimCount = 100;

// Address length in bytes (before base64 encoding)
static const NSInteger kGermAddressByteLength = 32;

@interface GermMailboxService ()
@property (nonatomic, unsafe_unretained) id<PDSQueryDatabase> database;
@end

@implementation GermMailboxService

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database {
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}

#pragma mark - Ephemeral Addresses

- (nullable NSArray<NSString *> *)claimAddressesForAgent:(NSString *)agentRef
                                                   count:(NSInteger)count
                                                   error:(NSError **)error {
    if (!agentRef || agentRef.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermMailbox"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Agent reference is required"}];
        }
        return nil;
    }

    if (count < 1 || count > kGermMailboxMaxClaimCount) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermMailbox"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                     [NSString stringWithFormat:@"Count must be between 1 and %ld",
                                                      (long)kGermMailboxMaxClaimCount]}];
        }
        return nil;
    }

    NSMutableArray<NSString *> *addresses = [NSMutableArray arrayWithCapacity:count];
    NSString *expiresAt = [self expiryDateFromNow:kGermMailboxDefaultTTL];

    for (NSInteger i = 0; i < count; i++) {
        NSString *address = [self generateOpaqueAddress];
        NSString *sql = @"INSERT INTO germ_mailboxes (address, agent_ref, expires_at) VALUES (?, ?, ?)";

        BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:sql
                                                                          params:@[address, agentRef, expiresAt]
                                                                           error:error];
        if (!success) {
            GZ_LOG_ERROR(@"Failed to claim mailbox address: %@", *error ?: @"unknown error");
            return nil;
        }
        [addresses addObject:address];
    }

    GZ_LOG_DEBUG(@"Claimed %ld ephemeral addresses for agent", (long)count);
    return [addresses copy];
}

#pragma mark - Mailbox Delivery

- (BOOL)deliverCiphertext:(NSData *)ciphertext
               toAddress:(NSString *)address
                    error:(NSError **)error {
    if (!ciphertext || !address) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermMailbox"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Ciphertext and address are required"}];
        }
        return NO;
    }

    // Verify the address exists and hasn't expired
    NSString *checkSQL = @"SELECT address FROM germ_mailboxes WHERE address = ? AND datetime(expires_at) > datetime('now')";
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:checkSQL
                                                                     params:@[address]
                                                                      error:error];
    if (!rows) {
        GZ_LOG_ERROR(@"Mailbox address lookup failed: %@", *error ?: @"unknown error");
        return NO;
    }

    if (rows.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermMailbox"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Address not found or expired"}];
        }
        return NO;
    }

    // Insert the ciphertext
    NSString *messageId = [self generateMessageId];
    NSString *sql = @"INSERT INTO germ_mailbox_messages (id, address, ciphertext) VALUES (?, ?, ?)";
    BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:sql
                                                                     params:@[messageId, address, ciphertext]
                                                                      error:error];
    if (!success) {
        GZ_LOG_ERROR(@"Failed to deliver ciphertext to mailbox: %@", *error ?: @"unknown error");
        return NO;
    }

    GZ_LOG_DEBUG(@"Delivered ciphertext to ephemeral address");
    return YES;
}

#pragma mark - Mailbox Polling

- (nullable NSArray<NSDictionary *> *)pollMessagesForAgent:(NSString *)agentRef
                                                     error:(NSError **)error {
    if (!agentRef || agentRef.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermMailbox"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Agent reference is required"}];
        }
        return nil;
    }

    // Fetch all messages for the agent's addresses
    NSString *fetchSQL = @"SELECT m.id, m.address, m.ciphertext "
                         @"FROM germ_mailbox_messages m "
                         @"INNER JOIN germ_mailboxes b ON m.address = b.address "
                         @"WHERE b.agent_ref = ? "
                         @"ORDER BY m.created_at ASC";
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:fetchSQL
                                                                     params:@[agentRef]
                                                                      error:error];
    if (!rows) {
        GZ_LOG_ERROR(@"Failed to poll mailbox messages: %@", *error ?: @"unknown error");
        return nil;
    }

    NSMutableArray<NSDictionary *> *messages = [NSMutableArray arrayWithCapacity:rows.count];
    NSMutableArray<NSString *> *messageIds = [NSMutableArray arrayWithCapacity:rows.count];

    for (NSDictionary *row in rows) {
        [messages addObject:@{
            @"ciphertext": row[@"ciphertext"] ?: [NSData data],
            @"address": row[@"address"] ?: @""
        }];
        if (row[@"id"]) {
            [messageIds addObject:row[@"id"]];
        }
    }

    // Delete polled messages (single-read semantics)
    if (messageIds.count > 0) {
        NSString *placeholders = [self placeholderListForCount:messageIds.count];
        NSString *deleteSQL = [NSString stringWithFormat:
                               @"DELETE FROM germ_mailbox_messages WHERE id IN (%@)", placeholders];
        [(PDSDatabase *)self.database executeParameterizedUpdate:deleteSQL
                                                          params:messageIds
                                                           error:nil];
    }

    GZ_LOG_DEBUG(@"Polled %lu messages for agent", (unsigned long)messages.count);
    return [messages copy];
}

#pragma mark - Rendezvous Addresses

- (BOOL)registerRendezvousAddress:(NSString *)address
                         forAgent:(NSString *)agentRef
                           epoch:(NSInteger)epoch
                           error:(NSError **)error {
    if (!address || !agentRef) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermMailbox"
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Address and agent reference are required"}];
        }
        return NO;
    }

    // Upsert: replace if the agent already has a rendezvous address
    // for this epoch
    NSString *sql = @"INSERT OR REPLACE INTO germ_rendezvous (address, agent_ref, epoch) "
                    @"VALUES (?, ?, ?)";
    BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:sql
                                                                     params:@[address, agentRef, @(epoch)]
                                                                      error:error];
    if (!success) {
        GZ_LOG_ERROR(@"Failed to register rendezvous address: %@", *error ?: @"unknown error");
        return NO;
    }

    GZ_LOG_DEBUG(@"Registered rendezvous address for epoch %ld", (long)epoch);
    return YES;
}

- (BOOL)deliverToRendezvous:(NSData *)ciphertext
                    address:(NSString *)address
                     error:(NSError **)error {
    if (!ciphertext || !address) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermMailbox"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Ciphertext and address are required"}];
        }
        return NO;
    }

    // Verify the rendezvous address exists
    NSString *checkSQL = @"SELECT address FROM germ_rendezvous WHERE address = ?";
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:checkSQL
                                                                     params:@[address]
                                                                      error:error];
    if (!rows) {
        return NO;
    }

    if (rows.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermMailbox"
                                         code:6
                                     userInfo:@{NSLocalizedDescriptionKey: @"Rendezvous address not found"}];
        }
        return NO;
    }

    NSString *messageId = [self generateMessageId];
    NSString *sql = @"INSERT INTO germ_rendezvous_messages (id, address, ciphertext) VALUES (?, ?, ?)";
    BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:sql
                                                                     params:@[messageId, address, ciphertext]
                                                                      error:error];
    if (!success) {
        GZ_LOG_ERROR(@"Failed to deliver to rendezvous address: %@", *error ?: @"unknown error");
        return NO;
    }

    GZ_LOG_DEBUG(@"Delivered ciphertext to rendezvous address");
    return YES;
}

- (nullable NSArray<NSDictionary *> *)pollRendezvousForAgent:(NSString *)agentRef
                                                       error:(NSError **)error {
    if (!agentRef || agentRef.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GermMailbox"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Agent reference is required"}];
        }
        return nil;
    }

    NSString *fetchSQL = @"SELECT m.id, m.address, m.ciphertext "
                         @"FROM germ_rendezvous_messages m "
                         @"INNER JOIN germ_rendezvous r ON m.address = r.address "
                         @"WHERE r.agent_ref = ? "
                         @"ORDER BY m.created_at ASC";
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:fetchSQL
                                                                     params:@[agentRef]
                                                                      error:error];
    if (!rows) {
        return nil;
    }

    NSMutableArray<NSDictionary *> *messages = [NSMutableArray arrayWithCapacity:rows.count];
    NSMutableArray<NSString *> *messageIds = [NSMutableArray arrayWithCapacity:rows.count];

    for (NSDictionary *row in rows) {
        [messages addObject:@{
            @"ciphertext": row[@"ciphertext"] ?: [NSData data],
            @"address": row[@"address"] ?: @""
        }];
        if (row[@"id"]) {
            [messageIds addObject:row[@"id"]];
        }
    }

    // Delete polled messages
    if (messageIds.count > 0) {
        NSString *placeholders = [self placeholderListForCount:messageIds.count];
        NSString *deleteSQL = [NSString stringWithFormat:
                               @"DELETE FROM germ_rendezvous_messages WHERE id IN (%@)", placeholders];
        [(PDSDatabase *)self.database executeParameterizedUpdate:deleteSQL
                                                          params:messageIds
                                                           error:nil];
    }

    return [messages copy];
}

#pragma mark - Maintenance

- (void)expireStaleAddresses {
    // Delete expired ephemeral addresses (cascades to messages)
    NSString *sql = @"DELETE FROM germ_mailboxes WHERE datetime(expires_at) <= datetime('now')";
    [(PDSDatabase *)self.database executeParameterizedUpdate:sql params:@[] error:nil];
    GZ_LOG_DEBUG(@"Expired stale mailbox addresses");
}

#pragma mark - Private Helpers

- (NSString *)generateOpaqueAddress {
    // Generate a cryptographically random 32-byte address, base64url-encoded.
    // The address is opaque — the server cannot link it to a DID or conversation.
    NSMutableData *data = [NSMutableData dataWithLength:kGermAddressByteLength];
    arc4random_buf(data.mutableBytes, kGermAddressByteLength);
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    // Convert to base64url
    NSMutableString *urlSafe = [base64 mutableCopy];
    [urlSafe replaceOccurrencesOfString:@"+" withString:@"-" options:0 range:NSMakeRange(0, urlSafe.length)];
    [urlSafe replaceOccurrencesOfString:@"/" withString:@"_" options:0 range:NSMakeRange(0, urlSafe.length)];
    [urlSafe replaceOccurrencesOfString:@"=" withString:@"" options:0 range:NSMakeRange(0, urlSafe.length)];
    return [urlSafe copy];
}

- (NSString *)generateMessageId {
    // TID-style message ID for internal use
    return [NSString stringWithFormat:@"germ-msg-%@", [[NSUUID UUID] UUIDString]];
}

- (NSString *)expiryDateFromNow:(NSTimeInterval)ttlSeconds {
    NSDate *expiry = [NSDate dateWithTimeIntervalSinceNow:ttlSeconds];
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    return [formatter stringFromDate:expiry];
}

- (NSString *)placeholderListForCount:(NSInteger)count {
    NSMutableArray *parts = [NSMutableArray arrayWithCapacity:count];
    for (NSInteger i = 0; i < count; i++) {
        [parts addObject:@"?"];
    }
    return [parts componentsJoinedByString:@", "];
}

@end
