#import "CLI/PDSCLIAccountManager.h"
#import <CommonCrypto/CommonKeyDerivation.h>
#import "PDSCLIDefinitions.h"
#import "Debug/PDSLogger.h"
#import "PDSCLIInputHelper.h"
#import "Database/PDSDatabase.h"
#import "Database/Schema.h"
#import "App/PDSConfiguration.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"
#import "PLC/PLCOperation.h"
#import "PLC/DIDPLCResolver.h"
#import "PLC/PLCRotationKeyManager.h"
#import <CommonCrypto/CommonDigest.h>
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"

#ifndef kCCSuccess
#define kCCSuccess 0
#endif

@implementation PDSCLIAccountManager

+ (NSString *)dataDirForContext:(PDSCLICommandContext *)context {
    NSDictionary *config = [context loadConfig];
    NSString *dataDir = config[@"server"][@"data_dir"] ?: [PDSConfiguration defaultDataDirectory];
    
    // Command line flag should override config file
    if (context.dataDir && ![context.dataDir isEqualToString:[PDSConfiguration defaultDataDirectory]] && ![context.dataDir isEqualToString:@"./data"]) {
        dataDir = context.dataDir;
    }
    return dataDir;
}

+ (NSString *)databasePathForContext:(PDSCLICommandContext *)context {
    NSString *dataDir = [self dataDirForContext:context];
    return [[dataDir stringByAppendingPathComponent:@"service"] stringByAppendingPathComponent:@"service.db"];
}

+ (NSString *)pdsHostnameForContext:(PDSCLICommandContext *)context {
    NSDictionary *config = [context loadConfig];
    // Prefer issuer for determining the public hostname
    NSString *issuer = config[@"issuer"] ?: config[@"server"][@"issuer"];
    if (issuer.length > 0) {
        NSURLComponents *c = [NSURLComponents componentsWithString:issuer];
        if (c.host.length > 0) {
            return c.host;
        }
    }
    NSString *host = config[@"server"][@"host"];
    if (!host || host.length == 0) {
        host = @"localhost";
    }
    if ([host isEqualToString:@"0.0.0.0"]) {
        host = @"localhost";
    }
    return host;
}

+ (NSString *)pdsServiceEndpointForContext:(PDSCLICommandContext *)context {
    NSDictionary *config = [context loadConfig];
    NSString *issuer = config[@"issuer"] ?: config[@"server"][@"issuer"];
    if (issuer.length > 0) {
        return issuer;
    }
    NSString *host = [self pdsHostnameForContext:context];
    return [NSString stringWithFormat:@"http://%@", host];
}

+ (NSArray<PDSDatabaseAccount *> *)listAccountsWithContext:(PDSCLICommandContext *)context
                                                    filter:(NSString *)filter
                                                    limit:(NSInteger)limit {
    NSString *dbPath = [self databasePathForContext:context];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
        if (context.verbose) {
            PDS_LOG_WARN(@"Database not found at %@", dbPath);
        }
        return @[];
    }

    NSError *error = nil;
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:&error]) {
        if (context.verbose) {
            PDS_LOG_ERROR(@"Failed to open database: %@", error.localizedDescription);
        }
        return @[];
    }

    NSArray<PDSDatabaseAccount *> *allAccounts = [db getAllAccountsWithError:&error];
    [db close];

    if (error) {
        if (context.verbose) {
            PDS_LOG_ERROR(@"Failed to query accounts: %@", error.localizedDescription);
        }
        return @[];
    }

    if (filter.length == 0 && limit <= 0) {
        return allAccounts;
    }

    NSMutableArray<PDSDatabaseAccount *> *filtered = [NSMutableArray array];
    for (PDSDatabaseAccount *account in allAccounts) {
        if (filter.length > 0) {
            if (![account.handle containsString:filter] &&
                ![account.email containsString:filter] &&
                ![account.did containsString:filter]) {
                continue;
            }
        }
        [filtered addObject:account];
        if (limit > 0 && filtered.count >= limit) {
            break;
        }
    }

    return filtered;
}

