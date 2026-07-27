// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file SecItemLinuxStore.m
 *
 * @brief Persistent SQLite-backed keychain storage for Linux SecItem implementation.
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "SecItemLinuxStore.h"
#import "Debug/GZLogger.h"
#import "Compat/PDSTypes.h"
#import "Security/PDSKeyEnvelope.h"
#import <sqlite3.h>

#if PDS_PLATFORM_APPLE
#import <CommonCrypto/CommonDigest.h>
#else
#import "CommonCrypto/CommonDigest.h"
#endif

#define PDS_SQLITE_AUTORELEASE_STMT __attribute__((cleanup(PDS_sqlite3_finalize_cleanup)))

static inline void PDS_sqlite3_finalize_cleanup(sqlite3_stmt **stmt) {
    if (*stmt) {
        sqlite3_finalize(*stmt);
    }
}

// SQLite error domain
NSString * const SecItemLinuxStoreErrorDomain = @"SecItemLinuxStoreErrorDomain";

// Returned when the store cannot be opened or used because no operator
// key is configured. Never fall back to plaintext on this path.
static const NSInteger kSecItemLinuxStoreErrorMissingKey = -100;
static const NSInteger kSecItemLinuxStoreErrorDecryptionFailed = -101;

static sqlite3 *gKeychainDB = NULL;
static dispatch_queue_t gKeychainQueue = NULL;
static dispatch_once_t gKeychainOnce = 0;
static NSData *gKeychainEncryptionKey = nil;

static NSString *PDSSecItemLinuxStoreDatabasePath(void);

/// Mirrors the test-detection convention used elsewhere in the app
/// (e.g. ATProtoServiceConfigRunningUnderTests) without introducing a
/// Compat -> App layering dependency.
static BOOL PDSSecItemLinuxStoreRunningUnderTests(void) {
    if (NSClassFromString(@"XCTestCase") != nil) {
        return YES;
    }
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    if ([env[@"XCTestConfigurationFilePath"] length] > 0 ||
        [env[@"XCTestBundlePath"] length] > 0 ||
        [env[@"PDS_RUNNING_TESTS"] length] > 0) {
        return YES;
    }
    NSString *processName = [[[NSProcessInfo processInfo] processName] lowercaseString];
    return [processName containsString:@"alltests"] || [processName containsString:@"xctest"];
}

/// Returns the production keychain path, or a process-local scratch path for
/// the test runner.  The override is deliberately accepted only under tests:
/// operators configure the key, not an alternate persistence location.
static NSString *PDSSecItemLinuxStoreDatabasePath(void) {
    const char *configuredPath = getenv("PDS_LINUX_KEYCHAIN_DB_PATH");
    NSString *testPath = configuredPath ? [NSString stringWithUTF8String:configuredPath] : nil;
    if (PDSSecItemLinuxStoreRunningUnderTests() && testPath.length > 0) {
        return testPath;
    }
    return [[NSHomeDirectory() stringByAppendingPathComponent:@".pds"]
        stringByAppendingPathComponent:@"keychain.db"];
}

