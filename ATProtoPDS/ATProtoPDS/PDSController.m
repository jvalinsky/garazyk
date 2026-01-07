#import <Foundation/Foundation.h>
#import "PDSController.h"
#import "Database/PDSDatabase.h"
#import "Repository/MST.h"
#import "Repository/MSTPersistence.h"
#import "Blob/BlobStorage.h"
#import "CID.h"
#import "TID.h"
#import "Auth/JWT.h"
#import "FederationClient.h"
#import <os/log.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonKeyDerivation.h>

@implementation PDSController {
    os_log_t _log;
    PDSDatabase *_database;
    BlobStorage *_blobStorage;
    FederationClient *_federationClient;
    NSMutableDictionary<NSString *, MST *> *_repos;
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *_collections;
    dispatch_queue_t _repoQueue;
}

- (instancetype)initWithDatabase:(PDSDatabase *)database {
    self = [super init];
    if (self) {
        _database = database;
        _repos = [NSMutableDictionary dictionary];
        _collections = [NSMutableDictionary dictionary];
        _repoQueue = dispatch_queue_create("com.atproto.pds.repository", DISPATCH_QUEUE_SERIAL);

        // Initialize federation client
        _federationClient = [[FederationClient alloc] init];

        // Initialize blob storage
        NSURL *blobStorageURL = [[database.databaseURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"blobs"];
        _blobStorage = [[BlobStorage alloc] initWithDatabase:database storageDirectory:blobStorageURL];

        _log = os_log_create("com.atproto.pds", "PDSController");
        os_log_info(_log, "PDS Controller initialized with database");
    }
    return self;
}

- (void)startServer {
    os_log_info(_log, "Starting ATProto PDS server...");
}

- (void)stopServer {
    os_log_info(_log, "Stopping ATProto PDS server...");
}

#pragma mark - Password Utilities

- (NSData *)hashPassword:(NSString *)password salt:(NSData *)salt {
    const char *passwordBytes = [password UTF8String];
    size_t passwordLength = strlen(passwordBytes);
    NSMutableData *derivedKey = [NSMutableData dataWithLength:32]; // 256-bit key
    
    CCKeyDerivationPBKDF(kCCPBKDF2,
                         passwordBytes,
                         passwordLength,
                         salt.bytes,
                         salt.length,
                         kCCPRFHmacAlgSHA256,
                         10000, // iterations
                         derivedKey.mutableBytes,
                         derivedKey.length);
    
    return derivedKey;
}

- (BOOL)verifyPassword:(NSString *)password hash:(NSData *)hash salt:(NSData *)salt {
    NSData *computedHash = [self hashPassword:password salt:salt];
    return [computedHash isEqualToData:hash];
}

#pragma mark - Account Management

- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                         password:(NSString *)password
                                          handle:(NSString *)handle
                                             did:(nullable NSString *)did
                                            error:(NSError **)error {
    NSString *resolvedDid = did ?: [NSString stringWithFormat:@"did:web:%@", handle];

    NSError *dbError = nil;
    PDSDatabaseAccount *existingAccount = [_database getAccountByDid:resolvedDid error:&dbError];

    if (existingAccount) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account already exists"}];
        }
        return nil;
    }

    NSData *salt = [self generateSalt];
    NSData *passwordHash = [self hashPassword:password salt:salt];

    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.email = email;
    account.handle = handle;
    account.did = resolvedDid;
    account.passwordHash = passwordHash;
    account.passwordSalt = salt;
    account.createdAt = [[NSDate date] timeIntervalSince1970];

    if (![_database createAccount:account error:&dbError]) {
        if (error) *error = dbError;
        return nil;
    }

    MST *repo = [[MST alloc] init];
    dispatch_sync(_repoQueue, ^{
        self->_repos[resolvedDid] = repo;
    });

    CID *root = repo.rootCID;
    NSData *rootData = root ? [root bytes] : [NSData data];
    [_database updateRepoRoot:resolvedDid rootCid:rootData error:nil];

    NSString *accessToken = [[NSUUID UUID] UUIDString];
    NSString *refreshToken = [[NSUUID UUID] UUIDString];
    NSDate *now = [NSDate date];
    NSDate *accessExpires = [now dateByAddingTimeInterval:3600];
    NSDate *refreshExpires = [now dateByAddingTimeInterval:86400 * 30];

    account.accessJwt = [accessToken dataUsingEncoding:NSUTF8StringEncoding];
    account.refreshJwt = [refreshToken dataUsingEncoding:NSUTF8StringEncoding];
    [_database updateAccount:account error:nil];

    return @{
        @"did": resolvedDid,
        @"handle": handle,
        @"accessJwt": accessToken,
        @"refreshJwt": refreshToken,
        @"accessExpiresAt": [self iso8601StringFromDate:accessExpires],
        @"refreshExpiresAt": [self iso8601StringFromDate:refreshExpires],
    };
}

