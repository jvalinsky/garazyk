#import "GermMailboxSchemaManager.h"

@implementation GermMailboxSchemaManager

+ (instancetype)sharedManager {
    static GermMailboxSchemaManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[GermMailboxSchemaManager alloc] init];
    });
    return shared;
}

- (NSString *)mailboxesTableSchema {
    // Ephemeral addresses: single-use, assigned to agents (not DIDs).
    // The server cannot link an address to a conversation or DID.
    // Addresses are claimed in batches and distributed within the
    // E2EE channel, so the server never sees which DID uses which
    // address.
    return @"CREATE TABLE IF NOT EXISTS germ_mailboxes ("
           "    address TEXT PRIMARY KEY,"
           "    agent_ref TEXT NOT NULL,"
           "    device_token TEXT,"
           "    expires_at TEXT NOT NULL,"
           "    created_at TEXT NOT NULL DEFAULT (datetime('now'))"
           ")";
}

- (NSString *)mailboxMessagesTableSchema {
    // Messages stored at ephemeral addresses. The server stores only
    // ciphertext — it cannot decrypt message content. Messages are
    // deleted after polling.
    return @"CREATE TABLE IF NOT EXISTS germ_mailbox_messages ("
           "    id TEXT PRIMARY KEY,"
           "    address TEXT NOT NULL,"
           "    ciphertext BLOB NOT NULL,"
           "    created_at TEXT NOT NULL DEFAULT (datetime('now')),"
           "    FOREIGN KEY (address) REFERENCES germ_mailboxes(address) ON DELETE CASCADE"
           ")";
}

- (NSString *)rendezvousTableSchema {
    // Rendezvous addresses: derived from MLS epoch secrets, stable
    // within an epoch for reconnection. Change with each epoch.
    // The server cannot link a rendezvous address to a DID.
    return @"CREATE TABLE IF NOT EXISTS germ_rendezvous ("
           "    address TEXT PRIMARY KEY,"
           "    agent_ref TEXT NOT NULL,"
           "    epoch INTEGER NOT NULL DEFAULT 0,"
           "    created_at TEXT NOT NULL DEFAULT (datetime('now'))"
           ")";
}

- (NSString *)rendezvousMessagesTableSchema {
    // Messages stored at rendezvous addresses. Same ciphertext-only
    // storage as ephemeral mailboxes.
    return @"CREATE TABLE IF NOT EXISTS germ_rendezvous_messages ("
           "    id TEXT PRIMARY KEY,"
           "    address TEXT NOT NULL,"
           "    ciphertext BLOB NOT NULL,"
           "    created_at TEXT NOT NULL DEFAULT (datetime('now')),"
           "    FOREIGN KEY (address) REFERENCES germ_rendezvous(address) ON DELETE CASCADE"
           ")";
}

- (NSString *)mailboxSchemaSQL {
    NSMutableString *sql = [NSMutableString string];
    [sql appendString:[self mailboxesTableSchema]];
    [sql appendString:@";\n"];
    [sql appendString:[self mailboxMessagesTableSchema]];
    [sql appendString:@";\n"];
    [sql appendString:[self rendezvousTableSchema]];
    [sql appendString:@";\n"];
    [sql appendString:[self rendezvousMessagesTableSchema]];
    [sql appendString:@";\n"];

    // Indexes for polling: look up messages by address
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_mailbox_messages_address ON germ_mailbox_messages(address);"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_rendezvous_messages_address ON germ_rendezvous_messages(address);"];

    // Index for expiration cleanup
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_mailboxes_expires ON germ_mailboxes(expires_at);"];

    return sql;
}

@end
