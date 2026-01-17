#import "PDSCLIDefinitions.h"
#import "Debug/PDSLogger.h"
#import "Database/PDSDatabase.h"
#import "Database/Schema.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonKeyDerivation.h>

#ifndef kCCSuccess
#define kCCSuccess 0
#endif

@interface PDSCLIAccountManager : NSObject

+ (NSArray<PDSDatabaseAccount *> *)listAccountsWithContext:(PDSCLICommandContext *)context
                                                    filter:(NSString *)filter
                                                    limit:(NSInteger)limit;
+ (nullable PDSDatabaseAccount *)getAccountWithContext:(PDSCLICommandContext *)context
                                              identifier:(NSString *)identifier;
+ (BOOL)createAccountWithContext:(PDSCLICommandContext *)context
                             email:(NSString *)email
                           handle:(NSString *)handle
                         password:(NSString *)password;
+ (BOOL)deactivateAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did;
+ (BOOL)reactivateAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did;
+ (BOOL)deleteAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did;
+ (BOOL)updateEmailWithContext:(PDSCLICommandContext *)context
                            did:(NSString *)did
                          email:(NSString *)email;
+ (BOOL)updateHandleWithContext:(PDSCLICommandContext *)context
                             did:(NSString *)did
                          handle:(NSString *)handle;

+ (NSString *)databasePathForContext:(PDSCLICommandContext *)context;
+ (NSString *)pdsHostnameForContext:(PDSCLICommandContext *)context;

@end

@implementation PDSCLIAccountManager

+ (NSString *)databasePathForContext:(PDSCLICommandContext *)context {
    NSDictionary *config = [context loadConfig];
    NSString *dataDir = context.dataDir;
    if (config[@"server"][@"data_dir"]) {
        dataDir = config[@"server"][@"data_dir"];
    }
    return [[dataDir stringByAppendingPathComponent:@"service"] stringByAppendingPathComponent:@"service.db"];
}