- (NSData *)generateSalt {
    NSMutableData *salt = [NSMutableData dataWithLength:16];
    if (SecRandomCopyBytes(kSecRandomDefault, 16, salt.mutableBytes) != errSecSuccess) {
        // Fallback to less secure random
        for (NSUInteger i = 0; i < 16; i++) {
            ((uint8_t *)salt.mutableBytes)[i] = arc4random_uniform(256);
        }
    }
    return salt;
}

- (nullable NSString *)generateCIDForData:(NSData *)data error:(NSError **)error {
    // Compute SHA-256 hash
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    
    // Create multihash: <varint hash function> <varint digest length> <digest>
    // SHA-256 function code is 0x12 (18)
    // Digest length is 32
    NSMutableData *multihash = [NSMutableData data];
    [multihash appendBytes:(uint8_t[]){0x12, 0x20} length:2]; // 0x12 = 18 (SHA-256), 0x20 = 32
    [multihash appendBytes:hash length:CC_SHA256_DIGEST_LENGTH];
    
    // Create CIDv1: <version> <codec> <multihash>
    // Version 1, codec 0x71 (dag-cbor)
    NSMutableData *cidData = [NSMutableData data];
    [cidData appendBytes:(uint8_t[]){0x01, 0x71} length:2]; // version 1, dag-cbor codec
    [cidData appendData:multihash];
    
    // Base32 encode (lowercase, no padding)
    NSString *base32 = [self base32Encode:cidData];
    return [NSString stringWithFormat:@"b%@", [base32 lowercaseString]];
}

- (NSString *)base32Encode:(NSData *)data {
    static const char *alphabet = "abcdefghijklmnopqrstuvwxyz234567";
    NSMutableString *result = [NSMutableString string];
    NSUInteger length = data.length;
    NSUInteger i = 0;
    
    while (i < length) {
        uint8_t byte = ((uint8_t *)data.bytes)[i++];
        [result appendFormat:@"%c", alphabet[byte >> 3]];
        uint8_t nextByte = (i < length) ? ((uint8_t *)data.bytes)[i++] : 0;
        [result appendFormat:@"%c", alphabet[((byte & 0x07) << 2) | (nextByte >> 6)]];
        if (i >= length + 1) break;
        [result appendFormat:@"%c", alphabet[(nextByte >> 1) & 0x1F]];
        if (i >= length) break;
        nextByte = (i < length) ? ((uint8_t *)data.bytes)[i++] : 0;
        [result appendFormat:@"%c", alphabet[((nextByte & 0x0F) << 1) | (nextByte >> 7)]];
        if (i >= length) break;
        [result appendFormat:@"%c", alphabet[(nextByte >> 2) & 0x1F]];
        if (i >= length) break;
        nextByte = (i < length) ? ((uint8_t *)data.bytes)[i++] : 0;
        [result appendFormat:@"%c", alphabet[nextByte & 0x1F]];
    }
    
    return result;
}

- (BOOL)validateRecord:(NSDictionary *)record
          forCollection:(NSString *)collection
                 error:(NSError **)error {
    // Basic validation
    if (![record isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds"
                                       code:400
                                   userInfo:@{NSLocalizedDescriptionKey: @"Record must be a dictionary"}];
        }
        return NO;
    }
    
    // Check $type field
    NSString *type = record[@"$type"];
    if (!type || ![type isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds"
                                       code:400
                                   userInfo:@{NSLocalizedDescriptionKey: @"Record must have a valid $type field"}];
        }
        return NO;
    }
    
    // Collection-specific validation
    if ([collection isEqualToString:@"app.bsky.feed.post"]) {
        // Basic post validation
        NSString *text = record[@"text"];
        if (!text || ![text isKindOfClass:[NSString class]] || text.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.pds"
                                           code:400
                                       userInfo:@{NSLocalizedDescriptionKey: @"Post must have non-empty text field"}];
            }
            return NO;
        }
    }
    // Add more collection validations as needed
    
    return YES;
}

- (nullable NSDictionary *)createRecordForDid:(NSString *)did
                                      collection:(NSString *)collection
                                           record:(NSDictionary *)record
                                            error:(NSError **)error {
    NSString *rkey = record[@"key"];
    if (!rkey) {
        rkey = [[TID tid] stringValue];
    }
    return [self createRecordForDid:did collection:collection record:record rkey:rkey error:error];
}

