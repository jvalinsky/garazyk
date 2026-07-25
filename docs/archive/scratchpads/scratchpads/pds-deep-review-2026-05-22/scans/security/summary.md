# Objective-C Security Audit — Combined Summary

- Root: .
- Generated: 2026-05-22T18:10:03Z

## scan_sql_injection
### Objective-C SQL Injection Deep Scan

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

## scan_crypto
### Objective-C Cryptographic Security Scan

- Root: .
- Scan path: ./Garazyk/Sources
- Generated: 2026-05-22T18:10:03Z

## Counts
- Weak hash usage (MD5/SHA1): 4
- Weak encryption (DES/3DES/RC4): 8
- Hardcoded key references: 17
- Hardcoded IV references: 4
- Timing-vulnerable comparisons: 46
- Weak random usage: 2
- ECB mode usage: 1
- Secure random usage: 26

## Files with potential crypto issues
- ./Garazyk/Sources/AppView/Services/ContactService.m
- ./Garazyk/Sources/AppView/Services/GraphService.m
- ./Garazyk/Sources/Auth/OAuth2.m
- ./Garazyk/Sources/Auth/OAuth2Handler.m
- ./Garazyk/Sources/Auth/OAuthClientAuthPolicy.m
- ./Garazyk/Sources/Auth/OAuthProvider/OAuthProvider.m
- ./Garazyk/Sources/Auth/PDSAppleKeyManager.m
- ./Garazyk/Sources/Auth/PDSOpenSSLSessionKeyManager.m
- ./Garazyk/Sources/Blob/MimeTypeValidator.m
- ./Garazyk/Sources/CLI/PDSCLIAccountCommand.m
- ./Garazyk/Sources/CLI/PDSCLIAdminCommand.m
- ./Garazyk/Sources/CLI/PDSCLIDispatcher.m
- ./Garazyk/Sources/CLI/PDSCLIInputHelper.m
- ./Garazyk/Sources/CLI/PDSCLIOAuthCommand.m
- ./Garazyk/Sources/Compat/PlatformShims/CommonCrypto/CommonCryptor.h
- ./Garazyk/Sources/Compat/PlatformShims/CommonCrypto/CommonDigest.h
- ./Garazyk/Sources/Compat/PlatformShims/CoreFoundation/CFBase.h
- ./Garazyk/Sources/Core/ATProtoCBORSerialization.m
- ./Garazyk/Sources/Core/ATProtoDagCBOR.m
- ./Garazyk/Sources/Core/ATProtoValidator.m
- ./Garazyk/Sources/Core/ATURI.m
- ./Garazyk/Sources/Core/DID.m
- ./Garazyk/Sources/Database/Utils/ATProtoDatabaseUtilities.h
- ./Garazyk/Sources/Email/PDSEmailProviderFactory.m
- ./Garazyk/Sources/Lexicon/ATProtoLexiconValidator.m
- ./Garazyk/Sources/Network/SSRFValidator.m
- ./Garazyk/Sources/Network/WebSocketUpgradeHandler.m
- ./Garazyk/Sources/Network/XrpcAdminPack.m
- ./Garazyk/Sources/Network/XrpcAuthHelper.m
- ./Garazyk/Sources/Repository/CBOR.m
- ./Garazyk/Sources/Repository/MST.m
- ./Garazyk/Sources/Security/PDSKeyEnvelope.m
- ./Garazyk/Sources/Sync/WebSocket/WebSocketConnection.m
- ./Garazyk/Sources/Video/VideoJWTAuthProvider.m

## Detailed findings

### Weak hash algorithms (MD5/SHA1)
  ./Garazyk/Sources/Sync/WebSocket/WebSocketConnection.m:391:    CC_SHA1(data.bytes, (CC_LONG)data.length, hash);
  ./Garazyk/Sources/Compat/PlatformShims/CommonCrypto/CommonDigest.h:24:#define CC_SHA1(data, len, md) SHA1((const unsigned char *)(data), (size_t)(len), (md))
  ./Garazyk/Sources/Compat/PlatformShims/CommonCrypto/CommonDigest.h:25:#define CC_MD5(data, len, md) MD5((const unsigned char *)(data), (size_t)(len), (md))
  ./Garazyk/Sources/Network/WebSocketUpgradeHandler.m:100:    CC_SHA1(cStr, (CC_LONG)strlen(cStr), digest);

