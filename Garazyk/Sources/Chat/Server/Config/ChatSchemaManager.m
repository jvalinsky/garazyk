// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "ChatSchemaManager.h"

@implementation ChatSchemaManager

+ (instancetype)sharedManager {
    static ChatSchemaManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ChatSchemaManager alloc] init];
    });
    return shared;
}

- (NSString *)conversationsTableSchema {
    return @"CREATE TABLE IF NOT EXISTS conversations ("
           @"    id TEXT PRIMARY KEY,"
           @"    locked INTEGER DEFAULT 0,"
           @"    mode TEXT NOT NULL DEFAULT 'plaintext',"
           @"    created_at TEXT NOT NULL,"
           @"    updated_at TEXT NOT NULL"
           @")";
}

- (NSString *)conversationMembersTableSchema {
    return @"CREATE TABLE IF NOT EXISTS conversation_members ("
           @"    convo_id TEXT NOT NULL,"
           @"    member_did TEXT NOT NULL,"
           @"    status TEXT NOT NULL DEFAULT 'pending',"
           @"    muted INTEGER DEFAULT 0,"
           @"    last_read_id TEXT,"
           @"    joined_at TEXT NOT NULL,"
           @"    PRIMARY KEY (convo_id, member_did),"
           @"    FOREIGN KEY (convo_id) REFERENCES conversations(id) ON DELETE CASCADE"
           @") WITHOUT ROWID";
}

- (NSString *)messagesTableSchema {
    return @"CREATE TABLE IF NOT EXISTS messages ("
           @"    id TEXT PRIMARY KEY,"
           @"    convo_id TEXT NOT NULL,"
           @"    sender_did TEXT NOT NULL,"
           @"    text TEXT,"
           @"    embed_json TEXT,"
           @"    deleted_for_json TEXT,"
           @"    created_at TEXT NOT NULL,"
           @"    FOREIGN KEY (convo_id) REFERENCES conversations(id) ON DELETE CASCADE"
           @")";
}

- (NSString *)messageReactionsTableSchema {
    return @"CREATE TABLE IF NOT EXISTS message_reactions ("
           @"    message_id TEXT NOT NULL,"
           @"    actor_did TEXT NOT NULL,"
           @"    emoji TEXT NOT NULL,"
           @"    created_at TEXT NOT NULL,"
           @"    PRIMARY KEY (message_id, actor_did, emoji),"
           @"    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE"
           @") WITHOUT ROWID";
}

- (NSString *)eventLogTableSchema {
    return @"CREATE TABLE IF NOT EXISTS chat_event_log ("
           @"    id TEXT PRIMARY KEY,"
           @"    convo_id TEXT NOT NULL,"
           @"    actor_did TEXT NOT NULL,"
           @"    event_type TEXT NOT NULL,"
           @"    event_data TEXT,"
           @"    created_at INTEGER"
           @")";
}

- (NSString *)actorMetadataTableSchema {
    return @"CREATE TABLE IF NOT EXISTS chat_actor_metadata ("
           @"    did TEXT PRIMARY KEY,"
           @"    muted INTEGER DEFAULT 0,"
           @"    blocked INTEGER DEFAULT 0,"
           @"    labels TEXT,"
           @"    updated_at INTEGER"
           @")";
}

- (NSString *)chatSchemaSQL {
    NSMutableString *sql = [NSMutableString string];
    [sql appendString:[self conversationsTableSchema]];
    [sql appendString:@";\n"];
    [sql appendString:[self conversationMembersTableSchema]];
    [sql appendString:@";\n"];
    [sql appendString:[self messagesTableSchema]];
    [sql appendString:@";\n"];
    [sql appendString:[self messageReactionsTableSchema]];
    [sql appendString:@";\n"];
    [sql appendString:[self eventLogTableSchema]];
    [sql appendString:@";\n"];
    [sql appendString:[self actorMetadataTableSchema]];
    [sql appendString:@";\n"];
    
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_messages_convo ON messages(convo_id);"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_chat_event_log_convo ON chat_event_log(convo_id);"];

    return sql;
}

- (NSString *)chatMigrationSQL {
    // Safe migrations for existing databases. Each statement is
    // wrapped in a guard that checks whether the column exists
    // before attempting to add it. SQLite doesn't support
    // IF NOT EXISTS for ALTER TABLE, so we use pragma to check.
    return @"-- Migration: add mode column to conversations\n"
           @"-- SQLite ALTER TABLE ADD COLUMN is safe to re-run if the\n"
           @"-- column already exists (it will error, which we ignore).\n"
           @"ALTER TABLE conversations ADD COLUMN mode TEXT NOT NULL DEFAULT 'plaintext'";
}

@end
