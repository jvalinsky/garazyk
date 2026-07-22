// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Services/PDS/PDSSpaceStore.h"

#import <sqlite3.h>

#import "Core/NSDateFormatter+ATProto.h"
#import "Core/TID.h"
#import "Database/Connection/ATProtoConnectionManager.h"
#import "Database/Connection/ATProtoConnectionManagerSerial.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Core/CID.h"
#import "Core/ATProtoDagCBOR.h"
#import "Core/NSDictionary+CID.h"
#import "Repository/CAR.h"
#import "Security/Space/PDSSpaceCommit.h"
#import "Security/Space/PDSSpaceLtHash.h"

NSString *const PDSSpaceStoreErrorDomain = @"com.garazyk.space.store";

static NSString *const PDSSpaceSchemaSQL =
    @"CREATE TABLE IF NOT EXISTS space ("
     "uri TEXT PRIMARY KEY NOT NULL, is_owner INTEGER NOT NULL, policy TEXT NOT NULL, "
     "managing_app TEXT, app_access_type TEXT NOT NULL, app_allowed TEXT NOT NULL, "
     "created_at TEXT NOT NULL, deleted_at TEXT);"
     "CREATE TABLE IF NOT EXISTS space_member ("
     "space TEXT NOT NULL, did TEXT NOT NULL, PRIMARY KEY (space, did), "
     "FOREIGN KEY(space) REFERENCES space(uri) ON DELETE CASCADE);"
     "CREATE TABLE IF NOT EXISTS space_repo ("
     "space TEXT NOT NULL, author_did TEXT NOT NULL, lthash_state BLOB NOT NULL, "
     "rev TEXT, updated_at TEXT NOT NULL, PRIMARY KEY (space, author_did), "
     "FOREIGN KEY(space) REFERENCES space(uri) ON DELETE CASCADE);"
     "CREATE TABLE IF NOT EXISTS space_record ("
     "space TEXT NOT NULL, author_did TEXT NOT NULL, collection TEXT NOT NULL, rkey TEXT NOT NULL, "
     "cid TEXT NOT NULL, value BLOB NOT NULL, repo_rev TEXT NOT NULL, indexed_at TEXT NOT NULL, "
     "PRIMARY KEY (space, author_did, collection, rkey), "
     "FOREIGN KEY(space, author_did) REFERENCES space_repo(space, author_did) ON DELETE CASCADE);"
     "CREATE INDEX IF NOT EXISTS space_record_repo_rev_idx "
     "ON space_record(space, author_did, repo_rev);"
     "CREATE TABLE IF NOT EXISTS space_record_oplog ("
     "space TEXT NOT NULL, author_did TEXT NOT NULL, rev TEXT NOT NULL, idx INTEGER NOT NULL, "
     "action TEXT NOT NULL, collection TEXT NOT NULL, rkey TEXT NOT NULL, cid TEXT, prev TEXT, "
     "PRIMARY KEY (space, author_did, rev, idx), "
     "FOREIGN KEY(space, author_did) REFERENCES space_repo(space, author_did) ON DELETE CASCADE);"
     "CREATE INDEX IF NOT EXISTS space_record_oplog_since_idx "
     "ON space_record_oplog(space, author_did, rev, idx);"
     "CREATE TABLE IF NOT EXISTS space_writer ("
     "space TEXT NOT NULL, did TEXT NOT NULL, rev TEXT NOT NULL, hash BLOB NOT NULL, "
     "PRIMARY KEY (space, did), FOREIGN KEY(space) REFERENCES space(uri) ON DELETE CASCADE);"
     "CREATE TABLE IF NOT EXISTS space_credential_recipient ("
     "space TEXT NOT NULL, service_did TEXT NOT NULL, service_endpoint TEXT NOT NULL, "
     "last_issued_at TEXT NOT NULL, PRIMARY KEY (space, service_did), "
     "FOREIGN KEY(space) REFERENCES space(uri) ON DELETE CASCADE);"
     "CREATE TABLE IF NOT EXISTS space_delegation_replay ("
     "jti TEXT PRIMARY KEY NOT NULL, expires_at REAL NOT NULL);"
     "CREATE INDEX IF NOT EXISTS space_delegation_replay_expiry_idx "
     "ON space_delegation_replay(expires_at);";

/* Blobs are deliberately not related to the public PDS blob store.  A remote
 * user's PDS may receive a space-bound upload before it has synchronized the
 * authority's metadata, so this table cannot use a foreign key to `space`. */
static NSString *const PDSSpaceBlobSchemaSQL =
    @"CREATE TABLE IF NOT EXISTS space_blob ("
     "space TEXT NOT NULL, author_did TEXT NOT NULL, cid TEXT NOT NULL, "
     "mime_type TEXT NOT NULL, size INTEGER NOT NULL, data BLOB NOT NULL, "
     "created_at TEXT NOT NULL, PRIMARY KEY (space, author_did, cid));"
     "CREATE INDEX IF NOT EXISTS space_blob_lookup_idx "
     "ON space_blob(space, author_did, cid);";

/* Existing experimental databases predate expiring notification recipients.
 * Existing rows expire immediately rather than being silently grandfathered. */
static NSString *const PDSSpaceRecipientExpirySchemaSQL =
    @"ALTER TABLE space_credential_recipient ADD COLUMN expires_at REAL;"
     "UPDATE space_credential_recipient SET expires_at = 0 WHERE expires_at IS NULL;"
     "CREATE INDEX IF NOT EXISTS space_credential_recipient_expiry_idx "
     "ON space_credential_recipient(space, expires_at);";

static NSString *PDSSpaceTimestamp(NSDate *date) {
  return [NSDateFormatter atproto_stringFromDate:date ?: [NSDate date]];
}

static NSString *PDSSpaceStringColumn(sqlite3_stmt *statement, int column) {
  const unsigned char *bytes = sqlite3_column_text(statement, column);
  return bytes ? [NSString stringWithUTF8String:(const char *)bytes] : nil;
}

static NSData *PDSSpaceDataColumn(sqlite3_stmt *statement, int column) {
  const void *bytes = sqlite3_column_blob(statement, column);
  int length = sqlite3_column_bytes(statement, column);
  return bytes && length >= 0 ? [NSData dataWithBytes:bytes length:(NSUInteger)length] : nil;
}

static NSError *PDSSpaceSQLiteError(sqlite3 *database, NSString *message) {
  NSString *detail = database ? @(sqlite3_errmsg(database)) : @"Unknown SQLite error";
  return [NSError errorWithDomain:PDSSpaceStoreErrorDomain
                             code:PDSSpaceStoreErrorDatabase
                         userInfo:@{NSLocalizedDescriptionKey : message ?: detail,
                                    NSUnderlyingErrorKey : ATProtoDBError(PDSSpaceStoreErrorDomain,
                                                                          detail,
                                                                          PDSSpaceStoreErrorDatabase)}];
}

static BOOL PDSSpacePrepare(sqlite3 *database, const char *sql, sqlite3_stmt **statement,
                            NSError **error) {
  if (sqlite3_prepare_v2(database, sql, -1, statement, NULL) == SQLITE_OK) {
    return YES;
  }
  if (error) *error = PDSSpaceSQLiteError(database, @"Unable to prepare space-store query");
  return NO;
}

static BOOL PDSSpaceStepDone(sqlite3 *database, sqlite3_stmt *statement, NSError **error) {
  if (sqlite3_step(statement) == SQLITE_DONE) {
    return YES;
  }
  if (error) *error = PDSSpaceSQLiteError(database, @"Unable to execute space-store query");
  return NO;
}

static NSString *PDSSpaceActionString(PDSSpaceWriteAction action) {
  switch (action) {
    case PDSSpaceWriteActionCreate: return @"create";
    case PDSSpaceWriteActionUpdate: return @"update";
    case PDSSpaceWriteActionDelete: return @"delete";
  }
  return nil;
}

@interface PDSSpaceWrite ()
@property(nonatomic, readwrite) PDSSpaceWriteAction action;
@property(nonatomic, readwrite, copy) NSString *collection;
@property(nonatomic, readwrite, copy) NSString *rkey;
@property(nonatomic, readwrite, copy, nullable) NSString *cid;
@property(nonatomic, readwrite, copy, nullable) NSData *value;
@end

@implementation PDSSpaceWrite

+ (instancetype)writeWithAction:(PDSSpaceWriteAction)action
                      collection:(NSString *)collection
                            rkey:(NSString *)rkey
                             cid:(NSString *)cid
                           value:(NSData *)value {
  PDSSpaceWrite *write = [[self alloc] init];
  write.action = action;
  write.collection = collection;
  write.rkey = rkey;
  write.cid = cid;
  write.value = value;
  return write;
}

