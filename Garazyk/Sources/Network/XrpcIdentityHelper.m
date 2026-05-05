//
//  XrpcIdentityHelper.m
//  ATProtoPDS
//
//  Identity resolution helper implementation for XRPC endpoints.
//

#import "Network/XrpcIdentityHelper.h"
#import "Identity/HandleResolver.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "App/PDSConfiguration.h"
#import "Core/ATProtoValidator.h"
#import "Identity/ATProtoHandleValidator.h"
#import "PLC/DIDPLCResolver.h"
#import "Core/DID.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/PDSLogger.h"

// Helper function to extract normalized handle from alsoKnownAs array
static NSString *normalizedAtHandleFromAlsoKnownAs(NSArray *alsoKnownAs) {
    if (![alsoKnownAs isKindOfClass:[NSArray class]]) {
        return nil;
    }

    for (id value in alsoKnownAs) {
        if (![value isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *candidate = (NSString *)value;
        if ([candidate hasPrefix:@"at://"]) {
            candidate = [candidate substringFromIndex:5];
        }
        if ([candidate hasSuffix:@"/"]) {
            candidate = [candidate substringToIndex:candidate.length - 1];
        }
        if (candidate.length > 0) {
            return [candidate lowercaseString];
        }
    }
    return nil;
}

// Helper function to check if DID document contains a handle
static BOOL didDocumentContainsHandle(DIDDocument *doc, NSString *handle) {
    NSString *normalizedHandle = [handle lowercaseString];
    NSString *docHandle = normalizedAtHandleFromAlsoKnownAs(doc.alsoKnownAs);
    return docHandle.length > 0 && [docHandle isEqualToString:normalizedHandle];
}

@implementation XrpcIdentityHelper

#pragma mark - Public Methods

+ (NSString *)resolveHandleToDid:(NSString *)handle
                  handleResolver:(HandleResolver *)resolver
                           error:(NSError **)error {
    if (!handle || handle.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.identity"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing handle"}];
        }
        return nil;
    }
    
    if (!resolver) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.identity"
                                         code:500
                                     userInfo:@{NSLocalizedDescriptionKey: @"HandleResolver not available"}];
        }
        return nil;
    }
    
    // Use synchronous wrapper around async HandleResolver
    __block NSString *resolvedDid = nil;
    __block NSError *resolveError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [resolver resolveHandle:handle completion:^(NSString * _Nullable did, NSError * _Nullable err) {
        resolvedDid = did;
        resolveError = err;
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    if (!resolvedDid && resolveError) {
        if (error) {
            *error = resolveError;
        }
        return nil;
    }
    
    return resolvedDid;
}

+ (BOOL)resolveAccountIdentifierToDid:(NSString *)identifier
                     serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                               outDid:(NSString **)outDid
                                error:(NSError **)error {
    if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.temp"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing account identifier"}];
        }
        return NO;
    }
    
    PDSDatabaseAccount *account = nil;
    NSError *lookupError = nil;
    
    // Check if identifier is a DID or handle
    if ([ATProtoValidator validateDID:identifier error:nil]) {
        account = [serviceDatabases getAccountByDid:identifier error:&lookupError];
    } else if ([ATProtoHandleValidator validateHandle:identifier error:nil]) {
        account = [serviceDatabases getAccountByHandle:identifier error:&lookupError];
    } else {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.temp"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid account identifier"}];
        }
        return NO;
    }
    
    if (!account) {
        if (error) {
            *error = lookupError ?: [NSError errorWithDomain:@"com.atproto.temp"
                                                        code:404
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }
    
    if (outDid) {
        *outDid = account.did;
    }
    return YES;
}

+ (NSDictionary *)resolveDid:(NSString *)did
            serviceDatabases:(PDSServiceDatabases *)serviceDatabases
               configuration:(PDSConfiguration *)configuration
                       error:(NSError **)error {
    if (![did hasPrefix:@"did:"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.identity"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DID format"}];
        }
        return nil;
    }

    // Parse DID method
    NSArray<NSString *> *components = [did componentsSeparatedByString:@":"];
    if (components.count < 3) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.identity"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DID format"}];
        }
        return nil;
    }

    NSString *method = components[1];

    // AT Protocol only supports did:plc and did:web
    if (![method isEqualToString:@"plc"] && ![method isEqualToString:@"web"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.identity"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"Unsupported DID method: %@ (AT Protocol only supports did:plc and did:web)", did]}];
        }
        return nil;
    }

    // First try local account as fast path (for hosted DIDs)
    PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:nil];
    if (account && account.handle.length > 0) {
        NSString *serviceEndpoint = [configuration canonicalIssuerWithPortHint:0];
        NSDictionary *localDoc = @{
            @"@context": @[@"https://www.w3.org/ns/did/v1"],
            @"id": did,
            @"alsoKnownAs": @[[NSString stringWithFormat:@"at://%@", account.handle]],
            @"service": @[
                @{
                    @"id": @"#atproto_pds",
                    @"type": @"AtprotoPersonalDataServer",
                    @"serviceEndpoint": serviceEndpoint
                }
            ]
        };

        // For did:plc, prefer fresh data from PLC directory
        if ([method isEqualToString:@"plc"]) {
            NSString *plcUrl = configuration.plcURL;
            if ([plcUrl isEqualToString:@"mock"] || plcUrl.length == 0) {
                plcUrl = @"http://127.0.0.1:2582";
            }

            DIDPLCResolver *plcResolver = [[DIDPLCResolver alloc] initWithPlcUrl:plcUrl];
            plcResolver.timeout = 10.0;

            NSError *plcError = nil;
            NSDictionary *doc = [plcResolver resolveDID:did error:&plcError];
            if (doc) {
                return doc;
            }
        }

        // For did:web, try external resolution via DIDResolver
        if ([method isEqualToString:@"web"]) {
            DIDResolver *didResolver = [DIDResolver sharedResolver];
            NSError *resolveError = nil;
            DIDDocument *doc = [didResolver resolveDIDSync:did error:&resolveError];
            if (doc) {
                return doc.jsonDictionary;
            }
        }

        // Return local account data if external resolution fails
        return localDoc;
    }

    // No local account - use DIDResolver for external resolution
    // DIDResolver supports both did:plc and did:web
    DIDResolver *didResolver = [DIDResolver sharedResolver];
    NSError *resolveError = nil;
    DIDDocument *doc = [didResolver resolveDIDSync:did error:&resolveError];

    if (doc) {
        return doc.jsonDictionary;
    }

    if (error) {
        *error = resolveError;
    }
    return nil;
}