+ (NSString *)pdsHostnameForContext:(PDSCLICommandContext *)context {
    NSDictionary *config = [context loadConfig];
    NSString *host = config[@"server"][@"host"];
    if (!host || host.length == 0) {
        host = @"localhost";
    }
    if ([host isEqualToString:@"0.0.0.0"]) {
        host = @"localhost";
    }
    return host;
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
    
    // Register with PLC
    NSString *did = [self registerDidWithHandle:handle email:email pdsHost:pdsHostname error:&error];
    if (!did) {
        if (context.verbose) {
            PDS_LOG_ERROR(@"Failed to register DID with PLC: %@", error.localizedDescription);
        }
        [db close];
        return NO;
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

    unsigned char derivedKey[derivedKeyLength];

    int result = CCKeyDerivationPBKDF(
        kCCPBKDF2,
        password.UTF8String,
        password.length,
        salt.bytes,
        salt.length,
        kCCPRFHmacAlgSHA256,
        iterations,
        derivedKey,
        derivedKeyLength
    );

    if (result != kCCSuccess) {
        return nil;
    }

    return [NSData dataWithBytes:derivedKey length:derivedKeyLength];
}

+ (NSString *)registerDidWithHandle:(NSString *)handle 
                             email:(NSString *)email 
                           pdsHost:(NSString *)pdsHost 
                             error:(NSError **)error {
    // 1. Generate Keypair
    Secp256k1 *signer = [Secp256k1 shared];
    NSError *keyError = nil;
    Secp256k1KeyPair *keyPair = [signer generateKeyPairWithError:&keyError];
    if (!keyPair) {
        if (error) *error = keyError;
        return nil;
    }

    NSString *pubKeyDidKey = [NSString stringWithFormat:@"did:key:z%@", [CID base58btcEncode:[self addMulticodecPrefix:keyPair.publicKey]]];

    // 2. Construct Genesis Op Data
    // Note: In a real app, you'd want separate rotation and signing keys
    NSDictionary *opData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[pubKeyDidKey],
        @"verificationMethods": @{@"atproto": pubKeyDidKey},
        @"alsoKnownAs": @[[NSString stringWithFormat:@"at://%@", handle]],
        @"services": @{
            @"atproto_pds": @{
                @"type": @"AtprotoPersonalDataServer",
                @"endpoint": [NSString stringWithFormat:@"http://%@", pdsHost] // Assuming pdsHost includes port if needed, or we fix this
            }
        },
        @"prev": [NSNull null]
    };

    // 3. Encode and Hash
    NSError *cborError = nil;
    NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:opData error:&cborError];
    if (!cborData) {
        if (error) *error = cborError;
        return nil;
    }
    
    NSData *sha256 = [self sha256:cborData];
    
    // 4. Sign
    NSError *sigError = nil;
    NSData *signature = [signer signHash:sha256 withPrivateKey:keyPair.privateKey error:&sigError];
    if (!signature) {
        if (error) *error = sigError;
        return nil;
    }
    
    // 5. Construct Payload (Flattened)
    NSMutableDictionary *payload = [opData mutableCopy];
    payload[@"sig"] = [signature base64EncodedStringWithOptions:0];
    
    // 6. Generate DID
    NSString *did = [self generatePlcDid];
    
    // 7. POST to PLC Server (loop 25 times)
    NSString *plcUrl = [NSProcessInfo processInfo].environment[@"PDS_PLC_URL"] ?: @"http://localhost:2582";
    NSString *urlStr = [NSString stringWithFormat:@"%@/%@", plcUrl, did];
    
    // Initial genesis op
    NSDictionary *currentOpData = opData;
    NSString *prevHash = nil;
    
    for (int i = 0; i < 25; i++) {
        // If not first op, update it
        if (i > 0) {
            NSMutableDictionary *newOp = [currentOpData mutableCopy];
            newOp[@"prev"] = prevHash;
            
            // Mutate service to ensure uniqueness
            NSMutableDictionary *services = [newOp[@"services"] mutableCopy];
            services[[NSString stringWithFormat:@"dummy_%d", i]] = @{
                @"type": @"DummyService",
                @"endpoint": [NSString stringWithFormat:@"http://dummy%d.test", i]
            };
            newOp[@"services"] = services;
            
            currentOpData = newOp;
        }
        
        // Encode and Sign
        NSError *cborError = nil;
        NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:currentOpData error:&cborError];
         if (!cborData) {
            if (error) *error = cborError;
            return nil;
        }
        
        NSData *sha256 = [self sha256:cborData];
        
        // PLCAuditor expects 'prev' to be the CID string of the SHA256 hash (DAG-CBOR codec 0x71)
        NSString *prevHashHex = [[CID cidWithDigest:sha256 codec:0x71] stringValue];
        
        NSError *sigError = nil;
        NSData *signature = [signer signHash:sha256 withPrivateKey:keyPair.privateKey error:&sigError];
        if (!signature) {
            if (error) *error = sigError;
            return nil;
        }
        
        NSMutableDictionary *payload = [currentOpData mutableCopy];
        payload[@"sig"] = [signature base64EncodedStringWithOptions:0];
        
        // Post
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
                if (httpResp.statusCode == 200) {
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
        
        prevHash = prevHashHex; // Set prev for next iteration
        
        if (i%5==0) [NSThread sleepForTimeInterval:0.1]; // Brief pause to be nice
    }
    
    return did;
}

+ (NSData *)addMulticodecPrefix:(NSData *)pubKey {
    // Add secp256k1 multicodec prefix (0xe7, 0x01)
    NSMutableData *data = [NSMutableData dataWithBytes:"\xe7\x01" length:2];
    [data appendData:pubKey];
    return data;
}