@end

@interface PDSSpaceStore ()
@property(nonatomic, strong) ATProtoConnectionManagerSerial *connection;
@property(nonatomic, copy) NSString *databasePath;
@end

@implementation PDSSpaceStore

- (instancetype)initWithDatabasePath:(NSString *)databasePath error:(NSError **)error {
  if (databasePath.length == 0) {
    if (error) {
      *error = [NSError errorWithDomain:PDSSpaceStoreErrorDomain
                                   code:PDSSpaceStoreErrorDatabase
                               userInfo:@{NSLocalizedDescriptionKey : @"A space-store path is required"}];
    }
    return nil;
  }
  self = [super init];
  if (!self) return nil;

  NSString *directory = [databasePath stringByDeletingLastPathComponent];
  if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:error]) {
    return nil;
  }

  _connection = [[ATProtoConnectionManagerSerial alloc]
      initWithLabel:@"com.garazyk.pds.permissioned-spaces"];
  _databasePath = [databasePath copy];
  if (![_connection openWithPath:databasePath config:ATProtoDBConfigServiceDatabase error:error]) {
    return nil;
  }
  if (![self applyMigrations:error]) {
    [_connection close];
    return nil;
  }
  return self;
}

- (void)dealloc {
  [self close];
}

- (void)close {
  [self.connection close];
}

- (BOOL)createOnlineBackupAtPath:(NSString *)destinationPath error:(NSError **)error {
  if (destinationPath.length == 0 || [destinationPath isEqualToString:self.databasePath]) {
    if (error) *error = [self invalidWriteError:@"Backup destination must differ from the space database"];
    return NO;
  }
  NSString *directory = [destinationPath stringByDeletingLastPathComponent];
  if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES attributes:nil error:error]) return NO;

  __block NSError *localError = nil;
  __block BOOL copied = NO;
  BOOL executed = [self.connection execute:^(sqlite3 *source) {
    sqlite3 *destination = NULL;
    if (sqlite3_open_v2(destinationPath.fileSystemRepresentation, &destination,
                        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL) != SQLITE_OK) {
      localError = PDSSpaceSQLiteError(destination, @"Unable to open space backup destination");
      if (destination) sqlite3_close(destination);
      return;
    }
    sqlite3_backup *backup = sqlite3_backup_init(destination, "main", source, "main");
    if (!backup) {
      localError = PDSSpaceSQLiteError(destination, @"Unable to initialize online space backup");
      sqlite3_close(destination);
      return;
    }
    int step = sqlite3_backup_step(backup, -1);
    int finish = sqlite3_backup_finish(backup);
    if (step != SQLITE_DONE || finish != SQLITE_OK) {
      localError = PDSSpaceSQLiteError(destination, @"Unable to copy space database backup");
    } else {
      copied = YES;
    }
    sqlite3_close(destination);
  } error:nil];
  if (!executed || !copied) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to create space database backup");
    return NO;
  }
  return YES;
}

- (BOOL)applyMigrations:(NSError **)error {
  __block NSError *localError = nil;
  __block NSInteger currentVersion = 0;
  BOOL queried = [self.connection execute:^(sqlite3 *database) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (sqlite3_exec(database,
                     "CREATE TABLE IF NOT EXISTS _migrations (version INTEGER PRIMARY KEY, "
                     "name TEXT NOT NULL, applied_at TEXT NOT NULL)",
                     NULL, NULL, NULL) != SQLITE_OK ||
        !PDSSpacePrepare(database, "SELECT COALESCE(MAX(version), 0) FROM _migrations", &statement,
                         &localError)) {
      if (!localError) localError = PDSSpaceSQLiteError(database, @"Unable to initialize space migrations");
      return;
    }
    if (sqlite3_step(statement) == SQLITE_ROW) currentVersion = sqlite3_column_int(statement, 0);
  } error:&localError];
  if (!queried || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to inspect space migrations");
    return NO;
  }
  __block BOOL migrationOK = YES;
  BOOL transacted = [self.connection transact:^(sqlite3 *database, BOOL *rollback) {
    NSArray<NSDictionary<NSString *, id> *> *migrations = @[
        @{ @"version" : @1, @"name" : @"permissioned_spaces_initial", @"sql" : PDSSpaceSchemaSQL },
        @{ @"version" : @2, @"name" : @"permissioned_spaces_private_blobs", @"sql" : PDSSpaceBlobSchemaSQL },
        @{ @"version" : @3, @"name" : @"permissioned_spaces_notification_expiry", @"sql" : PDSSpaceRecipientExpirySchemaSQL },
    ];
    for (NSDictionary<NSString *, id> *migration in migrations) {
      if (currentVersion >= [migration[@"version"] integerValue]) continue;
      char *message = NULL;
      if (sqlite3_exec(database, [migration[@"sql"] UTF8String], NULL, NULL, &message) != SQLITE_OK) {
        if (message) sqlite3_free(message);
        localError = PDSSpaceSQLiteError(database, @"Unable to create space-store schema");
        migrationOK = NO;
        *rollback = YES;
        return;
      }
      PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
      if (!PDSSpacePrepare(database,
                           "INSERT INTO _migrations(version, name, applied_at) VALUES(?, ?, ?)",
                           &statement, &localError)) {
        migrationOK = NO;
        *rollback = YES;
        return;
      }
      ATProtoDBBindParams(statement, @[migration[@"version"], migration[@"name"], PDSSpaceTimestamp(nil)]);
      if (!PDSSpaceStepDone(database, statement, &localError)) {
        migrationOK = NO;
        *rollback = YES;
        return;
      }
    }
  } error:nil];
  if (!transacted || !migrationOK) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to migrate space store");
    return NO;
  }
  return YES;
}

- (BOOL)createSpace:(NSString *)space
              owner:(BOOL)owner
              policy:(NSString *)policy
          managingApp:(NSString *)managingApp
       appAccessType:(NSString *)appAccessType
           appAllowed:(NSArray<NSString *> *)appAllowed
                error:(NSError **)error {
  if (space.length == 0 || policy.length == 0 || appAccessType.length == 0) {
    if (error) *error = [self invalidWriteError:@"Space URI and configuration are required"];
    return NO;
  }
  NSData *initialState = [[PDSSpaceLtHash alloc] init].state;
  NSString *timestamp = PDSSpaceTimestamp(nil);
  NSString *allowedJSON = [self JSONStringForStringArray:appAllowed error:error];
  if (!allowedJSON) return NO;

  __block NSError *localError = nil;
  __block BOOL created = YES;
  BOOL transacted = [self.connection transact:^(sqlite3 *database, BOOL *rollback) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *spaceInsert = NULL;
    if (!PDSSpacePrepare(database,
                         "INSERT INTO space(uri, is_owner, policy, managing_app, app_access_type, "
                         "app_allowed, created_at, deleted_at) VALUES(?, ?, ?, ?, ?, ?, ?, NULL)",
                         &spaceInsert, &localError)) {
      created = NO; *rollback = YES; return;
    }
    ATProtoDBBindParams(spaceInsert, @[space, @(owner), policy, managingApp ?: [NSNull null],
                                       appAccessType, allowedJSON, timestamp]);
    if (!PDSSpaceStepDone(database, spaceInsert, &localError)) {
      if (sqlite3_extended_errcode(database) == SQLITE_CONSTRAINT_PRIMARYKEY ||
          sqlite3_extended_errcode(database) == SQLITE_CONSTRAINT_UNIQUE) {
        localError = [NSError errorWithDomain:PDSSpaceStoreErrorDomain
                                         code:PDSSpaceStoreErrorSpaceAlreadyExists
                                     userInfo:@{NSLocalizedDescriptionKey : @"Space already exists"}];
      }
      created = NO; *rollback = YES; return;
    }
  } error:nil];
  if (!transacted || !created) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to create space");
    return NO;
  }
  return YES;
}

- (BOOL)ensureRepositoryForSpace:(NSString *)space author:(NSString *)author error:(NSError **)error {
  if (space.length == 0 || author.length == 0) {
    if (error) *error = [self invalidWriteError:@"Space URI and repository author are required"];
    return NO;
  }
  NSData *initialState = [[PDSSpaceLtHash alloc] init].state;
  NSString *timestamp = PDSSpaceTimestamp(nil);
  __block NSError *localError = nil;
  __block BOOL success = YES;
  BOOL transacted = [self.connection transact:^(sqlite3 *database, BOOL *rollback) {
    if (![self ensureActiveSpaceInTransaction:database space:space timestamp:timestamp error:&localError]) {
      success = NO; *rollback = YES; return;
    }
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *insertRepo = NULL;
    if (!PDSSpacePrepare(database,
                         "INSERT OR IGNORE INTO space_repo(space, author_did, lthash_state, rev, updated_at) "
                         "VALUES(?, ?, ?, NULL, ?)",
                         &insertRepo, &localError)) {
      success = NO; *rollback = YES; return;
    }
    ATProtoDBBindParams(insertRepo, @[space, author, initialState, timestamp]);
    if (!PDSSpaceStepDone(database, insertRepo, &localError)) {
      success = NO; *rollback = YES;
    }
  } error:nil];
  if (!transacted || !success) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to initialize space repository");
    return NO;
  }
  return YES;
}