/// Derives a 32-byte AES-256 key from arbitrary operator-supplied secret
/// material via a context-tagged SHA-256, matching the derivation style
/// already used by PDSKeyEnvelope for its MAC subkey.
static NSData *PDSSecItemLinuxStoreDeriveKey(NSString *secretMaterial) {
    if (secretMaterial.length == 0) {
        return nil;
    }
    static const uint8_t context[] = "pds-linux-keychain-store-v1";
    NSMutableData *input = [NSMutableData dataWithData:[secretMaterial dataUsingEncoding:NSUTF8StringEncoding]];
    [input appendBytes:context length:sizeof(context) - 1];

    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(input.bytes, (CC_LONG)input.length, digest);
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

/// Resolves the operator-supplied encryption key from an environment
/// variable or a key file, per the decision recorded in workstream 01 S11:
/// Linux secrets are encrypted at rest with an operator-supplied key, never
/// an implicit or OS-keyring-derived one.
static NSData *PDSSecItemLinuxStoreResolveKey(void) {
    const char *directValue = getenv("PDS_LINUX_KEYCHAIN_KEY");
    NSString *direct = directValue ? [NSString stringWithUTF8String:directValue] : nil;
    if (direct.length > 0) {
        return PDSSecItemLinuxStoreDeriveKey(direct);
    }

    const char *keyFileValue = getenv("PDS_LINUX_KEYCHAIN_KEY_FILE");
    NSString *keyFilePath = keyFileValue ? [NSString stringWithUTF8String:keyFileValue] : nil;
    if (keyFilePath.length > 0) {
        NSError *readError = nil;
        NSString *fileContents = [NSString stringWithContentsOfFile:keyFilePath
                                                             encoding:NSUTF8StringEncoding
                                                                error:&readError];
        if (!fileContents) {
            GZ_LOG_ERROR(@"SecItemLinuxStore: Failed to read PDS_LINUX_KEYCHAIN_KEY_FILE at %@: %@", keyFilePath, readError);
            return nil;
        }
        NSString *trimmed = [fileContents stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            GZ_LOG_ERROR(@"SecItemLinuxStore: PDS_LINUX_KEYCHAIN_KEY_FILE at %@ is empty", keyFilePath);
            return nil;
        }
        return PDSSecItemLinuxStoreDeriveKey(trimmed);
    }

    return nil;
}

@implementation SecItemLinuxStore

+ (instancetype)sharedStore {
    static SecItemLinuxStore *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SecItemLinuxStore alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        if (!gKeychainQueue) {
            gKeychainQueue = dispatch_queue_create("com.pds.keychain", DISPATCH_QUEUE_SERIAL);
        }
        dispatch_once(&gKeychainOnce, ^{
            [self _openDatabase];
        });
    }
    return self;
}

- (void)_openDatabase {
    gKeychainEncryptionKey = PDSSecItemLinuxStoreResolveKey();
    if (!gKeychainEncryptionKey) {
        GZ_LOG_ERROR(@"SecItemLinuxStore: No encryption key configured. Set "
                      @"PDS_LINUX_KEYCHAIN_KEY or PDS_LINUX_KEYCHAIN_KEY_FILE before "
                      @"starting. Refusing to open the Linux secret store — it will "
                      @"never fall back to writing plaintext.");
        if (!PDSSecItemLinuxStoreRunningUnderTests()) {
            // Fail startup loudly rather than run with an unusable (and
            // therefore effectively unencrypted-or-unreadable) secret store.
            exit(1);
        }
        // Under tests, leave gKeychainDB NULL so every operation below
        // returns kSecItemLinuxStoreErrorMissingKey instead of crashing the
        // test binary or silently touching plaintext.
        return;
    }

    NSString *dbPath = PDSSecItemLinuxStoreDatabasePath();
    NSString *pdsDir = [dbPath stringByDeletingLastPathComponent];

    // Create .pds directory if needed
    NSError *dirError = nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:pdsDir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:pdsDir
                                   withIntermediateDirectories:YES
                                                    attributes:@{ NSFilePosixPermissions: @0700 }
                                                         error:&dirError];
        if (dirError) {
            GZ_LOG_ERROR(@"SecItemLinuxStore: Failed to create .pds directory: %@", dirError);
            return;
        }
    }

    // Set strict permissions on database file. Encryption is in addition to
    // these, not instead of them.
    if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
        [[NSFileManager defaultManager] createFileAtPath:dbPath contents:nil attributes:@{ NSFilePosixPermissions: @0600 }];
    }
    [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @0600 }
                                     ofItemAtPath:dbPath
                                            error:nil];

    // Open database
    int rc = sqlite3_open([dbPath UTF8String], &gKeychainDB);
    if (rc != SQLITE_OK) {
        GZ_LOG_ERROR(@"SecItemLinuxStore: Failed to open keychain database: %s", sqlite3_errmsg(gKeychainDB));
        gKeychainDB = NULL;
        return;
    }

    // Enable WAL mode for better concurrency
    sqlite3_exec(gKeychainDB, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);

    // Create schema if needed
    [self _createSchema];

    // Rewrite any rows still in the old plaintext format now that a key is
    // available. Rows already sealed by a prior run are left untouched.
    if (![self _migrateLegacyPlaintextRows]) {
        GZ_LOG_ERROR(@"SecItemLinuxStore: Legacy plaintext migration failed; refusing to open the secret store.");
        sqlite3_close(gKeychainDB);
        gKeychainDB = NULL;
    }
}