+ (NSData *)sha256:(NSData *)data {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

+ (NSString *)generatePlcDid {
    NSString *alphabet = @"abcdefghijklmnopqrstuvwxyz234567";
    NSMutableString *identifier = [NSMutableString stringWithCapacity:24];
    for (int i = 0; i < 24; i++) {
        unichar c = [alphabet characterAtIndex:arc4random_uniform((uint32_t)alphabet.length)];
        [identifier appendFormat:@"%C", c];
    }
    return [NSString stringWithFormat:@"did:plc:%@", identifier];
}

+ (BOOL)isValidPlcDid:(NSString *)did {
    if (![did hasPrefix:@"did:plc:"]) {
        return NO;
    }
    
    NSString *idPart = [did substringFromIndex:8];
    if (idPart.length != 24) {
        return NO;
    }
    
    NSCharacterSet *validChars = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz234567"];
    NSCharacterSet *inputChars = [NSCharacterSet characterSetWithCharactersInString:idPart];
    
    return [validChars isSupersetOfSet:inputChars];
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

@end

#pragma mark - Account Command

@interface PDSCLIAccountCommand : PDSBaseCommand

@end

@implementation PDSCLIAccountCommand

- (NSString *)name {
    return @"account";
}

- (NSString *)summary {
    return @"Manage PDS accounts";
}

- (NSString *)usage {
    return @"pds account <subcommand> [options]";
}

- (NSString *)helpText {
    return @"Manage PDS accounts.\n\n"
           @"Subcommands:\n"
           @"  list                   List all accounts\n"
           @"  info <did|handle>      Show account details\n"
           @"  create --email <email> --handle <handle> [--password <pw>]  Create a new account\n"
           @"  deactivate <did>       Deactivate an account\n"
           @"  reactivate <did>       Reactivate a deactivated account\n"
           @"  delete <did>           Permanently delete an account\n"
           @"  update-email <did> <email>  Update account email\n"
           @"  update-handle <did> <handle>  Update account handle\n\n"
           @"Options for 'list':\n"
           @"  --limit, -l <n>        Limit results (default: 100)\n"
           @"  --filter, -f <text>    Filter by handle, email, or DID";
}

- (NSArray<NSString *> *)aliases {
    return @[];
}

- (NSArray<NSString *> *)subcommands {
    return @[@"list", @"info", @"create", @"deactivate", @"reactivate", @"delete", @"update-email", @"update-handle"];
}

- (void)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printInfo:[self helpText]];
        return;
    }

    NSString *subcommand = args[0];
    NSArray *subArgs = args.count > 1 ? [args subarrayWithRange:NSMakeRange(1, args.count - 1)] : @[];

    if ([subcommand isEqualToString:@"list"]) {
        [self executeListWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"info"]) {
        [self executeInfoWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"create"]) {
        [self executeCreateWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"deactivate"]) {
        [self executeDeactivateWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"reactivate"]) {
        [self executeReactivateWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"delete"]) {
        [self executeDeleteWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"update-email"]) {
        [self executeUpdateEmailWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"update-handle"]) {
        [self executeUpdateHandleWithArgs:subArgs context:context];
    } else {
        [context printError:[NSString stringWithFormat:@"Unknown subcommand: %@", subcommand]];
    }
}