- (NSDictionary<NSString *, id> *)spaceInfoForURI:(NSString *)space error:(NSError **)error {
  __block NSDictionary *result = nil;
  __block NSError *localError = nil;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (!PDSSpacePrepare(database,
                         "SELECT is_owner, policy, managing_app, app_access_type, app_allowed, "
                         "created_at, deleted_at FROM space WHERE uri = ?",
                         &statement, &localError)) return;
    ATProtoDBBindParams(statement, @[space]);
    if (sqlite3_step(statement) == SQLITE_ROW) {
      NSString *appAllowed = PDSSpaceStringColumn(statement, 4) ?: @"[]";
      NSArray *allowed = [self stringArrayFromJSONString:appAllowed];
      result = @{ @"uri" : space,
                  @"isOwner" : @(sqlite3_column_int(statement, 0) != 0),
                  @"policy" : PDSSpaceStringColumn(statement, 1) ?: @"member-list",
                  @"managingApp" : PDSSpaceStringColumn(statement, 2) ?: [NSNull null],
                  @"appAccessType" : PDSSpaceStringColumn(statement, 3) ?: @"open",
                  @"appAllowed" : allowed,
                  @"createdAt" : PDSSpaceStringColumn(statement, 5) ?: @"",
                  @"deletedAt" : PDSSpaceStringColumn(statement, 6) ?: [NSNull null] };
    } else if (sqlite3_errcode(database) != SQLITE_OK && sqlite3_errcode(database) != SQLITE_DONE) {
      localError = PDSSpaceSQLiteError(database, @"Unable to read space");
    }
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to read space");
    return nil;
  }
  return result;
}

- (NSArray<NSDictionary<NSString *, id> *> *)listSpacesWithLimit:(NSUInteger)limit
                                                            cursor:(NSString *)cursor
                                                          authority:(NSString *)authority
                                                               type:(NSString *)type
                                                              error:(NSError **)error {
  NSUInteger clamped = MIN(MAX(limit, 1), 100);
  __block NSMutableArray *result = [NSMutableArray array];
  __block NSError *localError = nil;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    NSMutableString *sql = [NSMutableString stringWithString:
        @"SELECT uri, is_owner FROM space WHERE deleted_at IS NULL"];
    NSMutableArray *parameters = [NSMutableArray array];
    if (authority.length > 0) {
      [sql appendString:@" AND uri LIKE ?"];
      [parameters addObject:[NSString stringWithFormat:@"at://%@/space/%%", authority]];
    }
    if (type.length > 0) {
      [sql appendString:@" AND uri LIKE ?"];
      [parameters addObject:[NSString stringWithFormat:@"at://%%/space/%@/%%", type]];
    }
    if (cursor.length > 0) {
      [sql appendString:@" AND uri > ?"];
      [parameters addObject:cursor];
    }
    [sql appendString:@" ORDER BY uri ASC LIMIT ?"];
    [parameters addObject:@(clamped)];
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (!PDSSpacePrepare(database, sql.UTF8String, &statement, &localError)) return;
    ATProtoDBBindParams(statement, parameters);
    int step = SQLITE_ROW;
    while ((step = sqlite3_step(statement)) == SQLITE_ROW) {
      NSString *uri = PDSSpaceStringColumn(statement, 0);
      if (uri) [result addObject:@{ @"uri" : uri, @"isOwner" : @(sqlite3_column_int(statement, 1) != 0) }];
    }
    if (step != SQLITE_DONE) localError = PDSSpaceSQLiteError(database, @"Unable to list spaces");
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to list spaces");
    return nil;
  }
  return result;
}

- (BOOL)updateSpace:(NSString *)space
              policy:(NSString *)policy
          managingApp:(NSString *)managingApp
       appAccessType:(NSString *)appAccessType
           appAllowed:(NSArray<NSString *> *)appAllowed
                error:(NSError **)error {
  NSString *allowedJSON = appAllowed ? [self JSONStringForStringArray:appAllowed error:error] : nil;
  if (appAllowed && !allowedJSON) return NO;
  __block NSError *localError = nil;
  __block BOOL changed = NO;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (!PDSSpacePrepare(database,
                         "UPDATE space SET policy = COALESCE(?, policy), "
                         "managing_app = CASE WHEN ? = '' THEN NULL "
                         "WHEN ? IS NULL THEN managing_app ELSE ? END, "
                         "app_access_type = COALESCE(?, app_access_type), "
                         "app_allowed = COALESCE(?, app_allowed) WHERE uri = ? AND is_owner = 1",
                         &statement, &localError)) return;
    id managingValue = managingApp ?: [NSNull null];
    ATProtoDBBindParams(statement, @[policy ?: [NSNull null], managingValue, managingValue, managingValue,
                                     appAccessType ?: [NSNull null], allowedJSON ?: [NSNull null], space]);
    if (!PDSSpaceStepDone(database, statement, &localError)) return;
    changed = sqlite3_changes(database) == 1;
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to update space");
    return NO;
  }
  if (!changed && error) *error = [self spaceNotFoundError];
  return changed;
}

- (BOOL)markSpaceDeleted:(NSString *)space error:(NSError **)error {
  return [self markSpaceDeleted:space ownerOnly:YES error:error];
}

- (BOOL)markReplicatedSpaceDeleted:(NSString *)space error:(NSError **)error {
  return [self markSpaceDeleted:space ownerOnly:NO error:error];
}

- (BOOL)markSpaceDeleted:(NSString *)space ownerOnly:(BOOL)ownerOnly error:(NSError **)error {
  __block NSError *localError = nil;
  __block BOOL changed = NO;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    const char *sql = ownerOnly
        ? "UPDATE space SET deleted_at = ? WHERE uri = ? AND is_owner = 1 AND deleted_at IS NULL"
        : "UPDATE space SET deleted_at = ? WHERE uri = ? AND deleted_at IS NULL";
    if (!PDSSpacePrepare(database, sql,
                         &statement, &localError)) return;
    ATProtoDBBindParams(statement, @[PDSSpaceTimestamp(nil), space]);
    if (!PDSSpaceStepDone(database, statement, &localError)) return;
    changed = sqlite3_changes(database) == 1;
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to delete space");
    return NO;
  }
  if (!changed && error) *error = [self spaceNotFoundError];
  return changed;
}

- (BOOL)addMember:(NSString *)did toSpace:(NSString *)space error:(NSError **)error {
  return [self changeMember:did space:space add:YES error:error];
}

- (BOOL)removeMember:(NSString *)did fromSpace:(NSString *)space error:(NSError **)error {
  return [self changeMember:did space:space add:NO error:error];
}

- (BOOL)changeMember:(NSString *)did space:(NSString *)space add:(BOOL)add error:(NSError **)error {
  __block NSError *localError = nil;
  __block BOOL success = NO;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *owned = NULL;
    if (!PDSSpacePrepare(database, "SELECT 1 FROM space WHERE uri = ? AND is_owner = 1 AND deleted_at IS NULL",
                         &owned, &localError)) return;
    ATProtoDBBindParams(owned, @[space]);
    if (sqlite3_step(owned) != SQLITE_ROW) return;
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    const char *sql = add ? "INSERT OR IGNORE INTO space_member(space, did) VALUES(?, ?)"
                          : "DELETE FROM space_member WHERE space = ? AND did = ?";
    if (!PDSSpacePrepare(database, sql, &statement, &localError)) return;
    ATProtoDBBindParams(statement, @[space, did]);
    success = PDSSpaceStepDone(database, statement, &localError);
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to change member");
    return NO;
  }
  if (!success && error) *error = [self spaceNotFoundError];
  return success;
}

- (BOOL)isMember:(NSString *)did ofSpace:(NSString *)space error:(NSError **)error {
  __block BOOL result = NO;
  __block NSError *localError = nil;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (!PDSSpacePrepare(database, "SELECT 1 FROM space_member WHERE space = ? AND did = ?", &statement,
                         &localError)) return;
    ATProtoDBBindParams(statement, @[space, did]);
    result = sqlite3_step(statement) == SQLITE_ROW;
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to read members");
    return NO;
  }
  return result;
}