+ (nullable PDSDatabaseAccount *)getAccountWithContext:(PDSCLICommandContext *)context
                                               identifier:(NSString *)identifier {
    NSString *dbPath = [self databasePathForContext:context];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
        return nil;
    }

    NSError *error = nil;
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:&error]) {
        return nil;
    }

    PDSDatabaseAccount *account = [db getAccountByDid:identifier error:&error];
    if (!account || error) {
        account = [db getAccountByHandle:identifier error:&error];
    }

    [db close];
    return account;
}

+ (BOOL)createAccountWithContext:(PDSCLICommandContext *)context
                              email:(NSString *)email
                            handle:(NSString *)handle
                          password:(NSString *)password {
    // Ensure PDSConfiguration loads from the config file (otherwise defaults apply,
    // which has debugSkipPlcOperations=YES and plcURL="mock")
    if (context.configPath && [[NSFileManager defaultManager] fileExistsAtPath:context.configPath]) {
        NSError *configError = nil;
        PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
        if (![config loadFromPath:context.configPath error:&configError]) {
            PDS_LOG_WARN(@"Failed to load config from %@: %@", context.configPath, configError.localizedDescription);
        }
    }

    NSString *dbPath = [self databasePathForContext:context];

    NSError *error = nil;
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:&error]) {
        if (context.verbose) {
            PDS_LOG_ERROR(@"Failed to open database: %@", error.localizedDescription);
        }
        return NO;
    }

    if (context.verbose) {
        PDS_LOG_INFO(@"Creating account: email=%@, handle=%@", email, handle);
    }

    PDSDatabaseAccount *existing = [db getAccountByHandle:handle error:&error];
    if (existing) {
        if (context.verbose) {
            PDS_LOG_WARN(@"Account with handle %@ already exists", handle);
        }
        [db close];
        return NO;
    }

    NSString *pdsHostname = [self pdsHostnameForContext:context];
    NSString *pdsEndpoint = [self pdsServiceEndpointForContext:context];
    
    // Generate Identity Keys
    Secp256k1 *signer = [Secp256k1 shared];
    NSError *keyError = nil;
    Secp256k1KeyPair *keyPair = [signer generateKeyPairWithError:&keyError];
    
    if (!keyPair) {
        if (context.verbose) {
            PDS_LOG_ERROR(@"Failed to generate keypair: %@", keyError.localizedDescription);
        }
        [db close];
        return NO;
    }

    Secp256k1KeyPair *rotationKeyPair = [signer generateKeyPairWithError:&keyError];
    if (!rotationKeyPair) {
        if (context.verbose) {
            PDS_LOG_ERROR(@"Failed to generate rotation keypair: %@", keyError.localizedDescription);
        }
        [db close];
        return NO;
    }

    // Register with PLC
    NSString *did = [self registerDidWithHandle:handle email:email pdsHost:pdsHostname pdsEndpoint:pdsEndpoint keyPair:keyPair rotationKeyPair:rotationKeyPair error:&error];
    if (!did) {
        if (context.verbose) {
            PDS_LOG_ERROR(@"Failed to register DID with PLC: %@", error.localizedDescription);
        }
        [db close];
        return NO;
    }

    // Save keys to ActorStore
    PDSDatabasePool *pool = [[PDSDatabasePool alloc] initWithDbDirectory:[self dataDirForContext:context] maxSize:10];
    PDSActorStore *store = [pool storeForDid:did error:&error];
    if (store) {
        [store importSigningKey:keyPair.privateKey error:nil];
        [store storeRotationKeyPrivate:rotationKeyPair.privateKey
                              publicKey:rotationKeyPair.compressedPublicKey
                                  error:nil];
    } else if (context.verbose) {
        PDS_LOG_ERROR(@"Failed to open ActorStore to save keys: %@", error.localizedDescription);
    }

    if (context.verbose) {
        PDS_LOG_INFO(@"Generated and Registered DID: %@", did);
    }

    // Generate salt and hash password
    NSData *salt = [self generateSalt];
    NSData *passwordHash = [self hashPassword:password salt:salt];
    
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = did;
    account.handle = handle;
    account.email = email;
    account.passwordHash = passwordHash;
    account.passwordSalt = salt;
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = account.createdAt;

    BOOL success = [db createAccount:account error:&error];
    if (!success) {
        if (context.verbose) {
            PDS_LOG_ERROR(@"Failed to create account: %@", error.localizedDescription);
        }
    }

    [db close];
    return success;
}