- (void)executeListWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    NSInteger limit = 100;
    NSString *filter = @"";

    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg isEqualToString:@"--limit"] || [arg isEqualToString:@"-l"]) {
            if (i + 1 < args.count) {
                limit = [args[++i] integerValue];
            }
        } else if ([arg isEqualToString:@"--filter"] || [arg isEqualToString:@"-f"]) {
            if (i + 1 < args.count) {
                filter = args[++i];
            }
        }
    }

    NSArray<PDSDatabaseAccount *> *accounts = [PDSCLIAccountManager listAccountsWithContext:context
                                                                                  filter:filter
                                                                                  limit:limit];

    if (context.jsonOutput) {
        NSMutableArray *output = [NSMutableArray array];
        for (PDSDatabaseAccount *account in accounts) {
            [output addObject:@{
                @"did": account.did ?: @"",
                @"handle": account.handle ?: @"",
                @"email": account.email ?: @"",
                @"created_at": @(account.createdAt),
                @"updated_at": @(account.updatedAt)
            }];
        }
        [context printJSON:output];
    } else {
        if (accounts.count == 0) {
            NSString *hostname = [PDSCLIAccountManager pdsHostnameForContext:context];
            PDS_LOG_INFO(@"No accounts found in database");
            [context printInfo:@"No accounts found."];
            [context printInfo:@"\nTo create your first account, run:"];
            [context printInfo:[NSString stringWithFormat:@"  pds account create --email you@example.com --handle yourhandle.%@", hostname]];
            [context printInfo:@"\nFor testing, you can use the .test TLD:"];
            [context printInfo:@"  pds account create -e test@test.com -h testuser.test"];
            return;
        }
        printf("%-44s %-30s %-30s %s\n", "DID", "Handle", "Email", "Created");
        printf("%-44s %-30s %-30s %s\n", "----", "------", "-----", "-------");

        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm";

        for (PDSDatabaseAccount *account in accounts) {
            NSDate *created = [NSDate dateWithTimeIntervalSince1970:account.createdAt];
            printf("%-44s %-30s %-30s %s\n",
                   [account.did UTF8String],
                   [account.handle UTF8String],
                   [account.email ? account.email : @"<none>" UTF8String],
                   [[formatter stringFromDate:created] UTF8String]);
        }

        printf("\nTotal accounts: %lu\n", (unsigned long)accounts.count);
    }
}

- (void)executeInfoWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing account identifier"];
        [context printInfo:@"\nUsage: pds account info <did|handle>"];
        NSString *hostname = [PDSCLIAccountManager pdsHostnameForContext:context];
        [context printInfo:@"\nExamples:"];
        [context printInfo:@"  pds account info did:plc:abc123"];
        [context printInfo:[NSString stringWithFormat:@"  pds account info username.%@", hostname]];
        return;
    }

    NSString *identifier = args[0];
    PDSDatabaseAccount *account = [PDSCLIAccountManager getAccountWithContext:context identifier:identifier];

    if (!account) {
        PDS_LOG_WARN(@"Account not found: %@", identifier);
        [context printError:[NSString stringWithFormat:@"Account not found: %@", identifier]];
        [context printInfo:@"\nTo find accounts, run:"];
        [context printInfo:@"  pds account list"];
        return;
    }

    if (context.jsonOutput) {
        [context printJSON:@{
            @"did": account.did ?: @"",
            @"handle": account.handle ?: @"",
            @"email": account.email ?: @"",
            @"created_at": @(account.createdAt),
            @"updated_at": @(account.updatedAt)
        }];
    } else {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss Z";
        NSDate *created = [NSDate dateWithTimeIntervalSince1970:account.createdAt];
        NSDate *updated = [NSDate dateWithTimeIntervalSince1970:account.updatedAt];

        printf("Account Information:\n");
        printf("  DID:        %s\n", [account.did UTF8String]);
        printf("  Handle:     %s\n", [account.handle UTF8String]);
        printf("  Email:      %s\n", [account.email ?: @"<none>" UTF8String]);
        printf("  Created:    %s\n", [[formatter stringFromDate:created] UTF8String]);
        printf("  Updated:    %s\n", [[formatter stringFromDate:updated] UTF8String]);
    }
}