- (NSArray<NSString *> *)listMembersForSpace:(NSString *)space limit:(NSUInteger)limit
                                        cursor:(NSString *)cursor error:(NSError **)error {
  NSUInteger clamped = MIN(MAX(limit, 1), 100);
  __block NSMutableArray *result = [NSMutableArray array];
  __block NSError *localError = nil;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    const char *sql = cursor.length > 0
        ? "SELECT did FROM space_member WHERE space = ? AND did > ? ORDER BY did ASC LIMIT ?"
        : "SELECT did FROM space_member WHERE space = ? ORDER BY did ASC LIMIT ?";
    if (!PDSSpacePrepare(database, sql, &statement, &localError)) return;
    ATProtoDBBindParams(statement, cursor.length > 0 ? @[space, cursor, @(clamped)] : @[space, @(clamped)]);
    int step = SQLITE_ROW;
    while ((step = sqlite3_step(statement)) == SQLITE_ROW) {
      NSString *did = PDSSpaceStringColumn(statement, 0);
      if (did) [result addObject:did];
    }
    if (step != SQLITE_DONE) localError = PDSSpaceSQLiteError(database, @"Unable to list members");
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to list members");
    return nil;
  }
  return result;
}

- (NSDictionary<NSString *, id> *)applyWrites:(NSArray<PDSSpaceWrite *> *)writes
                                       toSpace:(NSString *)space
                                        author:(NSString *)author
                                           rev:(NSString *)requestedRev
                                         error:(NSError **)error {
  if (writes.count == 0 || space.length == 0 || author.length == 0) {
    if (error) *error = [self invalidWriteError:@"A non-empty write commit needs a space and author"];
    return nil;
  }
  NSString *rev = requestedRev.length > 0 ? requestedRev : [TID tid].stringValue;
  NSString *timestamp = PDSSpaceTimestamp(nil);
  __block NSDictionary *result = nil;
  __block NSError *localError = nil;
  __block BOOL success = YES;
  BOOL transacted = [self.connection transact:^(sqlite3 *database, BOOL *rollback) {
    if (![self ensureRepositoryInTransaction:database space:space author:author timestamp:timestamp error:&localError]) {
      success = NO; *rollback = YES; return;
    }
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stateQuery = NULL;
    if (!PDSSpacePrepare(database,
                         "SELECT lthash_state FROM space_repo WHERE space = ? AND author_did = ?",
                         &stateQuery, &localError)) {
      success = NO; *rollback = YES; return;
    }
    ATProtoDBBindParams(stateQuery, @[space, author]);
    if (sqlite3_step(stateQuery) != SQLITE_ROW) {
      localError = PDSSpaceSQLiteError(database, @"Space repository disappeared during commit");
      success = NO; *rollback = YES; return;
    }
    PDSSpaceLtHash *setHash = [[PDSSpaceLtHash alloc] initWithState:PDSSpaceDataColumn(stateQuery, 0)
                                                               error:&localError];
    if (!setHash) { success = NO; *rollback = YES; return; }

    NSInteger index = 0;
    for (PDSSpaceWrite *write in writes) {
      if (![self applyWrite:write toDatabase:database space:space author:author rev:rev index:index
                    timestamp:timestamp setHash:setHash error:&localError]) {
        success = NO; *rollback = YES; return;
      }
      index++;
    }
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stateUpdate = NULL;
    if (!PDSSpacePrepare(database,
                         "UPDATE space_repo SET lthash_state = ?, rev = ?, updated_at = ? "
                         "WHERE space = ? AND author_did = ?",
                         &stateUpdate, &localError)) {
      success = NO; *rollback = YES; return;
    }
    ATProtoDBBindParams(stateUpdate, @[setHash.state, rev, timestamp, space, author]);
    if (!PDSSpaceStepDone(database, stateUpdate, &localError)) {
      success = NO; *rollback = YES; return;
    }
    result = @{ @"rev" : rev, @"state" : setHash.state, @"hash" : setHash.digest };
  } error:nil];
  if (!transacted || !success) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to apply space writes");
    return nil;
  }
  return result;
}

- (BOOL)ensureRepositoryInTransaction:(sqlite3 *)database space:(NSString *)space author:(NSString *)author
                             timestamp:(NSString *)timestamp error:(NSError **)error {
  if (![self ensureActiveSpaceInTransaction:database space:space timestamp:timestamp error:error]) return NO;
  PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *insertRepo = NULL;
  if (!PDSSpacePrepare(database,
                       "INSERT OR IGNORE INTO space_repo(space, author_did, lthash_state, rev, updated_at) "
                       "VALUES(?, ?, ?, NULL, ?)",
                       &insertRepo, error)) return NO;
  ATProtoDBBindParams(insertRepo, @[space, author, [[PDSSpaceLtHash alloc] init].state, timestamp]);
  return PDSSpaceStepDone(database, insertRepo, error);
}

/* A non-authority PDS learns of a space lazily through a signed write
 * notification or its own member's first write.  The row carries no policy
 * authority; it is only the local isolated-repository namespace.  Tombstones
 * must never be recreated by delayed notifications or retries. */
- (BOOL)ensureActiveSpaceInTransaction:(sqlite3 *)database
                                 space:(NSString *)space
                             timestamp:(NSString *)timestamp
                                 error:(NSError **)error {
  PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *find = NULL;
  if (!PDSSpacePrepare(database, "SELECT deleted_at FROM space WHERE uri = ?", &find, error)) return NO;
  ATProtoDBBindParams(find, @[space]);
  int step = sqlite3_step(find);
  if (step == SQLITE_DONE) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *insertSpace = NULL;
    if (!PDSSpacePrepare(database,
                         "INSERT INTO space(uri, is_owner, policy, managing_app, app_access_type, app_allowed, "
                         "created_at, deleted_at) VALUES(?, 0, 'member-list', NULL, 'open', '[]', ?, NULL)",
                         &insertSpace, error)) return NO;
    ATProtoDBBindParams(insertSpace, @[space, timestamp]);
    if (!PDSSpaceStepDone(database, insertSpace, error)) return NO;
  } else if (step == SQLITE_ROW) {
    if (sqlite3_column_type(find, 0) != SQLITE_NULL) {
      if (error) *error = [self spaceNotFoundError];
      return NO;
    }
  } else {
    if (error) *error = PDSSpaceSQLiteError(database, @"Unable to inspect space state");
    return NO;
  }
  return YES;
}

- (BOOL)applyWrite:(PDSSpaceWrite *)write toDatabase:(sqlite3 *)database space:(NSString *)space
            author:(NSString *)author rev:(NSString *)rev index:(NSInteger)index timestamp:(NSString *)timestamp
           setHash:(PDSSpaceLtHash *)setHash error:(NSError **)error {
  NSString *action = PDSSpaceActionString(write.action);
  if (!action || write.collection.length == 0 || write.rkey.length == 0 ||
      ((write.action == PDSSpaceWriteActionCreate || write.action == PDSSpaceWriteActionUpdate) &&
       (write.cid.length == 0 || write.value.length == 0))) {
    if (error) *error = [self invalidWriteError:@"Invalid prepared space write"];
    return NO;
  }
  PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *existingQuery = NULL;
  if (!PDSSpacePrepare(database,
                       "SELECT cid FROM space_record WHERE space = ? AND author_did = ? AND collection = ? AND rkey = ?",
                       &existingQuery, error)) return NO;
  ATProtoDBBindParams(existingQuery, @[space, author, write.collection, write.rkey]);
  NSString *previousCID = sqlite3_step(existingQuery) == SQLITE_ROW ? PDSSpaceStringColumn(existingQuery, 0) : nil;
  if (write.action == PDSSpaceWriteActionCreate && previousCID) {
    if (error) *error = [NSError errorWithDomain:PDSSpaceStoreErrorDomain
                                             code:PDSSpaceStoreErrorRecordAlreadyExists
                                         userInfo:@{NSLocalizedDescriptionKey : @"Space record already exists"}];
    return NO;
  }
  if ((write.action == PDSSpaceWriteActionUpdate || write.action == PDSSpaceWriteActionDelete) && !previousCID) {
    if (error) *error = [NSError errorWithDomain:PDSSpaceStoreErrorDomain
                                             code:PDSSpaceStoreErrorRecordNotFound
                                         userInfo:@{NSLocalizedDescriptionKey : @"Space record does not exist"}];
    return NO;
  }

  if (previousCID) {
    [setHash removeElement:[NSString stringWithFormat:@"%@/%@/%@", write.collection, write.rkey, previousCID]];
  }
  if (write.action == PDSSpaceWriteActionDelete) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *deleteStatement = NULL;
    if (!PDSSpacePrepare(database,
                         "DELETE FROM space_record WHERE space = ? AND author_did = ? AND collection = ? AND rkey = ?",
                         &deleteStatement, error)) return NO;
    ATProtoDBBindParams(deleteStatement, @[space, author, write.collection, write.rkey]);
    if (!PDSSpaceStepDone(database, deleteStatement, error)) return NO;
  } else {
    [setHash addElement:[NSString stringWithFormat:@"%@/%@/%@", write.collection, write.rkey, write.cid]];
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *upsert = NULL;
    if (!PDSSpacePrepare(database,
                         "INSERT INTO space_record(space, author_did, collection, rkey, cid, value, repo_rev, indexed_at) "
                         "VALUES(?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(space, author_did, collection, rkey) DO UPDATE SET "
                         "cid = excluded.cid, value = excluded.value, repo_rev = excluded.repo_rev, indexed_at = excluded.indexed_at",
                         &upsert, error)) return NO;
    ATProtoDBBindParams(upsert, @[space, author, write.collection, write.rkey, write.cid, write.value, rev, timestamp]);
    if (!PDSSpaceStepDone(database, upsert, error)) return NO;
  }
  PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *oplog = NULL;
  if (!PDSSpacePrepare(database,
                       "INSERT INTO space_record_oplog(space, author_did, rev, idx, action, collection, rkey, cid, prev) "
                       "VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)",
                       &oplog, error)) return NO;
  ATProtoDBBindParams(oplog, @[space, author, rev, @(index), action, write.collection, write.rkey,
                               write.cid ?: [NSNull null], previousCID ?: [NSNull null]]);
  return PDSSpaceStepDone(database, oplog, error);
}