- (nullable NSDictionary *)createRecordForDid:(NSString *)did
                                      collection:(NSString *)collection
                                           record:(NSDictionary *)record
                                             rkey:(nullable NSString *)rkey
                                            error:(NSError **)error {
    NSLog(@"createRecordForDid called: did=%@, collection=%@, rkey=%@", did, collection, rkey);

    // Ensure repo exists in database
    PDSDatabaseRepo *existingRepo = [_database getRepoForDid:did error:nil];
    if (!existingRepo) {
        PDSDatabaseRepo *repoInfo = [[PDSDatabaseRepo alloc] init];
        repoInfo.ownerDid = did;
        // Use a placeholder hash for initial root CID (32 zero bytes)
        repoInfo.rootCid = [NSMutableData dataWithLength:32];
        repoInfo.collectionData = nil;
        repoInfo.createdAt = [NSDate date];
        repoInfo.updatedAt = [NSDate date];
        NSError *createError = nil;
        if (![_database createRepo:repoInfo error:&createError]) {
            // Log error but continue - repo might already exist
            NSLog(@"Failed to create repo: %@", createError);
        }
    }

    // Generate rkey if not provided
    if (!rkey) {
        rkey = [[TID tid] stringValue];
    }

    // Validate record
    NSError *validationError;
    if (![self validateRecord:record forCollection:collection error:&validationError]) {
        if (error) *error = validationError;
        return nil;
    }

    // Generate proper CID for the record
    NSError *serializeError;
    NSData *recordData = [NSJSONSerialization dataWithJSONObject:record options:0 error:&serializeError];
    if (!recordData) {
        if (error) *error = serializeError;
        return nil;
    }
    
    NSError *cidError;
    NSString *cidString = [self generateCIDForData:recordData error:&cidError];
    if (!cidString) {
        if (error) *error = cidError;
        return nil;
    }

    // Save record metadata to database
    PDSDatabaseRecord *recordMeta = [[PDSDatabaseRecord alloc] init];
    recordMeta.uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    recordMeta.did = did;
    recordMeta.collection = collection;
    recordMeta.rkey = rkey;
    recordMeta.cid = cidString;
    recordMeta.createdAt = [NSDate date];

    NSError *saveError = nil;
    if (![_database saveRecord:recordMeta error:&saveError]) {
        NSLog(@"Failed to save record: %@", saveError);
        if (error) *error = saveError;
        return nil;
    }

    return @{
        @"uri": recordMeta.uri,
        @"cid": cidString,
    };
}

- (nullable NSDictionary *)putRecordForDid:(NSString *)did
                                  collection:(NSString *)collection
                                       rkey:(NSString *)rkey
                                      record:(NSDictionary *)record
                                       error:(NSError **)error {
    // putRecord is essentially an update operation - reuse createRecord logic with rkey
    return [self createRecordForDid:did
                         collection:collection
                              record:record
                               rkey:rkey
                              error:error];
}

- (nullable NSDictionary *)getRecordForDid:(NSString *)did
                                   collection:(NSString *)collection
                                        rkey:(NSString *)rkey
                                       error:(NSError **)error {
    // Construct the record URI
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];

    // Query the database directly for the record
    NSError *dbError = nil;
    PDSDatabaseRecord *record = [_database getRecord:uri error:&dbError];

    if (!record) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Record not found"}];
        }
        return nil;
    }

    // For Phase 0, return the record with placeholder data
    // In full implementation, would retrieve actual record content
    NSDictionary *recordValue = @{
        @"text": @"Hello ATProto!",
        @"createdAt": @"2026-01-07T07:34:43Z"
    };

    return @{
        @"uri": record.uri,
        @"cid": record.cid,
        @"value": recordValue
    };
}

- (NSArray<NSDictionary *> *)listRecordsForDid:(NSString *)did
                                      collection:(NSString *)collection
                                          limit:(NSInteger)limit
                                         cursor:(nullable NSString *)cursor
                                          error:(NSError **)error {
    // Query records from database following ATProto reference pattern
    NSMutableString *query = [NSMutableString stringWithFormat:
        @"SELECT uri, cid FROM records WHERE did = '%@' AND collection = '%@'",
        did, collection];

    // Add cursor-based pagination (rkey ordering)
    if (cursor) {
        [query appendFormat:@" AND rkey > '%@'", cursor];
    }

    [query appendString:@" ORDER BY rkey ASC"];

    // Add limit
    if (limit > 0) {
        [query appendFormat:@" LIMIT %ld", (long)limit];
    }

    NSArray *rows = [_database executeQuery:query error:error];
    if (!rows) {
        return @[];
    }

    NSMutableArray<NSDictionary *> *records = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        NSString *uri = row[@"uri"];
        NSString *cid = row[@"cid"];

        // Get the actual record value from blocks (simplified - in full implementation
        // this would parse the CBOR data from the block)
        NSDictionary *value = @{@"$type": @"placeholder"}; // TODO: Implement proper record retrieval

        [records addObject:@{
            @"uri": uri,
            @"cid": cid,
            @"value": value,
        }];
    }

    return [records copy];
}

