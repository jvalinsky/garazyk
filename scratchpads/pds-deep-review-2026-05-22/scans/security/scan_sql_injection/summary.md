# Objective-C SQL Injection Deep Scan

- Root: .
- Scan path: ./Garazyk/Sources
- Generated: 2026-05-22T18:10:03Z

## Counts
- SQL with string formatting: 22
- SQL with string concatenation: 5
- SQL execution points: 818
- Prepared statement sites: 88
- Parameter binding sites: 196
- Dynamic table/column names: 11
- WHERE clause with format: 7
- Safe parameterized queries: 424

## High priority (format + exec in same file)
- ./Garazyk/Sources/AppView/Services/FeedService.m
- ./Garazyk/Sources/AppView/Services/GroupService.m
- ./Garazyk/Sources/Database/ActorStore/ActorStore.m
- ./Garazyk/Sources/Database/Migrations/PDSMigrationManager.m
- ./Garazyk/Sources/Database/PDSDatabase+Accounts.m
- ./Garazyk/Sources/Database/PDSDatabase+Records.m
- ./Garazyk/Sources/Network/XrpcChatBskyConvoPack.m
- ./Garazyk/Sources/Ozone/Services/ModerationService.m
- ./Garazyk/Sources/Services/Core/PDSAdminService.m

## Detailed findings