- (NSDictionary<NSString *, id> *)repositoryStateForSpace:(NSString *)space author:(NSString *)author
                                                     error:(NSError **)error {
  __block NSDictionary *result = nil;
  __block NSError *localError = nil;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (!PDSSpacePrepare(database,
                         "SELECT lthash_state, rev, updated_at FROM space_repo WHERE space = ? AND author_did = ?",
                         &statement, &localError)) return;
    ATProtoDBBindParams(statement, @[space, author]);
    if (sqlite3_step(statement) == SQLITE_ROW) {
      NSData *state = PDSSpaceDataColumn(statement, 0);
      PDSSpaceLtHash *hash = [[PDSSpaceLtHash alloc] initWithState:state error:&localError];
      if (hash) result = @{ @"state" : hash.state, @"hash" : hash.digest,
                            @"rev" : PDSSpaceStringColumn(statement, 1) ?: [NSNull null],
                            @"updatedAt" : PDSSpaceStringColumn(statement, 2) ?: @"" };
    }
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to read space repository");
    return nil;
  }
  return result;
}

- (NSArray<NSDictionary<NSString *, id> *> *)repositoriesForReconciliation:(NSError **)error {
  __block NSMutableArray *result = [NSMutableArray array];
  __block NSError *localError = nil;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (!PDSSpacePrepare(database,
                         "SELECT repo.space, repo.author_did, repo.lthash_state, repo.rev "
                         "FROM space_repo AS repo JOIN space ON space.uri = repo.space "
                         "WHERE space.deleted_at IS NULL AND repo.rev IS NOT NULL "
                         "ORDER BY repo.space ASC, repo.author_did ASC",
                         &statement, &localError)) return;
    int step = SQLITE_ROW;
    while ((step = sqlite3_step(statement)) == SQLITE_ROW) {
      NSData *state = PDSSpaceDataColumn(statement, 2);
      PDSSpaceLtHash *hash = [[PDSSpaceLtHash alloc] initWithState:state error:nil];
      NSString *space = PDSSpaceStringColumn(statement, 0);
      NSString *author = PDSSpaceStringColumn(statement, 1);
      NSString *rev = PDSSpaceStringColumn(statement, 3);
      if (hash && space.length > 0 && author.length > 0 && rev.length > 0) {
        [result addObject:@{ @"space" : space, @"author" : author, @"rev" : rev,
                             @"hash" : hash.digest }];
      }
    }
    if (step != SQLITE_DONE) localError = PDSSpaceSQLiteError(database, @"Unable to list space repositories for reconciliation");
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to list space repositories for reconciliation");
    return nil;
  }
  return result;
}

- (NSDictionary<NSString *, id> *)recordForSpace:(NSString *)space author:(NSString *)author
                                         collection:(NSString *)collection rkey:(NSString *)rkey error:(NSError **)error {
  __block NSDictionary *result = nil;
  __block NSError *localError = nil;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (!PDSSpacePrepare(database,
                         "SELECT cid, value, repo_rev, indexed_at FROM space_record "
                         "WHERE space = ? AND author_did = ? AND collection = ? AND rkey = ?",
                         &statement, &localError)) return;
    ATProtoDBBindParams(statement, @[space, author, collection, rkey]);
    if (sqlite3_step(statement) == SQLITE_ROW) {
      result = @{ @"cid" : PDSSpaceStringColumn(statement, 0) ?: @"",
                  @"value" : PDSSpaceDataColumn(statement, 1) ?: [NSData data],
                  @"rev" : PDSSpaceStringColumn(statement, 2) ?: @"",
                  @"indexedAt" : PDSSpaceStringColumn(statement, 3) ?: @"" };
    }
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to read space record");
    return nil;
  }
  return result;
}

- (NSArray<NSDictionary<NSString *, id> *> *)recordsForSpace:(NSString *)space author:(NSString *)author
                                                   collection:(NSString *)collection limit:(NSUInteger)limit cursor:(NSString *)cursor
                                                      reverse:(BOOL)reverse error:(NSError **)error {
  NSUInteger clamped = MIN(MAX(limit, 1), 100);
  __block NSMutableArray *result = [NSMutableArray array];
  __block NSError *localError = nil;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    NSMutableString *sql = [NSMutableString stringWithFormat:
        @"SELECT collection, rkey, cid, value, repo_rev, indexed_at FROM space_record "
         "WHERE space = ? AND author_did = ?%@%@ ORDER BY collection %@, rkey %@ LIMIT ?",
        collection.length > 0 ? @" AND collection = ?" : @"",
        cursor.length > 0 ? @" AND (collection || '/' || rkey) > ?" : @"",
        reverse ? @"DESC" : @"ASC", reverse ? @"DESC" : @"ASC"];
    NSMutableArray *parameters = [NSMutableArray arrayWithArray:@[space, author]];
    if (collection.length > 0) [parameters addObject:collection];
    if (cursor.length > 0) [parameters addObject:cursor];
    [parameters addObject:@(clamped)];
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (!PDSSpacePrepare(database, sql.UTF8String, &statement, &localError)) return;
    ATProtoDBBindParams(statement, parameters);
    int step = SQLITE_ROW;
    while ((step = sqlite3_step(statement)) == SQLITE_ROW) {
      [result addObject:@{ @"collection" : PDSSpaceStringColumn(statement, 0) ?: @"",
                           @"rkey" : PDSSpaceStringColumn(statement, 1) ?: @"",
                           @"cid" : PDSSpaceStringColumn(statement, 2) ?: @"",
                           @"value" : PDSSpaceDataColumn(statement, 3) ?: [NSData data],
                           @"rev" : PDSSpaceStringColumn(statement, 4) ?: @"",
                           @"indexedAt" : PDSSpaceStringColumn(statement, 5) ?: @"" }];
    }
    if (step != SQLITE_DONE) localError = PDSSpaceSQLiteError(database, @"Unable to list space records");
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to list space records");
    return nil;
  }
  return result;
}

- (NSArray<NSDictionary<NSString *, id> *> *)repoOperationsForSpace:(NSString *)space author:(NSString *)author
                                                                since:(NSString *)since limit:(NSUInteger)limit error:(NSError **)error {
  NSUInteger clamped = MIN(MAX(limit, 1), 1000);
  __block NSMutableArray *result = [NSMutableArray array];
  __block NSError *localError = nil;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    const char *sql = since.length > 0
        ? "SELECT rev, idx, action, collection, rkey, cid, prev FROM space_record_oplog "
          "WHERE space = ? AND author_did = ? AND rev > ? ORDER BY rev ASC, idx ASC LIMIT ?"
        : "SELECT rev, idx, action, collection, rkey, cid, prev FROM space_record_oplog "
          "WHERE space = ? AND author_did = ? ORDER BY rev ASC, idx ASC LIMIT ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (!PDSSpacePrepare(database, sql, &statement, &localError)) return;
    ATProtoDBBindParams(statement, since.length > 0 ? @[space, author, since, @(clamped)] : @[space, author, @(clamped)]);
    int step = SQLITE_ROW;
    while ((step = sqlite3_step(statement)) == SQLITE_ROW) {
      [result addObject:@{ @"rev" : PDSSpaceStringColumn(statement, 0) ?: @"",
                           @"index" : @(sqlite3_column_int(statement, 1)),
                           @"action" : PDSSpaceStringColumn(statement, 2) ?: @"",
                           @"collection" : PDSSpaceStringColumn(statement, 3) ?: @"",
                           @"rkey" : PDSSpaceStringColumn(statement, 4) ?: @"",
                           @"cid" : PDSSpaceStringColumn(statement, 5) ?: [NSNull null],
                           @"prev" : PDSSpaceStringColumn(statement, 6) ?: [NSNull null] }];
    }
    if (step != SQLITE_DONE) localError = PDSSpaceSQLiteError(database, @"Unable to list space repo ops");
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to list space repo ops");
    return nil;
  }
  return result;
}

