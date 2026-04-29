#import "TutorialIdentityService.h"
#import "TutorialSQLiteHelper.h"

NSString * const TutorialIdentityErrorDomain = @"com.atproto.tutorial.identity";

@implementation TutorialDIDDocument
@end

@interface TutorialIdentityService ()
@property (nonatomic, strong) TutorialSQLiteHelper *db;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation TutorialIdentityService

- (instancetype)initWithCacheDirectory:(NSString *)cacheDir {
    self = [super init];
    if (!self) return nil;

    _cacheTTL = 300; // 5 minutes
    _queue = dispatch_queue_create("com.atproto.tutorial.identity", DISPATCH_QUEUE_SERIAL);

    // Create cache directory
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:cacheDir withIntermediateDirectories:YES attributes:nil error:nil];

    // Open cache database
    NSString *dbPath = [cacheDir stringByAppendingPathComponent:@"identity.db"];
    _db = [[TutorialSQLiteHelper alloc] initWithPath:dbPath];
    if (!_db) return nil;

    [self createTablesIfNeeded];

    // Setup URL session for network lookups
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 10;
    config.timeoutIntervalForResource = 30;
    _session = [NSURLSession sessionWithConfiguration:config];

    return self;
}

- (void)createTablesIfNeeded {
    NSError *error = nil;
    [self.db executeUpdate:&error sql:@"CREATE TABLE IF NOT EXISTS did_cache ("
        @"did TEXT PRIMARY KEY, "
        @"handle TEXT, "
        @"doc_json TEXT, "
        @"cached_at REAL NOT NULL"
        @")"];
    [self.db executeUpdate:&error sql:@"CREATE TABLE IF NOT EXISTS handle_cache ("
        @"handle TEXT PRIMARY KEY, "
        @"did TEXT NOT NULL, "
        @"cached_at REAL NOT NULL"
        @")"];
}

- (nullable TutorialDIDDocument *)resolveDID:(NSString *)did
                                        error:(NSError **)error {
    // Check cache first
    TutorialDIDDocument *cached = [self cachedDIDDocument:did];
    if (cached && ([[NSDate date] timeIntervalSince1970] - cached.cachedAt) < self.cacheTTL) {
        return cached;
    }

    // Resolve based on DID method
    if ([did hasPrefix:@"did:web:"]) {
        return [self resolveDIDWeb:did error:error];
    } else if ([did hasPrefix:@"did:plc:"]) {
        return [self resolveDIDPlc:did error:error];
    } else {
        if (error) {
            *error = [NSError errorWithDomain:TutorialIdentityErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported DID method"}];
        }
        return nil;
    }
}

- (nullable NSString *)resolveHandle:(NSString *)handle
                               error:(NSError **)error {
    // Check cache first
    NSString *cachedDid = [self cachedDIDForHandle:handle];
    if (cachedDid) {
        NSTimeInterval cachedAt = [self cachedAtForHandle:handle];
        if ([[NSDate date] timeIntervalSince1970] - cachedAt < self.cacheTTL) {
            return cachedDid;
        }
    }

    // Try HTTPS well-known first
    NSString *did = [self resolveHandleViaWellKnown:handle error:nil];

    // Fallback: DNS TXT (simulated — real DNS lookup requires platform-specific code)
    if (!did) {
        did = [self resolveHandleViaDNS:handle error:nil];
    }

    if (!did && error) {
        *error = [NSError errorWithDomain:TutorialIdentityErrorDomain
                                     code:2
                                 userInfo:@{NSLocalizedDescriptionKey: @"Handle resolution failed"}];
    }

    // Cache result
    if (did) {
        [self cacheHandle:handle did:did];
    }

    return did;
}

- (BOOL)verifyHandle:(NSString *)handle
              forDID:(NSString *)did
               error:(NSError **)error {
    // 1. Resolve handle → DID
    NSString *resolvedDID = [self resolveHandle:handle error:error];
    if (!resolvedDID) return NO;

    // 2. Check DID matches
    if (![resolvedDID isEqualToString:did]) {
        if (error) {
            *error = [NSError errorWithDomain:TutorialIdentityErrorDomain
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"Handle resolves to %@, expected %@", resolvedDID, did]}];
        }
        return NO;
    }

    // 3. Resolve DID → handle
    TutorialDIDDocument *doc = [self resolveDID:did error:error];
    if (!doc) return NO;

    // 4. Check DID also claims the handle (bidirectional verification)
    if (![doc.handle isEqualToString:handle]) {
        if (error) {
            *error = [NSError errorWithDomain:TutorialIdentityErrorDomain
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID document does not claim this handle"}];
        }
        return NO;
    }

    return YES;
}