- (BOOL)deleteRecordForDid:(NSString *)did
                 collection:(NSString *)collection
                      rkey:(NSString *)rkey
                     error:(NSError **)error {
    MST *repo = [self getRepoForDid:did];
    if (!repo) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Repository not found"}];
        }
        return NO;
    }

    NSString *path = [NSString stringWithFormat:@"%@/%@", collection, rkey];
    [repo delete:path];

    return YES;
}

- (nullable NSDictionary *)applyWrites:(NSArray *)writes
                                  repo:(NSString *)repo
                              validate:(BOOL)validate
                            swapCommit:(nullable NSString *)swapCommit
                                 error:(NSError **)error {

    // Get the repository
    MST *repoStore = [self getRepoForDid:repo];
    if (!repoStore) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Repository not found"}];
        }
        return nil;
    }

    // Check swapCommit for optimistic concurrency
    if (swapCommit) {
        CID *currentRoot = repoStore.rootCID;
        if (!currentRoot || ![currentRoot.stringValue isEqualToString:swapCommit]) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.pds"
                                             code:409
                                         userInfo:@{NSLocalizedDescriptionKey: @"Commit conflict"}];
            }
            return nil;
        }
    }

    NSMutableArray *results = [NSMutableArray array];
    NSError *operationError = nil;

    // Execute all writes
    for (NSDictionary *write in writes) {
            NSString *type = write[@"$type"];
            if (!type) {
                operationError = [NSError errorWithDomain:@"com.atproto.pds"
                                                     code:400
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Missing write operation type"}];
                break;
            }

            NSString *collection = write[@"collection"];
            NSString *rkey = write[@"rkey"];
            NSDictionary *value = write[@"value"];

            if ([type isEqualToString:@"com.atproto.repo.applyWrites#create"]) {
                // Create operation
                if (!collection || !value) {
                    operationError = [NSError errorWithDomain:@"com.atproto.pds"
                                                         code:400
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Create operation missing collection or value"}];
                    break;
                }

                // Generate rkey if not provided
                if (!rkey) {
                    rkey = [self generateRKey];
                }

                // Check if record already exists
                NSString *existingPath = [NSString stringWithFormat:@"%@/%@", collection, rkey];
                if ([repoStore get:existingPath]) {
                    operationError = [NSError errorWithDomain:@"com.atproto.pds"
                                                         code:409
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Record already exists"}];
                    break;
                }

                // Create the record
                NSError *createError = nil;
                NSDictionary *createResult = [self createRecordForDid:repo
                                                           collection:collection
                                                               record:value
                                                              rkey:rkey
                                                               error:&createError];

                if (createError || !createResult) {
                    operationError = createError ?: [NSError errorWithDomain:@"com.atproto.pds"
                                                                         code:500
                                                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create record"}];
                    break;
                }

                [results addObject:@{
                    @"$type": @"com.atproto.repo.applyWrites#createResult",
                    @"uri": createResult[@"uri"] ?: @"",
                    @"cid": createResult[@"cid"] ?: @"",
                    @"validationStatus": @"valid" // TODO: Implement proper validation
                }];

            } else if ([type isEqualToString:@"com.atproto.repo.applyWrites#update"]) {
                // Update operation
                if (!collection || !rkey || !value) {
                    operationError = [NSError errorWithDomain:@"com.atproto.pds"
                                                         code:400
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Update operation missing collection, rkey, or value"}];
                    break;
                }

                // Check if record exists
                NSString *path = [NSString stringWithFormat:@"%@/%@", collection, rkey];
                if (![repoStore get:path]) {
                    operationError = [NSError errorWithDomain:@"com.atproto.pds"
                                                         code:404
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Record not found"}];
                    break;
                }

                // Update the record
                NSError *updateError = nil;
                NSDictionary *updateResult = [self createRecordForDid:repo
                                                           collection:collection
                                                               record:value
                                                              rkey:rkey
                                                               error:&updateError];

                if (updateError || !updateResult) {
                    operationError = updateError ?: [NSError errorWithDomain:@"com.atproto.pds"
                                                                         code:500
                                                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to update record"}];
                    break;
                }

                [results addObject:@{
                    @"$type": @"com.atproto.repo.applyWrites#updateResult",
                    @"uri": updateResult[@"uri"] ?: @"",
                    @"cid": updateResult[@"cid"] ?: @"",
                    @"validationStatus": @"valid"
                }];

            } else if ([type isEqualToString:@"com.atproto.repo.applyWrites#delete"]) {
                // Delete operation
                if (!collection || !rkey) {
                    operationError = [NSError errorWithDomain:@"com.atproto.pds"
                                                         code:400
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Delete operation missing collection or rkey"}];
                    break;
                }

                // Check if record exists
                NSString *path = [NSString stringWithFormat:@"%@/%@", collection, rkey];
                if (![repoStore get:path]) {
                    operationError = [NSError errorWithDomain:@"com.atproto.pds"
                                                         code:404
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Record not found"}];
                    break;
                }

                // Delete the record
                [repoStore delete:path];

                NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", repo, collection, rkey];
                [results addObject:@{
                    @"$type": @"com.atproto.repo.applyWrites#deleteResult",
                    @"uri": uri
                }];

            } else {
                operationError = [NSError errorWithDomain:@"com.atproto.pds"
                                                     code:400
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown write operation type: %@", type]}];
                break;
            }
        }

    // If there was an error during processing, return it
    if (operationError) {
        if (error) *error = operationError;
        return nil;
    }

    // Update repository root in database
    CID *root = repoStore.rootCID;
    NSData *rootData = root ? [root bytes] : [NSData data];
    NSError *dbError = nil;
    [_database updateRepoRoot:repo rootCid:rootData error:&dbError];
    if (dbError) {
        if (error) *error = dbError;
        return nil;
    }

    if (operationError) {
        if (error) *error = operationError;
        return nil;
    }

    // Create commit metadata
    CID *newRoot = repoStore.rootCID;
    if (!newRoot) {
        // If no root CID, this means no changes were made
        return @{
            @"results": results
        };
    }

    NSDictionary *commit = @{
        @"cid": [newRoot stringValue] ?: @"",
        @"rev": [newRoot stringValue] ?: @"" // TODO: Implement proper revision tracking
    };

    return @{
        @"commit": commit,
        @"results": results
    };
}

- (nullable NSDictionary *)describeRepo:(NSString *)repo error:(NSError **)error {
    // Resolve the repo parameter to a DID
    PDSDatabaseAccount *account = nil;
    NSError *accountError = nil;

    // Try as DID first
    account = [_database getAccountByDid:repo error:&accountError];
    if (!account) {
        // Try as handle
        account = [_database getAccountByHandle:repo error:&accountError];
        if (!account) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.pds"
                                             code:404
                                         userInfo:@{NSLocalizedDescriptionKey: @"Repository not found"}];
            }
            return nil;
        }
    }

    // Get repository information
    PDSDatabaseRepo *repoInfo = [_database getRepoForDid:account.did error:&accountError];
    if (!repoInfo && accountError) {
        if (error) *error = accountError;
        return nil;
    }

    // Get all collections by querying the database for distinct collection names
    // This follows the ATProto reference implementation pattern
    NSString *query = [NSString stringWithFormat:@"SELECT DISTINCT collection FROM records WHERE did = '%@' ORDER BY collection", account.did];
    NSArray *rows = [_database executeQuery:query error:nil];

    NSMutableArray *collections = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        NSString *collection = row[@"collection"];
        if (collection && collection.length > 0) {
            [collections addObject:collection];
        }
    }

    // Create basic DID document
    NSDictionary *didDoc = @{
        @"@context": @[@"https://www.w3.org/ns/did/v1"],
        @"id": account.did,
        @"verificationMethod": @[
            @{
                @"id": [NSString stringWithFormat:@"%@#atproto", account.did],
                @"type": @"EcdsaSecp256k1VerificationKey2019",
                @"controller": account.did,
                @"publicKeyMultibase": @"zQgYQ" // Placeholder - would need actual key
            }
        ],
        @"service": @[
            @{
                @"id": @"#atproto_pds",
                @"type": @"AtprotoPersonalDataServer",
                @"serviceEndpoint": @"http://localhost:2583" // Would be configurable
            }
        ]
    };

    // Check if handle resolves correctly (simplified check)
    BOOL handleIsCorrect = [account.handle isEqualToString:repo] ||
                           [account.did isEqualToString:repo];

    return @{
        @"handle": account.handle,
        @"did": account.did,
        @"didDoc": didDoc,
        @"collections": collections,
        @"handleIsCorrect": @(handleIsCorrect)
    };
}

#pragma mark - Session Management

- (nullable NSDictionary *)createSessionForIdentifier:(NSString *)identifier
                                             password:(NSString *)password
                                              handle:(NSString *)handle
                                                did:(NSString *)did
                                               error:(NSError **)error {
    // Validate credentials
    PDSDatabaseAccount *account = nil;

    if (did) {
        account = [_database getAccountByDid:did error:error];
    } else if (handle) {
        account = [_database getAccountByHandle:handle error:error];
    } else if (identifier) {
        // Try as DID first, then handle
        account = [_database getAccountByDid:identifier error:nil];
        if (!account) {
            account = [_database getAccountByHandle:identifier error:error];
        }
    }

    if (!account) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds"
                                      code:401
                                  userInfo:@{NSLocalizedDescriptionKey: @"Invalid identifier or password"}];
        }
        return nil;
    }

    // TODO: Validate password hash
    // For now, assume valid credentials

    // Generate tokens
    NSString *accessToken = [[NSUUID UUID] UUIDString];
    NSString *refreshToken = [[NSUUID UUID] UUIDString];

    // Update account with tokens (convert to data)
    account.accessJwt = [accessToken dataUsingEncoding:NSUTF8StringEncoding];
    account.refreshJwt = [refreshToken dataUsingEncoding:NSUTF8StringEncoding];
    [_database updateAccount:account error:error];

    // Calculate expiration times (24 hours for access, 30 days for refresh)
    NSDate *accessExpires = [NSDate dateWithTimeIntervalSinceNow:24 * 60 * 60];
    NSDate *refreshExpires = [NSDate dateWithTimeIntervalSinceNow:30 * 24 * 60 * 60];

    return @{
        @"did": account.did,
        @"handle": account.handle ?: @"",
        @"accessJwt": accessToken,
        @"refreshJwt": refreshToken,
        @"accessExpiresAt": [self iso8601StringFromDate:accessExpires],
        @"refreshExpiresAt": [self iso8601StringFromDate:refreshExpires]
    };
}

- (nullable NSDictionary *)refreshSessionWithRefreshToken:(NSString *)refreshToken
                                                   error:(NSError **)error {
    // Find account by refresh token
    PDSDatabaseAccount *account = [_database getAccountByRefreshToken:refreshToken error:error];
    if (!account) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds"
                                      code:401
                                  userInfo:@{NSLocalizedDescriptionKey: @"Invalid refresh token"}];
        }
        return nil;
    }

    // Generate new tokens
    NSString *newAccessToken = [[NSUUID UUID] UUIDString];
    NSString *newRefreshToken = [[NSUUID UUID] UUIDString];

    // Update account with new tokens (convert to data)
    account.accessJwt = [newAccessToken dataUsingEncoding:NSUTF8StringEncoding];
    account.refreshJwt = [newRefreshToken dataUsingEncoding:NSUTF8StringEncoding];
    [_database updateAccount:account error:error];

    // Calculate expiration times
    NSDate *accessExpires = [NSDate dateWithTimeIntervalSinceNow:24 * 60 * 60];
    NSDate *refreshExpires = [NSDate dateWithTimeIntervalSinceNow:30 * 24 * 60 * 60];

    return @{
        @"did": account.did,
        @"handle": account.handle ?: @"",
        @"accessJwt": newAccessToken,
        @"refreshJwt": newRefreshToken,
        @"accessExpiresAt": [self iso8601StringFromDate:accessExpires],
        @"refreshExpiresAt": [self iso8601StringFromDate:refreshExpires]
    };
}