- (void)_createSchema {
    const char *sql = "CREATE TABLE IF NOT EXISTS items ("
        "id INTEGER PRIMARY KEY,"
        "service TEXT NOT NULL,"
        "account TEXT NOT NULL,"
        "data BLOB,"
        "attrs TEXT NOT NULL," // JSON/PLIST-encoded attributes, sealed at rest
        "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,"
        "updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,"
        "UNIQUE(service, account)"
        ");";

    char *errMsg = NULL;
    int rc = sqlite3_exec(gKeychainDB, sql, NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        GZ_LOG_ERROR(@"SecItemLinuxStore: Failed to create schema: %s", errMsg);
        sqlite3_free(errMsg);
    }
}

/// Seals a blob for storage if it isn't already sealed. Returns nil (with a
/// logged error) only on an actual encryption failure — callers must not
/// fall back to writing the plaintext input on failure.
- (nullable NSData *)_sealForStorage:(NSData *)plaintext {
    if (!plaintext) {
        return nil;
    }
    NSError *sealError = nil;
    NSData *sealed = [PDSKeyEnvelope seal:plaintext withKey:gKeychainEncryptionKey error:&sealError];
    if (!sealed) {
        GZ_LOG_ERROR(@"SecItemLinuxStore: Failed to seal item for storage: %@", sealError);
    }
    return sealed;
}

/// Opens a blob read from storage, transparently accepting the legacy
/// plaintext format for at least one release. Returns nil only when the
/// blob is a sealed envelope that fails to open (wrong key or corruption) —
/// never returns raw ciphertext to the caller.
- (nullable NSData *)_openFromStorage:(NSData *)stored error:(NSError **)error {
    if (!stored) {
        return nil;
    }
    if (![PDSKeyEnvelope isVersionedEnvelope:stored]) {
        // Legacy plaintext row, not yet migrated.
        return stored;
    }
    NSError *openError = nil;
    NSData *plaintext = [PDSKeyEnvelope openEnvelope:stored withKey:gKeychainEncryptionKey error:&openError];
    if (!plaintext) {
        GZ_LOG_ERROR(@"SecItemLinuxStore: Failed to open sealed item: %@", openError);
        if (error) {
            *error = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                          code:kSecItemLinuxStoreErrorDecryptionFailed
                                      userInfo:@{NSLocalizedDescriptionKey: @"Failed to decrypt stored item"}];
        }
        return nil;
    }
    return plaintext;
}