- (void)clearCache {
    [self.db executeUpdate:nil sql:@"DELETE FROM did_cache"];
    [self.db executeUpdate:nil sql:@"DELETE FROM handle_cache"];
}

#pragma mark - DID Resolution

- (nullable TutorialDIDDocument *)resolveDIDWeb:(NSString *)did error:(NSError **)error {
    // did:web:example.com → https://example.com/.well-known/did.json
    // did:web:localhost:2583 → https://localhost:2583/.well-known/did.json
    NSString *domain = [did substringFromIndex:@"did:web:".length];
    domain = [domain stringByReplacingOccurrencesOfString:@":" withString:@"/"];

    NSString *urlStr = [NSString stringWithFormat:@"https://%@/.well-known/did.json", domain];

    // For tutorial: try to fetch, but allow mock responses for localhost
    TutorialDIDDocument *doc = nil;

    if ([domain hasPrefix:@"localhost"] || [domain hasPrefix:@"127.0.0.1"]) {
        // Mock response for local development
        doc = [self mockDIDDocumentForDID:did handle:@"localhost"];
    } else {
        // Real HTTP fetch
        doc = [self fetchDIDDocumentFromURL:urlStr did:did error:error];
    }

    if (doc) {
        [self cacheDIDDocument:doc];
    }

    return doc;
}

- (nullable TutorialDIDDocument *)resolveDIDPlc:(NSString *)did error:(NSError **)error {
    // did:plc:xxx → https://plc.directory/did:plc:xxx
    NSString *urlStr = [NSString stringWithFormat:@"https://plc.directory/%@", did];

    TutorialDIDDocument *doc = [self fetchDIDDocumentFromURL:urlStr did:did error:error];
    if (doc) {
        [self cacheDIDDocument:doc];
    }
    return doc;
}

- (nullable TutorialDIDDocument *)fetchDIDDocumentFromURL:(NSString *)urlStr
                                                      did:(NSString *)did
                                                    error:(NSError **)error {
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:TutorialIdentityErrorDomain
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}];
        }
        return nil;
    }

    // Synchronous fetch with semaphore
    __block NSDictionary *json = nil;
    __block NSError *fetchError = nil;

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *err) {
        if (!err && data) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode == 200) {
                json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            }
        }
        fetchError = err;
        dispatch_semaphore_signal(sem);
    }] resume];

    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC));

    if (!json) {
        if (error) {
            *error = fetchError ?: [NSError errorWithDomain:TutorialIdentityErrorDomain
                                                      code:6
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Failed to fetch DID document"}];
        }
        return nil;
    }

    TutorialDIDDocument *doc = [[TutorialDIDDocument alloc] init];
    doc.did = did;
    doc.handle = json[@"alsoKnownAs"] ? json[@"alsoKnownAs"][0] : nil;
    doc.verificationMethods = json[@"verificationMethod"] ?: @[];
    doc.services = json[@"service"] ?: @[];
    doc.cachedAt = [[NSDate date] timeIntervalSince1970];
    return doc;
}

#pragma mark - Handle Resolution

- (nullable NSString *)resolveHandleViaWellKnown:(NSString *)handle error:(NSError **)error {
    NSString *urlStr = [NSString stringWithFormat:@"https://%@/.well-known/atproto-did", handle];

    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return nil;

    __block NSString *did = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *err) {
        if (!err && data) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode == 200) {
                NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                body = [body stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if ([body hasPrefix:@"did:"]) {
                    did = body;
                }
            }
        }
        dispatch_semaphore_signal(sem);
    }] resume];

    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    return did;
}

- (nullable NSString *)resolveHandleViaDNS:(NSString *)handle error:(NSError **)error {
    // DNS TXT lookup for _atproto.handle
    // In production, use platform-specific DNS resolution (e.g., res_nquery on macOS)
    // For this tutorial, we simulate it
    NSLog(@"[Identity] DNS TXT lookup for _atproto.%@ (simulated)", handle);
    return nil;
}

#pragma mark - Mock

