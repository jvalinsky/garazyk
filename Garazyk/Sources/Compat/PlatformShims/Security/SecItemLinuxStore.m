/**
 * @file SecItemLinuxStore.m
 *
 * @brief Persistent SQLite-backed keychain storage for Linux SecItem implementation.
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "SecItemLinuxStore.h"
#import <sqlite3.h>

#define PDS_SQLITE_AUTORELEASE_STMT __attribute__((cleanup(PDS_sqlite3_finalize_cleanup)))

static inline void PDS_sqlite3_finalize_cleanup(sqlite3_stmt **stmt) {
    if (*stmt) {
        sqlite3_finalize(*stmt);
    }
}

// SQLite error domain
NSString * const SecItemLinuxStoreErrorDomain = @"SecItemLinuxStoreErrorDomain";

static sqlite3 *gKeychainDB = NULL;
static dispatch_queue_t gKeychainQueue = NULL;
static dispatch_once_t gKeychainOnce = 0;

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
    NSString *homeDir = NSHomeDirectory();
    NSString *pdsDir = [homeDir stringByAppendingPathComponent:@".pds"];
    NSString *dbPath = [pdsDir stringByAppendingPathComponent:@"keychain.db"];

    // Create .pds directory if needed
    NSError *dirError = nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:pdsDir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:pdsDir
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&dirError];
        if (dirError) {
            PDS_LOG_ERROR(@"SecItemLinuxStore: Failed to create .pds directory: %@", dirError);
            return;
        }
    }

    // Open database
    int rc = sqlite3_open([dbPath UTF8String], &gKeychainDB);
    if (rc != SQLITE_OK) {
        PDS_LOG_ERROR(@"SecItemLinuxStore: Failed to open keychain database: %s", sqlite3_errmsg(gKeychainDB));
        return;
    }

    // Enable WAL mode for better concurrency
    sqlite3_exec(gKeychainDB, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);

    // Create schema if needed
    [self _createSchema];
}

- (void)_createSchema {
    const char *sql = "CREATE TABLE IF NOT EXISTS items ("
        "id INTEGER PRIMARY KEY,"
        "service TEXT NOT NULL,"
        "account TEXT NOT NULL,"
        "data BLOB,"
        "attrs TEXT NOT NULL," // JSON-encoded attributes
        "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,"
        "updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,"
        "UNIQUE(service, account)"
        ");";

    char *errMsg = NULL;
    int rc = sqlite3_exec(gKeychainDB, sql, NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        PDS_LOG_ERROR(@"SecItemLinuxStore: Failed to create schema: %s", errMsg);
        sqlite3_free(errMsg);
    }
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

    __block BOOL success = NO;
    __block NSError *blockError = nil;
    dispatch_sync(gKeychainQueue, ^{
        // Check for duplicate
        if ([self itemExistsWithService:service account:account]) {
            blockError = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                             code:-25299
                                         userInfo:@{NSLocalizedDescriptionKey: @"Duplicate item"}];
            return;
        }

        // Serialize attributes to JSON
        NSError *jsonError = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:attributes options:0 error:&jsonError];
        if (!jsonData) {
            blockError = jsonError ?: [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                                          code:-50
                                                      userInfo:nil];
            return;
        }

        // Extract value data if present
        NSData *valueData = attributes[(__bridge NSString *)kSecValueData];

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
        if (valueData) {
            sqlite3_bind_blob(stmt, 3, [valueData bytes], (int)[valueData length], SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt, 3);
        }
        sqlite3_bind_blob(stmt, 4, [jsonData bytes], (int)[jsonData length], SQLITE_TRANSIENT);

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

    __block NSDictionary *result = nil;
    __block NSError *blockError = nil;
    dispatch_sync(gKeychainQueue, ^{
        const char *sql = "SELECT data, attrs FROM items WHERE service = ? AND account = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;

        int rc = sqlite3_prepare_v2(gKeychainDB, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            blockError = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain code:rc userInfo:nil];
            return;
        }

        sqlite3_bind_text(stmt, 1, [service UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [account UTF8String], -1, SQLITE_TRANSIENT);

        rc = sqlite3_step(stmt);
        if (rc == SQLITE_ROW) {
            // Deserialize attributes
            const void *attrBytes = sqlite3_column_blob(stmt, 1);
            int attrLen = sqlite3_column_bytes(stmt, 1);

            if (attrBytes && attrLen > 0) {
                NSData *jsonData = [NSData dataWithBytes:attrBytes length:attrLen];
                NSError *jsonError = nil;
                result = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];

                // Add back the value data if present
                const void *dataBytes = sqlite3_column_blob(stmt, 0);
                int dataLen = sqlite3_column_bytes(stmt, 0);
                if (dataBytes && dataLen > 0 && result) {
                    NSMutableDictionary *mutableResult = [result mutableCopy];
                    mutableResult[(__bridge NSString *)kSecValueData] = [NSData dataWithBytes:dataBytes length:dataLen];
                    result = [mutableResult copy];
                }
            }
        } else if (rc != SQLITE_DONE) {
            blockError = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain code:rc userInfo:nil];
        }
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

    __block BOOL success = NO;
    __block NSError *blockError = nil;
    dispatch_sync(gKeychainQueue, ^{
        // Fetch existing item
        NSError *itemError = nil;
        NSDictionary *existing = [self itemWithService:service account:account error:&itemError];
        if (!existing) {
            blockError = itemError ?: [NSError errorWithDomain:SecItemLinuxStoreErrorDomain
                                                          code:-25300
                                                      userInfo:@{NSLocalizedDescriptionKey: @"Item not found"}];
            return;
        }

        // Merge attributes
        NSMutableDictionary *updated = [existing mutableCopy];
        [updated addEntriesFromDictionary:attributesToUpdate];

        // Serialize to JSON
        NSError *jsonError = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:updated options:0 error:&jsonError];
        if (!jsonData) {
            blockError = jsonError;
            return;
        }

        NSData *valueData = updated[(__bridge NSString *)kSecValueData];

        const char *sql = "UPDATE items SET data = ?, attrs = ?, updated_at = CURRENT_TIMESTAMP WHERE service = ? AND account = ?";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;

        int rc = sqlite3_prepare_v2(gKeychainDB, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            blockError = [NSError errorWithDomain:SecItemLinuxStoreErrorDomain code:rc userInfo:nil];
            return;
        }

        if (valueData) {
            sqlite3_bind_blob(stmt, 1, [valueData bytes], (int)[valueData length], SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt, 1);
        }
        sqlite3_bind_blob(stmt, 2, [jsonData bytes], (int)[jsonData length], SQLITE_TRANSIENT);
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
    if (!service || !account) {
        return NO;
    }

    __block BOOL exists = NO;
    dispatch_sync(gKeychainQueue, ^{
        const char *sql = "SELECT 1 FROM items WHERE service = ? AND account = ? LIMIT 1";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;

        int rc = sqlite3_prepare_v2(gKeychainDB, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            return;
        }

        sqlite3_bind_text(stmt, 1, [service UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [account UTF8String], -1, SQLITE_TRANSIENT);

        rc = sqlite3_step(stmt);
        if (rc == SQLITE_ROW) {
            exists = YES;
        }
    });

    return exists;
}

@end