/// Rewrites every row still in the old plaintext format to a sealed
/// envelope, using the now-available operator key. Idempotent: rows already
/// sealed are skipped.
- (BOOL)_migrateLegacyPlaintextRows {
    if (!gKeychainDB || !gKeychainEncryptionKey) {
        return NO;
    }
    if (sqlite3_exec(gKeychainDB, "BEGIN IMMEDIATE TRANSACTION", NULL, NULL, NULL) != SQLITE_OK) {
        GZ_LOG_ERROR(@"SecItemLinuxStore: Migration could not begin transaction: %s", sqlite3_errmsg(gKeychainDB));
        return NO;
    }

    const char *selectSQL = "SELECT id, data, attrs FROM items";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *selectStmt = NULL;
    if (sqlite3_prepare_v2(gKeychainDB, selectSQL, -1, &selectStmt, NULL) != SQLITE_OK) {
        GZ_LOG_ERROR(@"SecItemLinuxStore: Migration scan failed to prepare: %s", sqlite3_errmsg(gKeychainDB));
        sqlite3_exec(gKeychainDB, "ROLLBACK", NULL, NULL, NULL);
        return NO;
    }

    NSMutableArray<NSNumber *> *rowIDsToMigrate = [NSMutableArray array];
    NSMutableArray *migratedData = [NSMutableArray array];
    NSMutableArray<NSData *> *migratedAttrs = [NSMutableArray array];
    NSUInteger migratedCount = 0;
    int selectRC = SQLITE_OK;

    while ((selectRC = sqlite3_step(selectStmt)) == SQLITE_ROW) {
        sqlite3_int64 rowID = sqlite3_column_int64(selectStmt, 0);

        const void *dataBytes = sqlite3_column_blob(selectStmt, 1);
        int dataLen = sqlite3_column_bytes(selectStmt, 1);
        BOOL hasData = sqlite3_column_type(selectStmt, 1) != SQLITE_NULL;
        NSData *existingData = hasData ? (dataLen > 0 ? [NSData dataWithBytes:dataBytes length:(NSUInteger)dataLen] : [NSData data]) : nil;

        const void *attrBytes = sqlite3_column_blob(selectStmt, 2);
        int attrLen = sqlite3_column_bytes(selectStmt, 2);
        BOOL hasAttrs = sqlite3_column_type(selectStmt, 2) != SQLITE_NULL;
        NSData *existingAttrs = hasAttrs ? (attrLen > 0 ? [NSData dataWithBytes:attrBytes length:(NSUInteger)attrLen] : [NSData data]) : nil;

        BOOL dataNeedsMigration = existingData && ![PDSKeyEnvelope isVersionedEnvelope:existingData];
        BOOL attrsNeedsMigration = existingAttrs && ![PDSKeyEnvelope isVersionedEnvelope:existingAttrs];
        if (!dataNeedsMigration && !attrsNeedsMigration) {
            continue;
        }

        NSData *sealedData = dataNeedsMigration ? [self _sealForStorage:existingData] : existingData;
        NSData *sealedAttrs = attrsNeedsMigration ? [self _sealForStorage:existingAttrs] : existingAttrs;
        if ((dataNeedsMigration && !sealedData) || (attrsNeedsMigration && !sealedAttrs)) {
            GZ_LOG_ERROR(@"SecItemLinuxStore: Migration could not seal a legacy row.");
            sqlite3_finalize(selectStmt);
            selectStmt = NULL;
            sqlite3_exec(gKeychainDB, "ROLLBACK", NULL, NULL, NULL);
            return NO;
        }

        [rowIDsToMigrate addObject:@(rowID)];
        [migratedData addObject:sealedData ?: [NSNull null]];
        [migratedAttrs addObject:sealedAttrs ?: [NSData data]];
    }

    if (selectRC != SQLITE_DONE) {
        GZ_LOG_ERROR(@"SecItemLinuxStore: Migration scan failed: %s", sqlite3_errmsg(gKeychainDB));
        sqlite3_finalize(selectStmt);
        selectStmt = NULL;
        sqlite3_exec(gKeychainDB, "ROLLBACK", NULL, NULL, NULL);
        return NO;
    }
    sqlite3_finalize(selectStmt);
    selectStmt = NULL;

    for (NSUInteger i = 0; i < rowIDsToMigrate.count; i++) {
        const char *updateSQL = "UPDATE items SET data = ?, attrs = ? WHERE id = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *updateStmt = NULL;
        if (sqlite3_prepare_v2(gKeychainDB, updateSQL, -1, &updateStmt, NULL) != SQLITE_OK) {
            GZ_LOG_ERROR(@"SecItemLinuxStore: Migration update failed to prepare: %s", sqlite3_errmsg(gKeychainDB));
            sqlite3_exec(gKeychainDB, "ROLLBACK", NULL, NULL, NULL);
            return NO;
        }
        id dataValue = migratedData[i];
        NSData *data = dataValue == [NSNull null] ? nil : (NSData *)dataValue;
        NSData *attrs = migratedAttrs[i];
        if (data) {
            sqlite3_bind_blob(updateStmt, 1, data.bytes, (int)data.length, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(updateStmt, 1);
        }
        sqlite3_bind_blob(updateStmt, 2, attrs.bytes, (int)attrs.length, SQLITE_TRANSIENT);
        sqlite3_bind_int64(updateStmt, 3, rowIDsToMigrate[i].longLongValue);
        if (sqlite3_step(updateStmt) == SQLITE_DONE) {
            migratedCount++;
        } else {
            GZ_LOG_ERROR(@"SecItemLinuxStore: Migration update failed: %s", sqlite3_errmsg(gKeychainDB));
            sqlite3_exec(gKeychainDB, "ROLLBACK", NULL, NULL, NULL);
            return NO;
        }
    }

    if (sqlite3_exec(gKeychainDB, "COMMIT", NULL, NULL, NULL) != SQLITE_OK) {
        GZ_LOG_ERROR(@"SecItemLinuxStore: Migration could not commit: %s", sqlite3_errmsg(gKeychainDB));
        sqlite3_exec(gKeychainDB, "ROLLBACK", NULL, NULL, NULL);
        return NO;
    }

    if (migratedCount > 0 && sqlite3_wal_checkpoint_v2(gKeychainDB, NULL, SQLITE_CHECKPOINT_TRUNCATE, NULL, NULL) != SQLITE_OK) {
        GZ_LOG_ERROR(@"SecItemLinuxStore: Migration could not checkpoint encrypted rows: %s", sqlite3_errmsg(gKeychainDB));
        return NO;
    }

    if (migratedCount > 0) {
        GZ_LOG_INFO(@"SecItemLinuxStore: Migration rewrote %lu legacy plaintext row(s) to sealed envelopes.",
                     (unsigned long)migratedCount);
    }
    return YES;
}

/// Raw existence check assuming the caller is already executing on
/// gKeychainQueue. Callers already inside a dispatch_sync onto that queue
/// must use this instead of the public itemExistsWithService:account:,
/// which itself dispatch_syncs onto the same serial queue and would
/// deadlock if called reentrantly.
- (BOOL)_itemExistsUnlockedWithService:(NSString *)service account:(NSString *)account {
    if (!service || !account || !gKeychainDB) {
        return NO;
    }
    const char *sql = "SELECT 1 FROM items WHERE service = ? AND account = ? LIMIT 1";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(gKeychainDB, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return NO;
    }
    sqlite3_bind_text(stmt, 1, [service UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [account UTF8String], -1, SQLITE_TRANSIENT);
    return sqlite3_step(stmt) == SQLITE_ROW;
}

/// Raw fetch-and-decrypt assuming the caller is already executing on
/// gKeychainQueue. See _itemExistsUnlockedWithService:account: for why this
/// exists separately from the public itemWithService:account:error:.
- (nullable NSDictionary *)_itemUnlockedWithService:(NSString *)service
                                             account:(NSString *)account
                                               error:(NSError **)error {
    const char *sql = "SELECT data, attrs FROM items WHERE service = ? AND account = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;

    if (sqlite3_prepare_v2(gKeychainDB, sql, -1, &stmt, NULL) != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain code:-1 userInfo:nil];
        }
        return nil;
    }

    sqlite3_bind_text(stmt, 1, [service UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [account UTF8String], -1, SQLITE_TRANSIENT);

    int rc = sqlite3_step(stmt);
    if (rc != SQLITE_ROW) {
        if (rc != SQLITE_DONE && error) {
            *error = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain code:rc userInfo:nil];
        }
        return nil;
    }

    NSDictionary *result = nil;
    const void *attrBytes = sqlite3_column_blob(stmt, 1);
    int attrLen = sqlite3_column_bytes(stmt, 1);
    if (!attrBytes || attrLen <= 0) {
        return nil;
    }

    NSData *storedAttrs = [NSData dataWithBytes:attrBytes length:attrLen];
    NSError *openError = nil;
    NSData *plistData = [self _openFromStorage:storedAttrs error:&openError];
    if (!plistData) {
        if (error) *error = openError;
        return nil;
    }

    result = [NSPropertyListSerialization propertyListWithData:plistData options:0 format:NULL error:nil];
    if (!result) {
        // Fallback to legacy JSON format for migration
        result = [NSJSONSerialization JSONObjectWithData:plistData options:0 error:nil];
    }

    const void *dataBytes = sqlite3_column_blob(stmt, 0);
    int dataLen = sqlite3_column_bytes(stmt, 0);
    if (dataBytes && dataLen > 0 && result) {
        NSData *storedValue = [NSData dataWithBytes:dataBytes length:dataLen];
        NSError *valueOpenError = nil;
        NSData *valuePlaintext = [self _openFromStorage:storedValue error:&valueOpenError];
        if (!valuePlaintext) {
            if (error) *error = valueOpenError;
            return nil;
        }
        NSMutableDictionary *mutableResult = [result mutableCopy];
        mutableResult[(__bridge NSString *)kSecValueData] = valuePlaintext;
        result = [mutableResult copy];
    }

    return result;
}