### Timing-vulnerable secret comparisons
  ./Garazyk/Sources/Lexicon/ATProtoLexiconValidator.m:469:    } else if ([format isEqualToString:@"record-key"]) {
  ./Garazyk/Sources/Email/PDSEmailProviderFactory.m:193:        if ([source isEqualToString:@"keychain"]) {
  ./Garazyk/Sources/CLI/PDSCLIAdminCommand.m:150:        } else if ([arg isEqualToString:@"--password"] || [arg isEqualToString:@"-p"]) {
  ./Garazyk/Sources/Blob/MimeTypeValidator.m:613:        if (memcmp(bytes, "RIFF", 4) == 0) {
  ./Garazyk/Sources/Blob/MimeTypeValidator.m:614:            if (memcmp(bytes + 8, "WEBP", 4) == 0) return @"image/webp";
  ./Garazyk/Sources/Blob/MimeTypeValidator.m:615:            if (memcmp(bytes + 8, "AVI ", 4) == 0) return @"video/avi";
  ./Garazyk/Sources/Blob/MimeTypeValidator.m:616:            if (memcmp(bytes + 8, "WAVE", 4) == 0) return @"audio/wav";
  ./Garazyk/Sources/CLI/PDSCLIInputHelper.m:17:    if (nonInteractive && (strcmp(nonInteractive, "1") == 0 || strcmp(nonInteractive, "true") == 0)) {
  ./Garazyk/Sources/CLI/PDSCLIAccountCommand.m:222:        } else if ([arg isEqualToString:@"--password"] || [arg isEqualToString:@"-p"]) {
  ./Garazyk/Sources/CLI/PDSCLIOAuthCommand.m:98:        } else if ([arg isEqualToString:@"--secret"] || [arg isEqualToString:@"-s"]) {
  ./Garazyk/Sources/CLI/PDSCLIDispatcher.m:304:        if ([key isEqualToString:[self.commands[key] name]]) {
  ./Garazyk/Sources/AppView/Services/ContactService.m:112:    if ([token isEqualToString:@"test-import-token"] && ([allowHTTP isEqualToString:@"1"] || [allowHTTP isEqualToString:@"true"])) {
  ./Garazyk/Sources/Core/DID.m:393:            if (!selectedMethod && [methodType isKindOfClass:[NSString class]] && [methodType isEqualToString:@"Multikey"]) {
  ./Garazyk/Sources/Core/ATProtoCBORSerialization.m:120:    if (strcmp(objCType, @encode(float)) == 0 ||
  ./Garazyk/Sources/Core/ATProtoCBORSerialization.m:121:        strcmp(objCType, @encode(double)) == 0) {
  ... and 31 more

### ECB mode usage
  ./Garazyk/Sources/Compat/PlatformShims/CommonCrypto/CommonCryptor.h:28:    kCCOptionECBMode = 2

## Notes
- SHA1/MD5 may be acceptable for non-security uses (checksums, dedup).
- Verify context before flagging as vulnerability.
- Timing attacks require network access; prioritize based on threat model.
- arc4random() without arguments is often used for non-crypto purposes.

## scan_secrets
### Objective-C Secrets Detection Scan

- Root: .
- Scan path: ./Garazyk/Sources
- Generated: 2026-05-22T18:10:03Z

## Counts
- Password assignments: 0
- API key assignments: 0
- Secret assignments: 0
- Token assignments: 0
- Private key references: 0
- Connection strings: 0
- .env file matches: 0

## Files with potential secrets
- none detected

## Detailed findings

### Password assignments
  none

### API key assignments
  none

### Private key references
  none

## Notes
- These are pattern-based heuristics; manual review required.
- Check context to determine if test fixtures or production secrets.
- Verify secrets are not committed to version control history.
- Run `gitleaks` or `trufflehog` for git history scanning.

## scan_log_redaction
### Objective-C Log Redaction Scan

- Root: .
- Scan path: ./Garazyk/Sources
- Generated: 2026-05-22T18:10:03Z

## Counts
- Logging signals: 259
- Sensitive identifier signals: 1884
- Header/token literal signals: 62

## Prioritize first (logging + sensitive identifiers)
- ./Garazyk/Sources/App/PDSApplication.m
- ./Garazyk/Sources/CLI/PDSCLIAccountCommand.m
- ./Garazyk/Sources/CLI/PDSCLIAdminCommand.m
- ./Garazyk/Sources/CLI/PDSCLIInitCommand.m
- ./Garazyk/Sources/CLI/PDSCLIInputHelper.m
- ./Garazyk/Sources/CLI/PDSCLIOAuthCommand.m
- ./Garazyk/Sources/CLI/PDSCLIServeCommand.m
- ./Garazyk/Sources/Debug/GZLogger.m

## Secondary priority (logging + auth header literals)
- ./Garazyk/Sources/Admin/AdminMiddleware.m

## Notes
- False positives are expected; inspect exact logged payloads.

