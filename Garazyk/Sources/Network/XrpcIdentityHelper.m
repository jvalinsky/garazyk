// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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
#import "App/ATProtoServiceConfiguration.h"
#import "Core/ATProtoValidator.h"
#import "Identity/ATProtoHandleValidator.h"
#import "PLC/DIDPLCResolver.h"
#import "Auth/JWT.h"
#import "Core/CID.h"
#import "Core/DID.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Security/PDSSecurityCompare.h"
#import "Debug/GZLogger.h"

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

static NSString *spaceHostEndpointForConfiguration(ATProtoServiceConfiguration *configuration,
                                                    NSString *fallbackEndpoint) {
    NSString *configured = [configuration stringForKey:@"permissionedSpacesHostEndpoint"];
    if (configured.length == 0) return fallbackEndpoint;
    NSURLComponents *components = [NSURLComponents componentsWithString:configured];
    BOOL valid = components != nil &&
        ([components.scheme isEqualToString:@"https"] || [components.scheme isEqualToString:@"http"]) &&
        components.host.length > 0 && components.user.length == 0 &&
        components.password.length == 0 && components.query.length == 0 &&
        components.fragment.length == 0;
    return valid ? configured : fallbackEndpoint;
}

static NSArray<NSDictionary *> *servicesForConfiguration(ATProtoServiceConfiguration *configuration,
                                                          NSString *pdsEndpoint) {
    NSMutableArray<NSDictionary *> *services = [NSMutableArray arrayWithObject:@{
        @"id" : @"#atproto_pds",
        @"type" : @"AtprotoPersonalDataServer",
        @"serviceEndpoint" : pdsEndpoint
    }];
    if ([configuration boolForKey:@"permissionedSpacesEnabled"]) {
        [services addObject:@{
            @"id" : @"#atproto_space_host",
            @"type" : @"AtprotoPersonalDataServer",
            @"serviceEndpoint" : spaceHostEndpointForConfiguration(configuration, pdsEndpoint)
        }];
    }
    return services;
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
    
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    
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

+ (nullable NSData *)publicKeyBytesFromMultibase:(NSString *)multibase
                                           error:(NSError **)error {
    if (multibase.length < 2) {
        if (error) {
            *error = [NSError errorWithDomain:DIDErrorDomain
                                         code:DIDErrorInvalidDocument
                                     userInfo:@{
                                         NSLocalizedDescriptionKey :
                                             @"Invalid publicKeyMultibase value"
                                     }];
        }
        return nil;
    }

    unichar prefix = [multibase characterAtIndex:0];
    NSString *payload = [multibase substringFromIndex:1];
    NSData *data = nil;
    switch (prefix) {
        case 'z':
        case 'Z':
            data = [CID base58btcDecode:payload];
            break;
        case 'b':
            data = [CID base32Decode:payload];
            break;
        case 'u':
            data = [JWT base64URLDecode:payload error:error];
            break;
        default:
            if (error) {
                *error = [NSError
                    errorWithDomain:DIDErrorDomain
                               code:DIDErrorInvalidDocument
                           userInfo:@{
                               NSLocalizedDescriptionKey :
                                   @"Unsupported multibase encoding for signing key"
                           }];
            }
            return nil;
    }

    if (!data) {
        return nil;
    }

    const uint8_t *bytes = data.bytes;
    if (data.length > 2 && bytes[0] == 0xE7 && bytes[1] == 0x01) {
        return [data subdataWithRange:NSMakeRange(2, data.length - 2)];
    }
    return data;
}

+ (NSDictionary *)resolveDid:(NSString *)did
            serviceDatabases:(PDSServiceDatabases *)serviceDatabases
               configuration:(ATProtoServiceConfiguration *)configuration
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
            @"service": servicesForConfiguration(configuration, serviceEndpoint)
        };

        // For did:plc, prefer fresh data from PLC directory
        if ([method isEqualToString:@"plc"]) {
            NSString *plcUrl = configuration.plcURL;
            if ([plcUrl isEqualToString:@"mock"] ||
                [plcUrl isEqualToString:@"skip"] ||
                plcUrl.length == 0) {
                return localDoc;
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

+ (NSDictionary *)defaultPdsServiceForConfig:(ATProtoServiceConfiguration *)configuration {
    NSString *serviceEndpoint = [configuration canonicalIssuerWithPortHint:0];
    NSMutableDictionary *services = [@{
        @"atproto_pds": @{
            @"type": @"AtprotoPersonalDataServer",
            @"endpoint": serviceEndpoint
        }
    } mutableCopy];
    if ([configuration boolForKey:@"permissionedSpacesEnabled"]) {
        services[@"atproto_space_host"] = @{
            @"type" : @"AtprotoPersonalDataServer",
            @"endpoint" : spaceHostEndpointForConfiguration(configuration, serviceEndpoint)
        };
    }
    return services;
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

#pragma mark - PLC Operation Tokens

static NSTimeInterval const kPlcOperationTokenTTLSeconds = 15.0 * 60.0;

static NSCache<NSString *, NSDictionary *> *plcOperationTokenCache(void) {
    static NSCache<NSString *, NSDictionary *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 1024;
    });
    return cache;
}

+ (void)storePlcOperationToken:(NSString *)token forDid:(NSString *)did {
    if (![token isKindOfClass:[NSString class]] || token.length == 0) {
        return;
    }
    if (![did isKindOfClass:[NSString class]] || did.length == 0) {
        return;
    }

    NSDate *expiresAt = [NSDate dateWithTimeIntervalSinceNow:kPlcOperationTokenTTLSeconds];
    NSDictionary *entry = @{@"token": token, @"expiresAt": expiresAt};
    [plcOperationTokenCache() setObject:entry forKey:did];
}

+ (BOOL)validatePlcOperationToken:(NSString *)token forDid:(NSString *)did {
    if (![token isKindOfClass:[NSString class]] || token.length == 0) {
        return NO;
    }
    if (![did isKindOfClass:[NSString class]] || did.length == 0) {
        return NO;
    }

    NSCache<NSString *, NSDictionary *> *cache = plcOperationTokenCache();
    NSDictionary *entry = [cache objectForKey:did];
    if (![entry isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    NSString *expected = entry[@"token"];
    NSDate *expiresAt = entry[@"expiresAt"];
    if (![expected isKindOfClass:[NSString class]] || ![expiresAt isKindOfClass:[NSDate class]]) {
        [cache removeObjectForKey:did];
        return NO;
    }
    if ([expiresAt timeIntervalSinceNow] <= 0) {
        [cache removeObjectForKey:did];
        return NO;
    }

    BOOL equal = [PDSSecurityCompare constantTimeEqualString:expected string:token];

    [cache removeObjectForKey:did];
    return equal;
}

@end
