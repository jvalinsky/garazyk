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
#import "Debug/PDSLogger.h"

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
    
    // Handle did:plc with PLC directory resolution and local fallback
    if ([did hasPrefix:@"did:plc:"]) {
        NSString *plcUrl = configuration.plcURL;
        if ([plcUrl isEqualToString:@"mock"] || plcUrl.length == 0) {
            plcUrl = @"http://127.0.0.1:2582";
        }
        
        DIDPLCResolver *resolver = [[DIDPLCResolver alloc] initWithPlcUrl:plcUrl];
        resolver.timeout = 10.0;
        
        NSError *plcError = nil;
        NSDictionary *doc = [resolver resolveDID:did error:&plcError];
        if (doc) {
            return doc;
        }
        
        // PLC unreachable or DID not found there — try local account as fallback
        PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:nil];
        if (account && account.handle.length > 0) {
            NSString *serviceEndpoint = [configuration canonicalIssuerWithPortHint:0];
            return @{
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
        }
        
        if (error) {
            *error = plcError;
        }
        return nil;
    }
    
    // Unsupported DID method
    if (error) {
        *error = [NSError errorWithDomain:@"com.atproto.identity"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey:
                                     [NSString stringWithFormat:@"Unsupported DID method: %@", did]}];
    }
    return nil;
}

@end