+ (NSDictionary *)defaultPdsServiceForConfig:(PDSConfiguration *)configuration {
    NSString *serviceEndpoint = [configuration canonicalIssuerWithPortHint:0];
    return @{
        @"atproto_pds": @{
            @"type": @"AtprotoPersonalDataServer",
            @"endpoint": serviceEndpoint
        }
    };
}

+ (NSDictionary *)resolveIdentityInfoForIdentifier:(NSString *)identifier
                                   serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                                          errorName:(NSString **)errorName
                                              error:(NSError **)error {
    if ([identifier hasPrefix:@"did:"]) {
        PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:identifier error:nil];
        if (account) {
            NSString *handle = account.handle.length > 0 ? [account.handle lowercaseString] : @"handle.invalid";
            NSDictionary *didDoc = @{
                @"id": account.did ?: identifier,
                @"alsoKnownAs": handle.length > 0 ? @[[NSString stringWithFormat:@"at://%@", handle]] : @[]
            };
            return @{
                @"did": account.did ?: identifier,
                @"handle": handle,
                @"didDoc": didDoc
            };
        }
    } else {
        PDSDatabaseAccount *account = [serviceDatabases getAccountByHandle:identifier error:nil];
        if (account) {
            NSString *handle = account.handle.length > 0 ? [account.handle lowercaseString] : @"handle.invalid";
            NSDictionary *didDoc = @{
                @"id": account.did ?: @"",
                @"alsoKnownAs": handle.length > 0 ? @[[NSString stringWithFormat:@"at://%@", handle]] : @[]
            };
            return @{
                @"did": account.did ?: @"",
                @"handle": handle,
                @"didDoc": didDoc
            };
        }
    }

    DIDResolver *didResolver = [DIDResolver sharedResolver];

    if ([identifier hasPrefix:@"did:"]) {
        DIDDocument *doc = [didResolver resolveDIDSync:identifier error:error];
        if (!doc) {
            if (errorName) *errorName = @"DidNotFound";
            return nil;
        }
        NSString *handle = normalizedAtHandleFromAlsoKnownAs(doc.alsoKnownAs) ?: @"handle.invalid";
        return @{
            @"did": identifier,
            @"handle": handle,
            @"didDoc": doc.jsonDictionary ?: @{}
        };
    }

    HandleResolver *handleResolver = [[HandleResolver alloc] init];
    __block NSString *did = nil;
    __block NSError *capturedError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [handleResolver resolveHandle:identifier completion:^(NSString * _Nullable resolvedDid, NSError * _Nullable resolveError) {
        did = resolvedDid;
        capturedError = resolveError;
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    if (did.length == 0) {
        if (errorName) *errorName = @"HandleNotFound";
        if (error && !*error) {
            *error = capturedError ?: [NSError errorWithDomain:@"com.atproto.identity"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Handle resolution failed"}];
        }
        return nil;
    }

    DIDDocument *doc = [didResolver resolveDIDSync:did error:error];
    if (!doc) {
        if (errorName) *errorName = @"DidNotFound";
        return nil;
    }

    NSString *resolvedHandle = didDocumentContainsHandle(doc, identifier) ? [identifier lowercaseString] : @"handle.invalid";
    return @{
        @"did": did,
        @"handle": resolvedHandle,
        @"didDoc": doc.jsonDictionary ?: @{}
    };
}

+ (BOOL)updateAccountHandle:(PDSServiceDatabases *)serviceDatabases
                        did:(NSString *)did
                     handle:(NSString *)handle
                      error:(NSError **)error {
    PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:error];
    if (!account) {
        return NO;
    }
    account.handle = handle;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    return [serviceDatabases updateAccount:account error:error];
}

+ (NSString *)currentISO8601String {
    return [NSDateFormatter atproto_stringFromDate:[NSDate date]];
}

@end