/// Returns NO with a clear error when the store could not be opened —
/// almost always because no encryption key was configured.
- (BOOL)_requireOpenDatabase:(NSError **)error {
    if (gKeychainDB) {
        return YES;
    }
    if (error) {
        *error = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                      code:kSecItemLinuxStoreErrorMissingKey
                                  userInfo:@{NSLocalizedDescriptionKey: @"Linux secret store is unavailable: no encryption key configured (set PDS_LINUX_KEYCHAIN_KEY or PDS_LINUX_KEYCHAIN_KEY_FILE)"}];
    }
    return NO;
}

- (BOOL)addItemWithService:(NSString *)service
                   account:(NSString *)account
                attributes:(NSDictionary *)attributes
                     error:(NSError **)error {
    if (!service || !account || !attributes) {
        if (error) {
            *error = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                         code:-50
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameters"}];
        }
        return NO;
    }
    if (![self _requireOpenDatabase:error]) {
        return NO;
    }

    __block BOOL success = NO;
    __block NSError *blockError = nil;
    dispatch_sync(gKeychainQueue, ^{
        // Check for duplicate
        if ([self _itemExistsUnlockedWithService:service account:account]) {
            blockError = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                             code:-25299
                                         userInfo:@{NSLocalizedDescriptionKey: @"Duplicate item"}];
            return;
        }

        // Serialize attributes to PLIST
        NSError *plistError = nil;
        NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:attributes
                                                                       format:NSPropertyListBinaryFormat_v1_0
                                                                      options:0
                                                                        error:&plistError];
        if (!plistData) {
            blockError = plistError ?: [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                                           code:-50
                                                       userInfo:nil];
            return;
        }

        // Extract value data if present
        NSData *valueData = attributes[(__bridge NSString *)kSecValueData];

        NSData *sealedAttrs = [self _sealForStorage:plistData];
        if (!sealedAttrs) {
            blockError = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                            code:kSecItemLinuxStoreErrorDecryptionFailed
                                        userInfo:@{NSLocalizedDescriptionKey: @"Failed to seal item attributes"}];
            return;
        }
        NSData *sealedValue = nil;
        if (valueData) {
            sealedValue = [self _sealForStorage:valueData];
            if (!sealedValue) {
                blockError = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                                code:kSecItemLinuxStoreErrorDecryptionFailed
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to seal item value"}];
                return;
            }
        }

        const char *sql = "INSERT INTO items (service, account, data, attrs) VALUES (?, ?, ?, ?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;

        int rc = sqlite3_prepare_v2(gKeychainDB, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            blockError = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                            code:rc
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:sqlite3_errmsg(gKeychainDB)]}];
            return;
        }

        sqlite3_bind_text(stmt, 1, [service UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [account UTF8String], -1, SQLITE_TRANSIENT);
        if (sealedValue) {
            sqlite3_bind_blob(stmt, 3, [sealedValue bytes], (int)[sealedValue length], SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt, 3);
        }
        sqlite3_bind_blob(stmt, 4, [sealedAttrs bytes], (int)[sealedAttrs length], SQLITE_TRANSIENT);

        rc = sqlite3_step(stmt);
        if (rc == SQLITE_DONE) {
            success = YES;
        } else {
            blockError = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                            code:rc
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:sqlite3_errmsg(gKeychainDB)]}];
        }
    });

    if (error) {
        *error = blockError;
    }
    return success;
}