- (NSDictionary<NSString *, id> *)storeBlobData:(NSData *)data
                                        mimeType:(NSString *)mimeType
                                         toSpace:(NSString *)space
                                          author:(NSString *)author
                                           error:(NSError **)error {
  if (data.length == 0 || space.length == 0 || author.length == 0 || mimeType.length == 0 ||
      mimeType.length > 255 || [mimeType rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location != NSNotFound) {
    if (error) *error = [self invalidWriteError:@"Blob data, MIME type, space, and author are required"];
    return nil;
  }
  CID *cid = [CID cidWithDigest:[CID sha256Digest:data] codec:0x55];
  if (!cid) {
    if (error) *error = [self invalidWriteError:@"Unable to derive a CID for the private blob"];
    return nil;
  }

  __block NSError *localError = nil;
  __block BOOL stored = NO;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (!PDSSpacePrepare(database,
                         "INSERT INTO space_blob(space, author_did, cid, mime_type, size, data, created_at) "
                         "VALUES(?, ?, ?, ?, ?, ?, ?) ON CONFLICT(space, author_did, cid) DO NOTHING",
                         &statement, &localError)) return;
    ATProtoDBBindParams(statement, @[space, author, cid.stringValue, mimeType, @(data.length), data,
                                    PDSSpaceTimestamp(nil)]);
    stored = PDSSpaceStepDone(database, statement, &localError);
  } error:nil];
  if (!executed || localError || !stored) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to store private space blob");
    return nil;
  }
  return [self blobForCID:cid.stringValue space:space author:author error:error];
}

- (NSDictionary<NSString *, id> *)blobForCID:(NSString *)cid
                                       space:(NSString *)space
                                      author:(NSString *)author
                                       error:(NSError **)error {
  if (cid.length == 0 || space.length == 0 || author.length == 0) {
    if (error) *error = [self invalidWriteError:@"Blob CID, space, and author are required"];
    return nil;
  }
  __block NSDictionary *result = nil;
  __block NSError *localError = nil;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (!PDSSpacePrepare(database,
                         "SELECT mime_type, size, data FROM space_blob "
                         "WHERE space = ? AND author_did = ? AND cid = ?",
                         &statement, &localError)) return;
    ATProtoDBBindParams(statement, @[space, author, cid]);
    if (sqlite3_step(statement) == SQLITE_ROW) {
      NSData *data = PDSSpaceDataColumn(statement, 2);
      result = @{ @"cid" : cid,
                  @"mimeType" : PDSSpaceStringColumn(statement, 0) ?: @"application/octet-stream",
                  @"size" : @(sqlite3_column_int64(statement, 1)),
                  @"data" : data ?: [NSData data] };
    }
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to read private space blob");
    return nil;
  }
  return result;
}

- (BOOL)recordWriter:(NSString *)writer forSpace:(NSString *)space rev:(NSString *)rev hash:(NSData *)hash
                 error:(NSError **)error {
  if (writer.length == 0 || space.length == 0 || rev.length == 0 || hash.length != 32) {
    if (error) *error = [self invalidWriteError:@"Writer, space, revision, and a 32-byte hash are required"];
    return NO;
  }
  __block NSError *localError = nil;
  __block BOOL success = NO;
  BOOL executed = [self.connection transact:^(sqlite3 *database, BOOL *rollback) {
    if (![self ensureActiveSpaceInTransaction:database space:space timestamp:PDSSpaceTimestamp(nil) error:&localError]) {
      *rollback = YES; return;
    }
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (!PDSSpacePrepare(database,
                         "INSERT INTO space_writer(space, did, rev, hash) VALUES(?, ?, ?, ?) "
                         "ON CONFLICT(space, did) DO UPDATE SET rev = excluded.rev, hash = excluded.hash "
                         "WHERE excluded.rev > space_writer.rev",
                         &statement, &localError)) { *rollback = YES; return; }
    ATProtoDBBindParams(statement, @[space, writer, rev, hash]);
    success = PDSSpaceStepDone(database, statement, &localError);
    if (!success) *rollback = YES;
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to record space writer");
    return NO;
  }
  return success;
}

- (NSArray<NSDictionary<NSString *, id> *> *)writersForSpace:(NSString *)space limit:(NSUInteger)limit
                                                       cursor:(NSString *)cursor error:(NSError **)error {
  NSUInteger clamped = MIN(MAX(limit, 1), 100);
  __block NSMutableArray *result = [NSMutableArray array];
  __block NSError *localError = nil;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    const char *sql = cursor.length > 0
        ? "SELECT did, rev, hash FROM space_writer WHERE space = ? AND did > ? ORDER BY did ASC LIMIT ?"
        : "SELECT did, rev, hash FROM space_writer WHERE space = ? ORDER BY did ASC LIMIT ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (!PDSSpacePrepare(database, sql, &statement, &localError)) return;
    ATProtoDBBindParams(statement, cursor.length > 0 ? @[space, cursor, @(clamped)] : @[space, @(clamped)]);
    int step = SQLITE_ROW;
    while ((step = sqlite3_step(statement)) == SQLITE_ROW) {
      [result addObject:@{ @"did" : PDSSpaceStringColumn(statement, 0) ?: @"",
                           @"rev" : PDSSpaceStringColumn(statement, 1) ?: @"",
                           @"hash" : PDSSpaceDataColumn(statement, 2) ?: [NSData data] }];
    }
    if (step != SQLITE_DONE) localError = PDSSpaceSQLiteError(database, @"Unable to list space writers");
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to list space writers");
    return nil;
  }
  return result;
}

- (BOOL)recordCredentialRecipientForSpace:(NSString *)space serviceDID:(NSString *)serviceDID
                           serviceEndpoint:(NSString *)serviceEndpoint expiresAt:(NSDate *)expiresAt
                                     error:(NSError **)error {
  if (space.length == 0 || serviceDID.length == 0 || serviceEndpoint.length == 0 ||
      !expiresAt || [expiresAt timeIntervalSinceNow] <= 0) {
    if (error) *error = [self invalidWriteError:@"Credential recipient and future expiration are required"];
    return NO;
  }
  __block NSError *localError = nil;
  __block BOOL success = NO;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (!PDSSpacePrepare(database,
                         "INSERT INTO space_credential_recipient(space, service_did, service_endpoint, last_issued_at, expires_at) "
                         "VALUES(?, ?, ?, ?, ?) ON CONFLICT(space, service_did) DO UPDATE SET "
                         "service_endpoint = excluded.service_endpoint, last_issued_at = excluded.last_issued_at, expires_at = excluded.expires_at",
                         &statement, &localError)) return;
    ATProtoDBBindParams(statement, @[space, serviceDID, serviceEndpoint, PDSSpaceTimestamp(nil),
                                    @(expiresAt.timeIntervalSince1970)]);
    success = PDSSpaceStepDone(database, statement, &localError);
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to record credential recipient");
    return NO;
  }
  return success;
}

- (NSArray<NSDictionary<NSString *, id> *> *)credentialRecipientsForSpace:(NSString *)space error:(NSError **)error {
  __block NSMutableArray *result = [NSMutableArray array];
  __block NSError *localError = nil;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *cleanup = NULL;
    if (!PDSSpacePrepare(database,
                         "DELETE FROM space_credential_recipient WHERE space = ? AND expires_at <= ?",
                         &cleanup, &localError)) return;
    ATProtoDBBindParams(cleanup, @[space, @([NSDate date].timeIntervalSince1970)]);
    if (!PDSSpaceStepDone(database, cleanup, &localError)) return;
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (!PDSSpacePrepare(database,
                         "SELECT service_did, service_endpoint, last_issued_at, expires_at FROM space_credential_recipient "
                         "WHERE space = ? AND expires_at > ? ORDER BY service_did ASC", &statement, &localError)) return;
    ATProtoDBBindParams(statement, @[space, @([NSDate date].timeIntervalSince1970)]);
    int step = SQLITE_ROW;
    while ((step = sqlite3_step(statement)) == SQLITE_ROW) {
      [result addObject:@{ @"serviceDID" : PDSSpaceStringColumn(statement, 0) ?: @"",
                           @"serviceEndpoint" : PDSSpaceStringColumn(statement, 1) ?: @"",
                           @"lastIssuedAt" : PDSSpaceStringColumn(statement, 2) ?: @"",
                           @"expiresAt" : @(sqlite3_column_double(statement, 3)) }];
    }
    if (step != SQLITE_DONE) localError = PDSSpaceSQLiteError(database, @"Unable to list credential recipients");
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to list credential recipients");
    return nil;
  }
  return result;
}