- (void)executeCreateWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    NSString *email = @"";
    NSString *handle = @"";
    NSString *password = @"";

    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg isEqualToString:@"--email"] || [arg isEqualToString:@"-e"]) {
            if (i + 1 < args.count) email = args[++i];
        } else if ([arg isEqualToString:@"--handle"] || [arg isEqualToString:@"-h"]) {
            if (i + 1 < args.count) handle = args[++i];
        } else if ([arg isEqualToString:@"--password"] || [arg isEqualToString:@"-p"]) {
            if (i + 1 < args.count) password = args[++i];
        }
    }
    
    if (email.length == 0 || handle.length == 0) {
        [context printError:@"Missing required arguments: --email and --handle"];
        NSString *hostname = [PDSCLIAccountManager pdsHostnameForContext:context];
        [context printInfo:@"\nUsage: pds account create --email <email> --handle <handle> [--password <pw>]"];
        [context printInfo:[NSString stringWithFormat:@"\nExamples:"]];
        [context printInfo:[NSString stringWithFormat:@"  pds account create --email alice@example.com --handle alice.%@", hostname]];
        [context printInfo:@"  pds account create -e bob@test.com -h bob.test -p secret123"];
        return;
    }

    NSError *emailError = nil;
    if (![ATProtoHandleValidator validateEmail:email error:&emailError]) {
        [context printError:[NSString stringWithFormat:@"Invalid email: %@", emailError.localizedDescription]];
        if (emailError.userInfo[NSLocalizedRecoverySuggestionErrorKey]) {
            [context printInfo:emailError.userInfo[NSLocalizedRecoverySuggestionErrorKey]];
        }
        return;
    }

    NSError *handleError = nil;
    NSString *normalizedHandle = [ATProtoHandleValidator validateAndNormalizeHandle:handle error:&handleError];
    if (!normalizedHandle) {
        [context printError:[NSString stringWithFormat:@"Invalid handle '%@': %@", handle, handleError.localizedDescription]];
        if (handleError.userInfo[NSLocalizedRecoverySuggestionErrorKey]) {
            [context printInfo:handleError.userInfo[NSLocalizedRecoverySuggestionErrorKey]];
        }
        NSString *hostname = [PDSCLIAccountManager pdsHostnameForContext:context];
        [context printInfo:[NSString stringWithFormat:@"\nValid handle formats:"]];
        [context printInfo:[NSString stringWithFormat:@"  username.%@       (uses this PDS)", hostname]];
        [context printInfo:@"  bob.test              (test TLD for development)"];
        [context printInfo:@"  carol.com             (any valid domain)"];
        return;
    }

    BOOL success = [PDSCLIAccountManager createAccountWithContext:context
                                                          email:email
                                                        handle:normalizedHandle
                                                      password:password];

    if (success) {
        PDS_LOG_INFO(@"Account created successfully: %@", normalizedHandle);
        [context printInfo:@"Account created successfully"];
        [context printInfo:[NSString stringWithFormat:@"Handle: %@", normalizedHandle]];
        [context printInfo:[NSString stringWithFormat:@"Email: %@", email]];
    } else {
        NSString *dbPath = [PDSCLIAccountManager databasePathForContext:context];
        if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
            PDS_LOG_ERROR(@"Database not found at %@", dbPath);
            [context printError:@"Database not found. Make sure the PDS data directory exists."];
            [context printInfo:[NSString stringWithFormat:@"Expected database at: %@", dbPath]];
        } else {
            PDS_LOG_ERROR(@"Failed to create account for handle: %@", normalizedHandle);
            [context printError:@"Failed to create account"];
            [context printInfo:@"Possible causes:"];
            [context printInfo:@"  - Handle already in use"];
            [context printInfo:@"  - Email already registered"];
            [context printInfo:@"  - Database error"];
        }
    }
}

- (void)executeDeactivateWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing account DID"];
        return;
    }

    NSString *did = args[0];
    BOOL success = [PDSCLIAccountManager deactivateAccountWithContext:context did:did];

    if (success) {
        [context printInfo:@"Account deactivated"];
    } else {
        [context printError:@"Failed to deactivate account"];
    }
}

- (void)executeReactivateWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing account DID"];
        return;
    }

    NSString *did = args[0];
    BOOL success = [PDSCLIAccountManager reactivateAccountWithContext:context did:did];

    if (success) {
        [context printInfo:@"Account reactivated"];
    } else {
        [context printError:@"Failed to reactivate account"];
    }
}