- (nullable NSDictionary *)itemWithService:(NSString *)service
                                   account:(NSString *)account
                                     error:(NSError **)error {
    if (!service || !account) {
        if (error) {
            *error = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                         code:-50
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameters"}];
        }
        return nil;
    }
    if (![self _requireOpenDatabase:error]) {
        return nil;
    }

    __block NSDictionary *result = nil;
    __block NSError *blockError = nil;
    dispatch_sync(gKeychainQueue, ^{
        result = [self _itemUnlockedWithService:service account:account error:&blockError];
    });

    if (error) {
        *error = blockError;
    }
    return result;
}

- (BOOL)updateItemWithService:(NSString *)service
                      account:(NSString *)account
            attributesToUpdate:(NSDictionary *)attributesToUpdate
                        error:(NSError **)error {
    if (!service || !account) {
        if (error) {
            *error = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                         code:-50
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameters"}];
        }
        return NO;
    }
    if (![self _requireOpenDatabase:error]) {
        return NO;
    }

    __block BOOL success = NO;
    __block NSError *blockError = nil;
    dispatch_sync(gKeychainQueue, ^{
        // Fetch existing item
        NSError *itemError = nil;
        NSDictionary *existing = [self _itemUnlockedWithService:service account:account error:&itemError];
        if (!existing) {
            blockError = itemError ?: [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                                          code:-25300
                                                      userInfo:@{NSLocalizedDescriptionKey: @"Item not found"}];
            return;
        }

        // Merge attributes
        NSMutableDictionary *updated = [existing mutableCopy];
        [updated addEntriesFromDictionary:attributesToUpdate];

        // Serialize to PLIST
        NSError *plistError = nil;
        NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:updated
                                                                       format:NSPropertyListBinaryFormat_v1_0
                                                                      options:0
                                                                        error:&plistError];
        if (!plistData) {
            blockError = plistError;
            return;
        }

        NSData *valueData = updated[(__bridge NSString *)kSecValueData];

        NSData *sealedAttrs = [self _sealForStorage:plistData];
        if (!sealedAttrs) {
            blockError = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                            code:kSecItemLinuxStoreErrorDecryptionFailed
                                        userInfo:@{NSLocalizedDescriptionKey: @"Failed to seal item attributes"}];
            return;
        }
        NSData *sealedValue = nil;
        if (valueData) {
            sealedValue = [self _sealForStorage:valueData];
            if (!sealedValue) {
                blockError = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                                code:kSecItemLinuxStoreErrorDecryptionFailed
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to seal item value"}];
                return;
            }
        }

        const char *sql = "UPDATE items SET data = ?, attrs = ?, updated_at = CURRENT_TIMESTAMP WHERE service = ? AND account = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;

        int rc = sqlite3_prepare_v2(gKeychainDB, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            blockError = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain code:rc userInfo:nil];
            return;
        }

        if (sealedValue) {
            sqlite3_bind_blob(stmt, 1, [sealedValue bytes], (int)[sealedValue length], SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt, 1);
        }
        sqlite3_bind_blob(stmt, 2, [sealedAttrs bytes], (int)[sealedAttrs length], SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, [service UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 4, [account UTF8String], -1, SQLITE_TRANSIENT);

        rc = sqlite3_step(stmt);
        if (rc == SQLITE_DONE) {
            success = YES;
        } else {
            blockError = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain code:rc userInfo:nil];
        }
    });

    if (error) {
        *error = blockError;
    }
    return success;
}