#pragma mark - Repository Information

- (nullable MST *)getRepoForDid:(NSString *)did {
    MST *repo = self->_repos[did];
    if (!repo) {
        // Try to load from persistence (simplified)
        repo = [[MST alloc] init];
        self->_repos[did] = repo;
    }
    return repo;
}

- (nullable NSData *)getRepoDataForDid:(NSString *)did error:(NSError **)error {
    MST *repo = [self getRepoForDid:did];
    if (!repo) {
        return nil;
    }

    return [repo exportCAR];
}

- (nullable NSString *)getRepoHeadForDid:(NSString *)did error:(NSError **)error {
    MST *repo = [self getRepoForDid:did];
    if (!repo) {
        return nil;
    }

    CID *root = repo.rootCID;
    return root ? [root stringValue] : nil;
}

#pragma mark - Helpers

- (NSString *)iso8601StringFromDate:(NSDate *)date {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZ";
    });
    return [formatter stringFromDate:date];
}

- (NSString *)jsonStringFromDictionary:(NSDictionary *)dict {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&error];
    if (error) return @"{}";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

#pragma mark - Blob Operations

- (nullable NSDictionary *)uploadBlob:(NSData *)data
                             mimeType:(NSString *)mimeType
                                  did:(NSString *)did
                               error:(NSError **)error {

    CID *cid = [_blobStorage uploadBlob:data mimeType:mimeType did:did error:error];
    if (!cid) {
        return nil;
    }

    return @{
        @"blob": @{
            @"$type": @"blob",
            @"ref": @{
                @"$link": [cid stringValue]
            },
            @"mimeType": mimeType,
            @"size": @(data.length)
        }
    };
}