+ (NSData *)generateSalt {
    NSMutableData *salt = [NSMutableData dataWithLength:32];
    [[NSUUID UUID] getUUIDBytes:salt.mutableBytes]; // Simple salt using UUID bytes
    return salt;
}

+ (NSData *)hashPassword:(NSString *)password salt:(NSData *)salt {
    const uint32_t iterations = 600000;
    const size_t derivedKeyLength = 32;

    NSMutableData *derivedKey = [NSMutableData dataWithLength:derivedKeyLength];

    int result = CCKeyDerivationPBKDF(
        kCCPBKDF2,
        password.UTF8String,
        password.length,
        salt.bytes,
        salt.length,
        kCCPRFHmacAlgSHA256,
        iterations,
        derivedKey.mutableBytes,
        derivedKeyLength
    );

    if (result != kCCSuccess) {
        return nil;
    }

    return [derivedKey copy];
}

+ (NSString *)registerDidWithHandle:(NSString *)handle 
                             email:(NSString *)email 
                           pdsHost:(NSString *)pdsHost 
                       pdsEndpoint:(NSString *)pdsEndpoint
                           keyPair:(Secp256k1KeyPair *)keyPair
                   rotationKeyPair:(Secp256k1KeyPair *)rotationKeyPair
                             error:(NSError **)error {
    NSString *pubKeyDidKey = [NSString stringWithFormat:@"did:key:z%@", [CID base58btcEncode:[self addMulticodecPrefix:keyPair.compressedPublicKey]]];
    NSString *rotationKeyDidKey = [NSString stringWithFormat:@"did:key:z%@", [CID base58btcEncode:[self addMulticodecPrefix:rotationKeyPair.compressedPublicKey]]];

    PLCRotationKeyManager *keyManager = [PLCRotationKeyManager sharedManager];
    [keyManager loadOrGenerateKeyWithError:nil];
    NSString *serverRotationKey = keyManager.rotationKeyDidKey;
    
    NSArray *rotationKeys = @[];
    if (serverRotationKey) {
        rotationKeys = @[serverRotationKey, rotationKeyDidKey];
    } else {
        rotationKeys = @[rotationKeyDidKey];
    }

    // Use the full issuer/endpoint URL if available, otherwise fall back to http://host
    NSString *serviceEndpoint = pdsEndpoint.length > 0 ? pdsEndpoint : [NSString stringWithFormat:@"http://%@", pdsHost];

    // 3. Genesis Op Data
    NSDictionary *opData = @{
        @"type": @"plc_operation",
        @"rotationKeys": rotationKeys,
        @"verificationMethods": @{@"atproto": pubKeyDidKey},
        @"alsoKnownAs": @[[NSString stringWithFormat:@"at://%@", handle]],
        @"services": @{
            @"atproto_pds": @{
                @"type": @"AtprotoPersonalDataServer",
                @"endpoint": serviceEndpoint
            }
        },
        @"prev": [NSNull null]
    };

    // 4. Generate DID (Derive from genesis data)
    NSString *did = [PLCOperation calculateDIDForData:opData];
    
    // 5. POST genesis operation to PLC Server
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NSString *plcUrl = [NSProcessInfo processInfo].environment[@"PDS_PLC_URL"] ?: config.plcURL;
    if (plcUrl.length == 0 || [plcUrl isEqualToString:@"mock"]) {
        plcUrl = @"http://127.0.0.1:2582";
    }
    NSString *urlStr = [NSString stringWithFormat:@"%@/%@", plcUrl, did];
    
    // Encode and sign the operation
    NSError *cborError = nil;
    NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:opData error:&cborError];
    if (!cborData) {
        if (error) *error = cborError;
        return nil;
    }
    
    NSData *sha256 = [CryptoUtils sha256:cborData];
    if (!sha256) {
        if (error) *error = [NSError errorWithDomain:@"PDSCLI" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Hash failure"}];
        return nil;
    }
    
    NSError *sigError = nil;
    // Genesis operations must be signed by a rotation key, not the atproto signing key
    NSData *signature = [[Secp256k1 shared] signHash:sha256 withPrivateKey:rotationKeyPair.privateKey error:&sigError];
    if (!signature) {
        if (error) *error = sigError;
        return nil;
    }
    
    NSMutableDictionary *payload = [opData mutableCopy];
    payload[@"sig"] = [CryptoUtils base64URLEncode:signature];
    
    // Post to PLC server
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block NSError *reqError = nil;
    __block BOOL success = NO;
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) {
            reqError = err;
        } else {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)resp;
            if (httpResp.statusCode == 200 || httpResp.statusCode == 201) {
                success = YES;
            } else {
                NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                reqError = [NSError errorWithDomain:@"PDSCLI" code:httpResp.statusCode userInfo:@{NSLocalizedDescriptionKey: body ?: @"Unknown error"}];
            }
        }
        dispatch_semaphore_signal(sema);
    }] resume];
    
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    
    if (!success) {
        if (error) *error = reqError;
        return nil;
    }
    
    return did;
}