- (TutorialDIDDocument *)mockDIDDocumentForDID:(NSString *)did handle:(NSString *)handle {
    TutorialDIDDocument *doc = [[TutorialDIDDocument alloc] init];
    doc.did = did;
    doc.handle = [NSString stringWithFormat:@"handle.%@", handle];
    doc.verificationMethods = @[@{
        @"id": [NSString stringWithFormat:@"%@#atproto", did],
        @"type": @"Multikey",
        @"publicKeyMultibase": @"zQ3sh..."
    }];
    doc.services = @[@{
        @"id": [NSString stringWithFormat:@"%@#atproto_pds", did],
        @"type": @"AtprotoPersonalDataServer",
        @"serviceEndpoint": [NSString stringWithFormat:@"https://%@:2583", handle]
    }];
    doc.cachedAt = [[NSDate date] timeIntervalSince1970];
    return doc;
}

#pragma mark - Cache

- (nullable TutorialDIDDocument *)cachedDIDDocument:(NSString *)did {
    return [self.db executeQuery:nil block:^id(sqlite3 *db) {
        const char *sql = "SELECT handle, doc_json, cached_at FROM did_cache WHERE did = ?";
        sqlite3_stmt *stmt;
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return nil;
        sqlite3_bind_text(stmt, 1, [did UTF8String], -1, SQLITE_TRANSIENT);

        TutorialDIDDocument *doc = nil;
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            doc = [[TutorialDIDDocument alloc] init];
            doc.did = did;
            const char *handle = (const char *)sqlite3_column_text(stmt, 0);
            doc.handle = handle ? [NSString stringWithUTF8String:handle] : nil;
            const char *docJson = (const char *)sqlite3_column_text(stmt, 1);
            if (docJson) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:
                    [[NSString stringWithUTF8String:docJson] dataUsingEncoding:NSUTF8StringEncoding]
                    options:0 error:nil];
                doc.verificationMethods = json[@"verificationMethod"] ?: @[];
                doc.services = json[@"service"] ?: @[];
            }
            doc.cachedAt = sqlite3_column_double(stmt, 2);
        }
        sqlite3_finalize(stmt);
        return doc;
    }];
}

- (void)cacheDIDDocument:(TutorialDIDDocument *)doc {
    [self.db executeSync:nil block:^(sqlite3 *db) {
        NSDictionary *docDict = @{
            @"verificationMethod": doc.verificationMethods ?: @[],
            @"service": doc.services ?: @[]
        };
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:docDict options:0 error:nil];
        NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

        const char *sql = "INSERT OR REPLACE INTO did_cache (did, handle, doc_json, cached_at) VALUES (?, ?, ?, ?)";
        sqlite3_stmt *stmt;
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return;

        sqlite3_bind_text(stmt, 1, [doc.did UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [doc.handle UTF8String] ?: "", -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, [jsonStr UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 4, doc.cachedAt);

        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }];
}

- (nullable NSString *)cachedDIDForHandle:(NSString *)handle {
    return [self.db executeQuery:nil block:^id(sqlite3 *db) {
        const char *sql = "SELECT did FROM handle_cache WHERE handle = ?";
        sqlite3_stmt *stmt;
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return nil;
        sqlite3_bind_text(stmt, 1, [handle UTF8String], -1, SQLITE_TRANSIENT);

        NSString *did = nil;
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            did = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
        }
        sqlite3_finalize(stmt);
        return did;
    }];
}

- (NSTimeInterval)cachedAtForHandle:(NSString *)handle {
    return [[self.db executeQuery:nil block:^id(sqlite3 *db) {
        const char *sql = "SELECT cached_at FROM handle_cache WHERE handle = ?";
        sqlite3_stmt *stmt;
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return @(0);
        sqlite3_bind_text(stmt, 1, [handle UTF8String], -1, SQLITE_TRANSIENT);

        NSNumber *result = @(0);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            result = @(sqlite3_column_double(stmt, 0));
        }
        sqlite3_finalize(stmt);
        return result;
    }] doubleValue];
}

- (void)cacheHandle:(NSString *)handle did:(NSString *)did {
    [self.db executeSync:nil block:^(sqlite3 *db) {
        const char *sql = "INSERT OR REPLACE INTO handle_cache (handle, did, cached_at) VALUES (?, ?, ?)";
        sqlite3_stmt *stmt;
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return;

        sqlite3_bind_text(stmt, 1, [handle UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [did UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 3, [[NSDate date] timeIntervalSince1970]);

        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }];
}

@end