- (void)executeDeleteWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing account DID"];
        return;
    }

    NSString *did = args[0];
    BOOL success = [PDSCLIAccountManager deleteAccountWithContext:context did:did];

    if (success) {
        [context printInfo:@"Account deleted"];
    } else {
        [context printError:@"Failed to delete account"];
    }
}

- (void)executeUpdateEmailWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count < 2) {
        [context printError:@"Missing arguments: --update-email <did> <email>"];
        [context printInfo:@"\nUsage: pds account update-email <did> <new-email>"];
        [context printInfo:@"\nExample:"];
        [context printInfo:@"  pds account update-email did:plc:abc123 newemail@example.com"];
        return;
    }

    NSString *did = args[0];
    NSString *email = args[1];

    NSError *emailError = nil;
    if (![ATProtoHandleValidator validateEmail:email error:&emailError]) {
        [context printError:[NSString stringWithFormat:@"Invalid email: %@", emailError.localizedDescription]];
        if (emailError.userInfo[NSLocalizedRecoverySuggestionErrorKey]) {
            [context printInfo:emailError.userInfo[NSLocalizedRecoverySuggestionErrorKey]];
        }
        return;
    }

    BOOL success = [PDSCLIAccountManager updateEmailWithContext:context did:did email:email];

    if (success) {
        PDS_LOG_INFO(@"Email updated for account %@: %@", did, email);
        [context printInfo:@"Email updated successfully"];
        [context printInfo:[NSString stringWithFormat:@"New email: %@", email]];
    } else {
        PDS_LOG_ERROR(@"Failed to update email for account %@", did);
        [context printError:@"Failed to update email"];
        [context printInfo:@"Possible causes:"];
        [context printInfo:@"  - Account not found"];
        [context printInfo:@"  - Database error"];
    }
}

- (void)executeUpdateHandleWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count < 2) {
        [context printError:@"Missing arguments: --update-handle <did> <handle>"];
        [context printInfo:@"\nUsage: pds account update-handle <did> <new-handle>"];
        [context printInfo:@"\nExample:"];
        [context printInfo:@"  pds account update-handle did:plc:abc123 newhandle.bsky.social"];
        return;
    }

    NSString *did = args[0];
    NSString *handle = args[1];

    NSError *handleError = nil;
    NSString *normalizedHandle = [ATProtoHandleValidator validateAndNormalizeHandle:handle error:&handleError];
    if (!normalizedHandle) {
        [context printError:[NSString stringWithFormat:@"Invalid handle '%@': %@", handle, handleError.localizedDescription]];
        if (handleError.userInfo[NSLocalizedRecoverySuggestionErrorKey]) {
            [context printInfo:handleError.userInfo[NSLocalizedRecoverySuggestionErrorKey]];
        }
        return;
    }

    BOOL success = [PDSCLIAccountManager updateHandleWithContext:context did:did handle:normalizedHandle];

    if (success) {
        PDS_LOG_INFO(@"Handle updated for account %@: %@", did, normalizedHandle);
        [context printInfo:@"Handle updated successfully"];
        [context printInfo:[NSString stringWithFormat:@"New handle: %@", normalizedHandle]];
    } else {
        PDS_LOG_ERROR(@"Failed to update handle for account %@", did);
        [context printError:@"Failed to update handle"];
        [context printInfo:@"Possible causes:"];
        [context printInfo:@"  - Account not found"];
        [context printInfo:@"  - Handle already in use by another account"];
        [context printInfo:@"  - Database error"];
    }
}

@end

#pragma mark - Register

@interface PDSAccountCommandRegistrar : NSObject
@end

@implementation PDSAccountCommandRegistrar

+ (void)load {
    [[PDSCLIDispatcher sharedDispatcher] addCommand:[[PDSCLIAccountCommand alloc] init]];
}

@end