+ (NSData *)addMulticodecPrefix:(NSData *)pubKey {
    // Add secp256k1 multicodec prefix (0xe7, 0x01)
    NSMutableData *data = [NSMutableData dataWithBytes:"\xe7\x01" length:2];
    [data appendData:pubKey];
    return data;
}

+ (BOOL)deactivateAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did {
    if (context.verbose) {
        PDS_LOG_INFO(@"Deactivating account: %@", did);
    }
    return YES;
}

+ (BOOL)reactivateAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did {
    if (context.verbose) {
        PDS_LOG_INFO(@"Reactivating account: %@", did);
    }
    return YES;
}

+ (BOOL)deleteAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did {
    NSString *dbPath = [self databasePathForContext:context];

    NSError *error = nil;
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:&error]) {
        return NO;
    }

    BOOL success = [db deleteAccount:did error:&error];
    if (context.verbose) {
        if (success) {
            PDS_LOG_INFO(@"Deleted account: %@", did);
        } else {
            PDS_LOG_ERROR(@"Failed to delete account: %@", error.localizedDescription);
        }
    }

    [db close];
    return success;
}

+ (BOOL)updateEmailWithContext:(PDSCLICommandContext *)context
                             did:(NSString *)did
                           email:(NSString *)email {
    NSString *dbPath = [self databasePathForContext:context];

    NSError *error = nil;
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:&error]) {
        return NO;
    }

    PDSDatabaseAccount *account = [db getAccountByDid:did error:&error];
    if (!account) {
        [db close];
        return NO;
    }

    account.email = email;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    BOOL success = [db updateAccount:account error:&error];

    [db close];
    return success;
}

+ (BOOL)updateHandleWithContext:(PDSCLICommandContext *)context
                              did:(NSString *)did
                           handle:(NSString *)handle {
    NSString *dbPath = [self databasePathForContext:context];

    NSError *error = nil;
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:&error]) {
        return NO;
    }

    PDSDatabaseAccount *account = [db getAccountByDid:did error:&error];
    if (!account) {
        [db close];
        return NO;
    }

    account.handle = handle;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    BOOL success = [db updateAccount:account error:&error];

    [db close];
    return success;
}