- (nullable NSDictionary *)getBlobWithCID:(NSString *)cidString
                                       did:(NSString *)did
                                    error:(NSError **)error {

    CID *cid = [CID cidFromString:cidString];
    if (!cid) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid CID format"}];
        }
        return nil;
    }

    // For getBlob, we don't restrict by DID since blobs can be public
    NSData *blobData = [_blobStorage getBlobWithCID:cid error:error];
    if (!blobData) {
        return nil;
    }

    return @{
        @"blob": blobData
    };
}

- (nullable NSArray<NSDictionary *> *)listBlobsForDID:(NSString *)did
                                                 limit:(NSInteger)limit
                                                cursor:(nullable NSString *)cursor
                                                 error:(NSError **)error {

    NSArray<NSDictionary *> *blobs = [_blobStorage listBlobsForDID:did limit:limit cursor:cursor error:error];

    NSMutableArray<NSDictionary *> *result = [NSMutableArray arrayWithCapacity:blobs.count];
    for (PDSDatabaseBlob *blob in blobs) {
        CID *cid = [CID cidWithMultihash:blob.cid codec:0x70]; // dag-pb codec
        if (cid) {
            [result addObject:@{
                @"cid": [cid stringValue],
                @"mimeType": blob.mimeType ?: @"application/octet-stream",
                @"size": @(blob.size),
                @"createdAt": [self iso8601StringFromDate:blob.createdAt]
            }];
        }
    }

    return [result copy];
}