### SQL with string formatting
  ./Garazyk/Sources/Services/Core/PDSAdminService.m:397:        NSString *codeSQL = [NSString stringWithFormat:@"UPDATE invite_codes SET disabled = 1 WHERE code IN (%@)",
  ./Garazyk/Sources/Services/Core/PDSAdminService.m:405:        NSString *accountSQL = [NSString stringWithFormat:@"UPDATE invite_codes SET disabled = 1 WHERE account_did IN (%@)",
  ./Garazyk/Sources/Ozone/Services/ModerationService.m:468:    NSString *sql = [NSString stringWithFormat:@"UPDATE moderation_templates SET %@ WHERE id = ?", [updates componentsJoinedByString:@", "]];
  ./Garazyk/Sources/Database/PDSDatabase+Records.m:19:    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM records WHERE uri = ?", kRecordsColumns];
  ./Garazyk/Sources/Database/PDSDatabase+Records.m:38:    NSMutableString *sql = [NSMutableString stringWithFormat:@"SELECT %@ FROM records WHERE did = ?", kRecordsColumns];
  ./Garazyk/Sources/Database/ActorStore/ActorStore.m:151:    NSString *checkMarkerSQL = [NSString stringWithFormat:@"SELECT name FROM sqlite_master WHERE type='table' AND name='%@'", schemaMarkerTable];
  ./Garazyk/Sources/Database/ActorStore/ActorStore.m:601:    return [self.database executeUnsafeRawSQL:[NSString stringWithFormat:@"ALTER TABLE %@ ADD COLUMN %@ %@", tableName, columnName, type] error:nil];
  ./Garazyk/Sources/AppView/Services/FeedService.m:400:    NSMutableString *query = [NSMutableString stringWithFormat:@"SELECT did, rkey, cid, value FROM records WHERE did IN (%@) AND collection = ?",
  ./Garazyk/Sources/Database/PDSDatabase+OAuthClients.m:147:    NSString *sql = [NSString stringWithFormat:@"INSERT OR REPLACE INTO oauth_clients (%@) VALUES (%@)",
  ./Garazyk/Sources/Database/PDSDatabase+Accounts.m:139:    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM accounts WHERE did = ?", kAccountsColumns];
  ./Garazyk/Sources/Database/PDSDatabase+Accounts.m:145:    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM accounts WHERE handle = ?", kAccountsColumns];
  ./Garazyk/Sources/Database/PDSDatabase+Accounts.m:152:    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM accounts WHERE email = ?", kAccountsColumns];
  ./Garazyk/Sources/Database/PDSDatabase+Accounts.m:161:    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM accounts WHERE refresh_jwt = ?", kAccountsColumns];
  ./Garazyk/Sources/Database/PDSDatabase+Accounts.m:190:    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM accounts ORDER BY created_at DESC", kAccountsColumns];
  ./Garazyk/Sources/Database/PDSDatabase+Accounts.m:199:        ? [NSString stringWithFormat:@"SELECT %@ FROM accounts WHERE did > ? ORDER BY did ASC LIMIT ?", kAccountsColumns]
  ./Garazyk/Sources/Database/PDSDatabase+Accounts.m:200:        : [NSString stringWithFormat:@"SELECT %@ FROM accounts ORDER BY did ASC LIMIT ?", kAccountsColumns];
  ./Garazyk/Sources/Database/Migrations/PDSMigrationManager.m:71:        NSString *sql = [NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table];
  ./Garazyk/Sources/Database/Migrations/PDSMigrationManager.m:129:        NSString *sql = [NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table];
  ./Garazyk/Sources/Database/Migrations/PDSMigrationManager.m:498:        NSString *sql = [NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table];
  ./Garazyk/Sources/Network/XrpcChatBskyConvoPack.m:999:        NSString *query = [NSString stringWithFormat:@"SELECT did, handle FROM accounts WHERE did IN (%@)", placeholders];
  ... and 2 more

### Dynamic table/column names
  ./Garazyk/Sources/Germ/Server/Services/GermMailboxService.m:168:                               @"DELETE FROM germ_mailbox_messages WHERE id IN (%@)", placeholders];
  ./Garazyk/Sources/Germ/Server/Services/GermMailboxService.m:293:                               @"DELETE FROM germ_rendezvous_messages WHERE id IN (%@)", placeholders];
  ./Garazyk/Sources/Database/PDSDatabase+OAuthClients.m:147:    NSString *sql = [NSString stringWithFormat:@"INSERT OR REPLACE INTO oauth_clients (%@) VALUES (%@)",
  ./Garazyk/Sources/Database/ActorStore/ActorStore.m:151:    NSString *checkMarkerSQL = [NSString stringWithFormat:@"SELECT name FROM sqlite_master WHERE type='table' AND name='%@'", schemaMarkerTable];
  ./Garazyk/Sources/Database/ActorStore/ActorStore.m:601:    return [self.database executeUnsafeRawSQL:[NSString stringWithFormat:@"ALTER TABLE %@ ADD COLUMN %@ %@", tableName, columnName, type] error:nil];
  ./Garazyk/Sources/Database/Migrations/PDSMigrationManager.m:71:        NSString *sql = [NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table];
  ./Garazyk/Sources/Database/Migrations/PDSMigrationManager.m:129:        NSString *sql = [NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table];
  ./Garazyk/Sources/Database/Migrations/PDSMigrationManager.m:498:        NSString *sql = [NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table];
  ./Garazyk/Sources/AppView/Services/FeedService.m:400:    NSMutableString *query = [NSMutableString stringWithFormat:@"SELECT did, rkey, cid, value FROM records WHERE did IN (%@) AND collection = ?",
  ./Garazyk/Sources/Network/XrpcChatBskyConvoPack.m:999:        NSString *query = [NSString stringWithFormat:@"SELECT did, handle FROM accounts WHERE did IN (%@)", placeholders];

### WHERE clause with format strings
  ./Garazyk/Sources/Services/Core/PDSAdminService.m:397:        NSString *codeSQL = [NSString stringWithFormat:@"UPDATE invite_codes SET disabled = 1 WHERE code IN (%@)",
  ./Garazyk/Sources/Services/Core/PDSAdminService.m:405:        NSString *accountSQL = [NSString stringWithFormat:@"UPDATE invite_codes SET disabled = 1 WHERE account_did IN (%@)",
  ./Garazyk/Sources/Germ/Server/Services/GermMailboxService.m:168:                               @"DELETE FROM germ_mailbox_messages WHERE id IN (%@)", placeholders];
  ./Garazyk/Sources/Germ/Server/Services/GermMailboxService.m:293:                               @"DELETE FROM germ_rendezvous_messages WHERE id IN (%@)", placeholders];
  ./Garazyk/Sources/AppView/Services/FeedService.m:400:    NSMutableString *query = [NSMutableString stringWithFormat:@"SELECT did, rkey, cid, value FROM records WHERE did IN (%@) AND collection = ?",
  ./Garazyk/Sources/Network/XrpcChatBskyConvoPack.m:999:        NSString *query = [NSString stringWithFormat:@"SELECT did, handle FROM accounts WHERE did IN (%@)", placeholders];
  ./Garazyk/Sources/Database/ActorStore/ActorStore.m:151:    NSString *checkMarkerSQL = [NSString stringWithFormat:@"SELECT name FROM sqlite_master WHERE type='table' AND name='%@'", schemaMarkerTable];

## Notes
- Format strings in SQL context require manual review.
- Check if format arguments are user-controlled.
- Prepared statements with bind are the safe pattern.
- Dynamic table names need whitelisting, not escaping.