+ (BOOL)updatePlcEndpointWithContext:(PDSCLICommandContext *)context
                                  did:(NSString *)did
                          newEndpoint:(NSString *)newEndpoint {
    if (context.verbose) {
        PDS_LOG_INFO(@"Updating PLC endpoint for %@ to %@", did, newEndpoint);
    }
    
    NSString *dbPath = [self databasePathForContext:context];
    NSError *error = nil;
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:&error]) {
        if (context.verbose) PDS_LOG_ERROR(@"Failed to open DB: %@", error.localizedDescription);
        return NO;
    }

    PDSDatabaseAccount *account = [db getAccountByDid:did error:&error];
    if (!account) {
        if (context.verbose) PDS_LOG_ERROR(@"Account not found");
        [db close];
        return NO;
    }
    [db close];

    // Read the current highest operation from the PLC server
    NSDictionary *config = [context loadConfig];
    NSString *plcUrl = config[@"plc"][@"url"];
    if (!plcUrl) {
        plcUrl = [[NSProcessInfo processInfo] environment][@"PDS_PLC_URL"] ?: @"http://localhost:2582";
    }

    DIDPLCResolver *resolver = [[DIDPLCResolver alloc] initWithPlcUrl:plcUrl];
    NSArray *auditLog = [resolver resolveAuditLogForDID:did error:&error];
    
    if (!auditLog || auditLog.count == 0) {
        if (context.verbose) PDS_LOG_ERROR(@"Failed to fetch PLC log for DID: %@", error.localizedDescription);
        return NO;
    }
    
    NSDictionary *lastOpPayload = auditLog.lastObject;
    NSString *lastOpHash = [PLCOperation calculateCIDForOperation:lastOpPayload error:nil];
    
    if (!lastOpHash) {
         if (context.verbose) PDS_LOG_ERROR(@"Could not calculate cid of previous operation");
         return NO;
    }
    
    NSMutableDictionary *newOpData = [lastOpPayload mutableCopy];
    // Strip old signature
    [newOpData removeObjectForKey:@"sig"];
    newOpData[@"prev"] = lastOpHash;
    
    // Update the service endpoint
    NSMutableDictionary *services = [newOpData[@"services"] mutableCopy] ?: [NSMutableDictionary dictionary];
    services[@"atproto_pds"] = @{
        @"type": @"AtprotoPersonalDataServer",
        @"endpoint": newEndpoint
    };
    newOpData[@"services"] = services;
    
    // Sign It
    PDSDatabasePool *pool = [[PDSDatabasePool alloc] initWithDbDirectory:[self dataDirForContext:context] maxSize:10];
    PDSActorStore *store = [pool storeForDid:did error:&error];
    if (!store) {
        if (context.verbose) PDS_LOG_ERROR(@"Could not open actor store: %@", error.localizedDescription);
        return NO;
    }
    
    NSData *privKeyData = [store exportSigningKeyWithError:&error];
    if (!privKeyData) {
        if (context.verbose) PDS_LOG_ERROR(@"No rotation key available: %@", error.localizedDescription);
        return NO;
    }
    
    NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:newOpData error:&error];
    NSData *sha256 = [CryptoUtils sha256:cborData];
    NSData *signature = [[Secp256k1 shared] signHash:sha256 withPrivateKey:privKeyData error:&error];
    
    if (!signature) {
        if (context.verbose) PDS_LOG_ERROR(@"Failed to sign new PLC op: %@", error.localizedDescription);
        return NO;
    }
    
    newOpData[@"sig"] = [CryptoUtils base64URLEncode:signature];
    
    // Post to PLC
    NSString *postUrl = [NSString stringWithFormat:@"%@/%@", plcUrl, did];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:postUrl]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:newOpData options:0 error:nil];
    
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block BOOL success = NO;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!err && [(NSHTTPURLResponse *)resp statusCode] == 200) {
            success = YES;
        } else {
            NSString *body = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
            if (context.verbose) PDS_LOG_ERROR(@"PLC Post Failed: %ld %@", (long)[(NSHTTPURLResponse *)resp statusCode], body);
        }
        dispatch_semaphore_signal(sema);
    }] resume];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

    return success;
}

@end