- (BOOL)consumeDelegationID:(NSString *)jti expiresAt:(NSDate *)expiresAt now:(NSDate *)now error:(NSError **)error {
  if (jti.length == 0 || !expiresAt || [expiresAt compare:now ?: [NSDate date]] != NSOrderedDescending) {
    if (error) *error = [self invalidWriteError:@"Delegation jti must be unexpired"];
    return NO;
  }
  __block NSError *localError = nil;
  __block BOOL inserted = NO;
  BOOL transacted = [self.connection transact:^(sqlite3 *database, BOOL *rollback) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *cleanup = NULL;
    if (!PDSSpacePrepare(database, "DELETE FROM space_delegation_replay WHERE expires_at <= ?", &cleanup, &localError)) {
      *rollback = YES; return;
    }
    ATProtoDBBindParams(cleanup, @[@((now ?: [NSDate date]).timeIntervalSince1970)]);
    if (!PDSSpaceStepDone(database, cleanup, &localError)) { *rollback = YES; return; }
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (!PDSSpacePrepare(database,
                         "INSERT OR IGNORE INTO space_delegation_replay(jti, expires_at) VALUES(?, ?)",
                         &statement, &localError)) {
      *rollback = YES; return;
    }
    ATProtoDBBindParams(statement, @[jti, @(expiresAt.timeIntervalSince1970)]);
    if (!PDSSpaceStepDone(database, statement, &localError)) { *rollback = YES; return; }
    inserted = sqlite3_changes(database) == 1;
  } error:nil];
  if (!transacted || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to record delegation replay state");
    return NO;
  }
  return inserted;
}

#pragma mark - Oplog pruning

- (BOOL)pruneOplogForSpace:(NSString *)space
                    author:(NSString *)author
          keepingRevisions:(NSUInteger)keepCount
                     error:(NSError **)error {
  if (space.length == 0 || author.length == 0) {
    if (error) *error = [self invalidWriteError:@"Space and author are required for oplog pruning"];
    return NO;
  }
  __block NSError *localError = nil;
  __block BOOL pruned = YES;
  BOOL transacted = [self.connection transact:^(sqlite3 *database, BOOL *rollback) {
    if (keepCount == 0) {
      PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *deleteAll = NULL;
      if (!PDSSpacePrepare(database,
                           "DELETE FROM space_record_oplog WHERE space = ? AND author_did = ?",
                           &deleteAll, &localError)) {
        *rollback = YES; return;
      }
      ATProtoDBBindParams(deleteAll, @[space, author]);
      if (!PDSSpaceStepDone(database, deleteAll, &localError)) { *rollback = YES; return; }
      return;
    }
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *prune = NULL;
    if (!PDSSpacePrepare(database,
                         "DELETE FROM space_record_oplog "
                         "WHERE space = ? AND author_did = ? "
                         "AND rev NOT IN ("
                           "SELECT DISTINCT rev FROM space_record_oplog "
                           "WHERE space = ? AND author_did = ? "
                           "ORDER BY rev DESC LIMIT ?"
                         ")",
                         &prune, &localError)) {
      *rollback = YES; return;
    }
    ATProtoDBBindParams(prune, @[space, author, space, author, @(keepCount)]);
    if (!PDSSpaceStepDone(database, prune, &localError)) { *rollback = YES; return; }
  } error:nil];
  if (!transacted || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to prune space oplog");
    return NO;
  }
  return pruned;
}

- (BOOL)pruneAllOplogsKeepingRevisions:(NSUInteger)keepCount error:(NSError **)error {
  return [self pruneAllOplogsKeepingRevisions:keepCount prunedEntries:NULL error:error];
}

- (BOOL)pruneAllOplogsKeepingRevisions:(NSUInteger)keepCount
                         prunedEntries:(NSUInteger *)prunedEntries
                                  error:(NSError **)error {
  if (prunedEntries) *prunedEntries = 0;
  NSArray<NSDictionary<NSString *, id> *> *repos = [self repositoriesWithOplogs:error];
  if (!repos) return NO;
  __block NSUInteger total = 0;
  for (NSDictionary<NSString *, id> *repo in repos) {
    __block NSError *localError = nil;
    __block NSUInteger removed = 0;
    BOOL transacted = [self.connection transact:^(sqlite3 *database, BOOL *rollback) {
      PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *prune = NULL;
      const char *sql = keepCount == 0
          ? "DELETE FROM space_record_oplog WHERE space = ? AND author_did = ?"
          : "DELETE FROM space_record_oplog WHERE space = ? AND author_did = ? AND rev NOT IN (SELECT DISTINCT rev FROM space_record_oplog WHERE space = ? AND author_did = ? ORDER BY rev DESC LIMIT ?)";
      if (!PDSSpacePrepare(database, sql, &prune, &localError)) { *rollback = YES; return; }
      ATProtoDBBindParams(prune, keepCount == 0 ? @[repo[@"space"], repo[@"author"]] : @[repo[@"space"], repo[@"author"], repo[@"space"], repo[@"author"], @(keepCount)]);
      if (!PDSSpaceStepDone(database, prune, &localError)) { *rollback = YES; return; }
      removed = (NSUInteger)sqlite3_changes(database);
    } error:nil];
    if (!transacted || localError) {
      if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to prune space oplog");
      return NO;
    }
    total += removed;
  }
  if (prunedEntries) *prunedEntries = total;
  return YES;
}

- (NSArray<NSDictionary<NSString *, id> *> *)repositoriesWithOplogs:(NSError **)error {
  __block NSMutableArray *result = [NSMutableArray array];
  __block NSError *localError = nil;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (!PDSSpacePrepare(database,
                         "SELECT DISTINCT space, author_did FROM space_record_oplog "
                         "ORDER BY space ASC, author_did ASC",
                         &statement, &localError)) return;
    int step = SQLITE_ROW;
    while ((step = sqlite3_step(statement)) == SQLITE_ROW) {
      NSString *space = PDSSpaceStringColumn(statement, 0);
      NSString *author = PDSSpaceStringColumn(statement, 1);
      if (space.length > 0 && author.length > 0) {
        [result addObject:@{ @"space" : space, @"author" : author }];
      }
    }
    if (step != SQLITE_DONE) localError = PDSSpaceSQLiteError(database, @"Unable to list repos with oplogs");
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to list repos with oplogs");
    return nil;
  }
  return result;
}

#pragma mark - CAR import