- (BOOL)deleteItemWithService:(NSString *)service
                      account:(NSString *)account
                        error:(NSError **)error {
    if (!service || !account) {
        if (error) {
            *error = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                         code:-50
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameters"}];
        }
        return NO;
    }
    if (![self _requireOpenDatabase:error]) {
        return NO;
    }

    __block BOOL success = NO;
    __block NSError *blockError = nil;
    dispatch_sync(gKeychainQueue, ^{
        const char *sql = "DELETE FROM items WHERE service = ? AND account = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;

        int rc = sqlite3_prepare_v2(gKeychainDB, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            blockError = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain code:rc userInfo:nil];
            return;
        }

        sqlite3_bind_text(stmt, 1, [service UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [account UTF8String], -1, SQLITE_TRANSIENT);

        rc = sqlite3_step(stmt);
        if (rc == SQLITE_DONE) {
            if (sqlite3_changes(gKeychainDB) > 0) {
                success = YES;
            } else {
                blockError = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                                code:-25300
                                            userInfo:@{NSLocalizedDescriptionKey: @"Item not found"}];
            }
        } else {
            blockError = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain code:rc userInfo:nil];
        }
    });

    if (error) {
        *error = blockError;
    }
    return success;
}

- (BOOL)itemExistsWithService:(NSString *)service
                      account:(NSString *)account {
    if (!service || !account || !gKeychainDB) {
        return NO;
    }

    __block BOOL exists = NO;
    dispatch_sync(gKeychainQueue, ^{
        exists = [self _itemExistsUnlockedWithService:service account:account];
    });

    return exists;
}

@end