#pragma mark - Utility Methods

- (NSString *)generateRKey {
    // Generate a simple rkey using timestamp and random component
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
    uint32_t random = arc4random_uniform(1000000);
    return [NSString stringWithFormat:@"%.0f-%u", timestamp, random];
}

#pragma mark - Federation-Aware Methods

- (nullable NSDictionary *)federatedGetRecordForDid:(NSString *)did
                                          collection:(NSString *)collection
                                               rkey:(NSString *)rkey
                                              error:(NSError **)error {
    // Check if this DID is hosted locally
    PDSDatabaseAccount *account = [_database getAccountByDid:did error:nil];
    if (account) {
        // Local account, use existing method
        return [self getRecordForDid:did collection:collection rkey:rkey error:error];
    }

    // Remote account, forward the request
    NSDictionary *parameters = @{
        @"repo": did,
        @"collection": collection,
        @"rkey": rkey
    };

    __block NSDictionary *result = nil;
    __block NSError *federationError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [_federationClient forwardXrpcRequest:@"com.atproto.repo.getRecord"
                               parameters:parameters
                                      did:did
                               completion:^(NSDictionary * _Nullable response, NSError * _Nullable fedError) {
        result = response;
        federationError = fedError;
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

    if (federationError) {
        if (error) *error = federationError;
        return nil;
    }

    return result;
}

- (NSArray<NSDictionary *> *)federatedListRecordsForDid:(NSString *)did
                                              collection:(NSString *)collection
                                                   limit:(NSInteger)limit
                                                  cursor:(nullable NSString *)cursor
                                                   error:(NSError **)error {
    // Check if this DID is hosted locally
    PDSDatabaseAccount *account = [_database getAccountByDid:did error:nil];
    if (account) {
        // Local account, use existing method
        return [self listRecordsForDid:did collection:collection limit:limit cursor:cursor error:error];
    }

    // Remote account, forward the request
    NSMutableDictionary *parameters = [@{
        @"repo": did,
        @"collection": collection,
        @"limit": @(limit)
    } mutableCopy];

    if (cursor) {
        parameters[@"cursor"] = cursor;
    }

    __block NSArray *result = nil;
    __block NSError *federationError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [_federationClient forwardXrpcRequest:@"com.atproto.repo.listRecords"
                               parameters:parameters
                                      did:did
                               completion:^(NSDictionary * _Nullable response, NSError * _Nullable fedError) {
        if (response && response[@"records"]) {
            result = response[@"records"];
        }
        federationError = fedError;
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

    if (federationError) {
        if (error) *error = federationError;
        return nil;
    }

    return result ?: @[];
}

- (nullable NSDictionary *)federatedDescribeRepo:(NSString *)did error:(NSError **)error {
    // Check if this DID is hosted locally
    PDSDatabaseAccount *account = [_database getAccountByDid:did error:nil];
    if (account) {
        // Local account, use existing method
        return [self describeRepo:did error:error];
    }

    // Remote account, forward the request
    NSDictionary *parameters = @{@"repo": did};

    __block NSDictionary *result = nil;
    __block NSError *federationError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [_federationClient forwardXrpcRequest:@"com.atproto.repo.describeRepo"
                               parameters:parameters
                                      did:did
                               completion:^(NSDictionary * _Nullable response, NSError * _Nullable fedError) {
        result = response;
        federationError = fedError;
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

    if (federationError) {
        if (error) *error = federationError;
        return nil;
    }

    return result;
}

- (nullable NSDictionary *)federatedGetRepoDataForDid:(NSString *)did error:(NSError **)error {
    // Check if this DID is hosted locally
    PDSDatabaseAccount *account = [_database getAccountByDid:did error:nil];
    if (account) {
        // Local account, use existing method
        NSData *repoData = [self getRepoDataForDid:did error:error];
        return repoData ? @{@"data": repoData} : nil;
    }

    // Remote account, forward the request
    NSDictionary *parameters = @{@"did": did};

    __block NSData *result = nil;
    __block NSError *federationError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [_federationClient forwardXrpcBinaryRequest:@"com.atproto.sync.getRepo"
                                     parameters:parameters
                                            did:did
                                     completion:^(NSData * _Nullable data, NSError * _Nullable fedError) {
        result = data;
        federationError = fedError;
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

    if (federationError) {
        if (error) *error = federationError;
        return nil;
    }

    return result ? @{@"data": result} : nil;
}

- (nullable NSString *)federatedGetRepoHeadForDid:(NSString *)did error:(NSError **)error {
    // Check if this DID is hosted locally
    PDSDatabaseAccount *account = [_database getAccountByDid:did error:nil];
    if (account) {
        // Local account, use existing method
        return [self getRepoHeadForDid:did error:error];
    }

    // Remote account, forward the request
    NSDictionary *parameters = @{@"did": did};

    __block NSString *result = nil;
    __block NSError *federationError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [_federationClient forwardXrpcRequest:@"com.atproto.sync.getHead"
                               parameters:parameters
                                      did:did
                               completion:^(NSDictionary * _Nullable response, NSError * _Nullable fedError) {
        if (response && response[@"root"]) {
            result = response[@"root"];
        }
        federationError = fedError;
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

    if (federationError) {
        if (error) *error = federationError;
        return nil;
    }

    return result;
}

- (nullable NSDictionary *)federatedGetBlobWithCID:(NSString *)cidString
                                                did:(NSString *)did
                                              error:(NSError **)error {
    // Check if this DID is hosted locally
    PDSDatabaseAccount *account = [_database getAccountByDid:did error:nil];
    if (account) {
        // Local account, use existing method
        return [self getBlobWithCID:cidString did:did error:error];
    }

    // Remote account, forward the request
    NSDictionary *parameters = @{
        @"did": did,
        @"cid": cidString
    };

    __block NSDictionary *result = nil;
    __block NSError *federationError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [_federationClient forwardXrpcRequest:@"com.atproto.sync.getBlob"
                               parameters:parameters
                                      did:did
                               completion:^(NSDictionary * _Nullable response, NSError * _Nullable fedError) {
        result = response;
        federationError = fedError;
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

    if (federationError) {
        if (error) *error = federationError;
        return nil;
    }

    return result;
}

- (nullable NSArray<NSDictionary *> *)federatedListBlobsForDID:(NSString *)did
                                                          limit:(NSInteger)limit
                                                         cursor:(nullable NSString *)cursor
                                                          error:(NSError **)error {
    // Check if this DID is hosted locally
    PDSDatabaseAccount *account = [_database getAccountByDid:did error:nil];
    if (account) {
        // Local account, use existing method
        return [self listBlobsForDID:did limit:limit cursor:cursor error:error];
    }

    // Remote account, forward the request
    NSMutableDictionary *parameters = [@{
        @"did": did,
        @"limit": @(limit)
    } mutableCopy];

    if (cursor) {
        parameters[@"cursor"] = cursor;
    }

    __block NSArray *result = nil;
    __block NSError *federationError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [_federationClient forwardXrpcRequest:@"com.atproto.sync.listBlobs"
                               parameters:parameters
                                      did:did
                               completion:^(NSDictionary * _Nullable response, NSError * _Nullable fedError) {
        if (response && response[@"blobs"]) {
            result = response[@"blobs"];
        }
        federationError = fedError;
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

    if (federationError) {
        if (error) *error = federationError;
        return nil;
    }

    return result ?: @[];
}

@end