- (BOOL)importRepoFromCAR:(NSData *)carData
                    space:(NSString *)space
                   author:(NSString *)author
          commitPublicKey:(NSData *)publicKey
                    error:(NSError **)error {
  if (carData.length == 0 || space.length == 0 || author.length == 0 || publicKey.length == 0) {
    if (error) *error = [self invalidWriteError:@"CAR data, space, author, and public key are required"];
    return NO;
  }

  CARReader *reader = [CARReader readFromData:carData error:error];
  if (!reader) {
    if (error && !*error) *error = [NSError errorWithDomain:PDSSpaceStoreErrorDomain
                                                       code:PDSSpaceStoreErrorInvalidCAR
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse CAR"}];
    return NO;
  }
  if (reader.roots.count < 2) {
    if (error) *error = [NSError errorWithDomain:PDSSpaceStoreErrorDomain
                                            code:PDSSpaceStoreErrorInvalidCAR
                                        userInfo:@{NSLocalizedDescriptionKey: @"Space CAR must have two roots"}];
    return NO;
  }

  CARBlock *commitBlock = [reader blockWithCID:reader.roots[0]];
  CARBlock *indexBlock = [reader blockWithCID:reader.roots[1]];
  if (!commitBlock || !indexBlock) {
    if (error) *error = [NSError errorWithDomain:PDSSpaceStoreErrorDomain
                                            code:PDSSpaceStoreErrorMissingBlock
                                        userInfo:@{NSLocalizedDescriptionKey: @"CAR root blocks not found"}];
    return NO;
  }

  NSDictionary *commitDict = [ATProtoDagCBOR decodeData:commitBlock.data error:error];
  if (![commitDict isKindOfClass:[NSDictionary class]]) {
    if (error && !*error) *error = [NSError errorWithDomain:PDSSpaceStoreErrorDomain
                                                       code:PDSSpaceStoreErrorInvalidCAR
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Invalid commit block"}];
    return NO;
  }

  PDSSpaceCommit *commit = [PDSSpaceCommit commitFromDictionary:commitDict error:error];
  if (!commit) {
    if (error && !*error) *error = [NSError errorWithDomain:PDSSpaceStoreErrorDomain
                                                       code:PDSSpaceStoreErrorInvalidCAR
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Malformed commit in CAR"}];
    return NO;
  }

  if (![commit verifySignatureForSpace:space author:author publicKey:publicKey error:error]) {
    if (error && !*error) *error = [NSError errorWithDomain:PDSSpaceStoreErrorDomain
                                                       code:PDSSpaceStoreErrorCommitSignature
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Commit signature verification failed"}];
    return NO;
  }

  NSDictionary *indexDict = [ATProtoDagCBOR decodeData:indexBlock.data error:error];
  if (![indexDict isKindOfClass:[NSDictionary class]]) {
    if (error && !*error) *error = [NSError errorWithDomain:PDSSpaceStoreErrorDomain
                                                       code:PDSSpaceStoreErrorInvalidCAR
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Invalid index block"}];
    return NO;
  }

  PDSSpaceLtHash *importHash = [[PDSSpaceLtHash alloc] init];
  NSMutableArray<NSDictionary *> *importRecords = [NSMutableArray array];
  for (NSString *path in indexDict) {
    NSArray *parts = [path componentsSeparatedByString:@"/"];
    if (parts.count != 2 || ((NSString *)parts[0]).length == 0 || ((NSString *)parts[1]).length == 0) {
      if (error) *error = [NSError errorWithDomain:PDSSpaceStoreErrorDomain
                                              code:PDSSpaceStoreErrorInvalidCAR
                                          userInfo:@{NSLocalizedDescriptionKey: @"Invalid index path"}];
      return NO;
    }
    CID *recordCID = [indexDict cidObjectForKey:path];
    if (!recordCID) {
      if (error) *error = [NSError errorWithDomain:PDSSpaceStoreErrorDomain
                                              code:PDSSpaceStoreErrorInvalidCAR
                                          userInfo:@{NSLocalizedDescriptionKey: @"Index entry has no CID"}];
      return NO;
    }
    CARBlock *recordBlock = [reader blockWithCID:recordCID];
    if (!recordBlock) {
      if (error) *error = [NSError errorWithDomain:PDSSpaceStoreErrorDomain
                                              code:PDSSpaceStoreErrorMissingBlock
                                          userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Record block missing for %@", path]}];
      return NO;
    }
    NSString *element = [NSString stringWithFormat:@"%@/%@/%@", parts[0], parts[1], recordCID.stringValue];
    [importHash addElement:element];
    [importRecords addObject:@{ @"collection" : parts[0], @"rkey" : parts[1],
                                 @"cid" : recordCID.stringValue, @"value" : recordBlock.data }];
  }

  if (![importHash.digest isEqualToData:commit.commitHash]) {
    if (error) *error = [NSError errorWithDomain:PDSSpaceStoreErrorDomain
                                            code:PDSSpaceStoreErrorCommitMismatch
                                        userInfo:@{NSLocalizedDescriptionKey: @"LtHash digest does not match commit hash"}];
    return NO;
  }

  NSString *timestamp = PDSSpaceTimestamp(nil);
  __block NSError *localError = nil;
  __block BOOL imported = YES;
  BOOL transacted = [self.connection transact:^(sqlite3 *database, BOOL *rollback) {
    if (![self ensureRepositoryInTransaction:database space:space author:author timestamp:timestamp error:&localError]) {
      *rollback = YES; return;
    }
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *deleteRecords = NULL;
    if (!PDSSpacePrepare(database,
                         "DELETE FROM space_record WHERE space = ? AND author_did = ?",
                         &deleteRecords, &localError)) {
      *rollback = YES; return;
    }
    ATProtoDBBindParams(deleteRecords, @[space, author]);
    if (!PDSSpaceStepDone(database, deleteRecords, &localError)) { *rollback = YES; return; }

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *deleteOps = NULL;
    if (!PDSSpacePrepare(database,
                         "DELETE FROM space_record_oplog WHERE space = ? AND author_did = ?",
                         &deleteOps, &localError)) {
      *rollback = YES; return;
    }
    ATProtoDBBindParams(deleteOps, @[space, author]);
    if (!PDSSpaceStepDone(database, deleteOps, &localError)) { *rollback = YES; return; }

    for (NSDictionary *rec in importRecords) {
      PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *insert = NULL;
      if (!PDSSpacePrepare(database,
                           "INSERT INTO space_record(space, author_did, collection, rkey, cid, value, repo_rev, indexed_at) "
                           "VALUES(?, ?, ?, ?, ?, ?, ?, ?)",
                           &insert, &localError)) {
        *rollback = YES; return;
      }
      ATProtoDBBindParams(insert, @[space, author, rec[@"collection"], rec[@"rkey"],
                                    rec[@"cid"], rec[@"value"], commit.rev, timestamp]);
      if (!PDSSpaceStepDone(database, insert, &localError)) { *rollback = YES; return; }
    }

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *updateRepo = NULL;
    if (!PDSSpacePrepare(database,
                         "UPDATE space_repo SET lthash_state = ?, rev = ?, updated_at = ? "
                         "WHERE space = ? AND author_did = ?",
                         &updateRepo, &localError)) {
      *rollback = YES; return;
    }
    ATProtoDBBindParams(updateRepo, @[importHash.state, commit.rev, timestamp, space, author]);
    if (!PDSSpaceStepDone(database, updateRepo, &localError)) { *rollback = YES; return; }
  } error:nil];
  if (!transacted || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to import space CAR");
    return NO;
  }
  return imported;
}

#pragma mark - Local record index

- (NSDictionary<NSString *, NSString *> *)recordIndexForSpace:(NSString *)space
                                                        author:(NSString *)author
                                                         error:(NSError **)error {
  __block NSMutableDictionary *result = [NSMutableDictionary dictionary];
  __block NSError *localError = nil;
  BOOL executed = [self.connection execute:^(sqlite3 *database) {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *statement = NULL;
    if (!PDSSpacePrepare(database,
                         "SELECT collection, rkey, cid FROM space_record "
                         "WHERE space = ? AND author_did = ? ORDER BY collection, rkey",
                         &statement, &localError)) return;
    ATProtoDBBindParams(statement, @[space, author]);
    int step = SQLITE_ROW;
    while ((step = sqlite3_step(statement)) == SQLITE_ROW) {
      NSString *collection = PDSSpaceStringColumn(statement, 0) ?: @"";
      NSString *rkey = PDSSpaceStringColumn(statement, 1) ?: @"";
      NSString *cid = PDSSpaceStringColumn(statement, 2) ?: @"";
      NSString *path = [NSString stringWithFormat:@"%@/%@", collection, rkey];
      result[path] = cid;
    }
    if (step != SQLITE_DONE) localError = PDSSpaceSQLiteError(database, @"Unable to read record index");
  } error:nil];
  if (!executed || localError) {
    if (error) *error = localError ?: PDSSpaceSQLiteError(NULL, @"Unable to read record index");
    return nil;
  }
  return [result copy];
}

- (NSString *)JSONStringForStringArray:(NSArray<NSString *> *)values error:(NSError **)error {
  for (id value in values ?: @[]) {
    if (![value isKindOfClass:[NSString class]]) {
      if (error) *error = [self invalidWriteError:@"Space app allow-list must contain strings"];
      return nil;
    }
  }
  NSData *data = [NSJSONSerialization dataWithJSONObject:values ?: @[] options:0 error:error];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

- (NSArray<NSString *> *)stringArrayFromJSONString:(NSString *)string {
  NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
  id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  if (![object isKindOfClass:[NSArray class]]) return @[];
  NSMutableArray *result = [NSMutableArray array];
  for (id value in object) if ([value isKindOfClass:[NSString class]]) [result addObject:value];
  return result;
}

- (NSError *)invalidWriteError:(NSString *)message {
  return [NSError errorWithDomain:PDSSpaceStoreErrorDomain
                             code:PDSSpaceStoreErrorInvalidWrite
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}

- (NSError *)spaceNotFoundError {
  return [NSError errorWithDomain:PDSSpaceStoreErrorDomain
                             code:PDSSpaceStoreErrorSpaceNotFound
                         userInfo:@{NSLocalizedDescriptionKey : @"Owned active space was not found"}];
}

@end
