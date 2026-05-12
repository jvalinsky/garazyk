// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "XrpcGermIdentityPack.h"
#import "Germ/Server/Identity/GermIdentityService.h"
#import "Chat/Server/ChatAuthManager.h"
#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/GZLogger.h"

@interface XrpcGermIdentityPack ()
@property (nonatomic, strong) GermIdentityService *identityService;
@property (nonatomic, strong) ChatAuthManager *authManager;
@end

@implementation XrpcGermIdentityPack

- (instancetype)initWithIdentityService:(GermIdentityService *)identityService
                            authManager:(ChatAuthManager *)authManager {
    self = [super init];
    if (self) {
        _identityService = identityService;
        _authManager = authManager;
    }
    return self;
}

- (void)registerHandlersWithDispatcher:(XrpcDispatcher *)dispatcher {
    // com.germnetwork.identity.getAnchorKey
    [dispatcher registerMethod:@"com.germnetwork.identity.getAnchorKey"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleGetAnchorKey:request response:response];
    }];

    GZ_LOG_INFO(@"Registered com.germnetwork.identity.* endpoints");
}

#pragma mark - Authentication

- (nullable NSString *)authenticateRequest:(HttpRequest *)request
                                  response:(HttpResponse *)response {
    NSString *did = [self.authManager authenticateRequest:request response:response];
    if (!did) {
        return nil;
    }
    return did;
}

#pragma mark - com.germnetwork.identity.getAnchorKey

- (void)handleGetAnchorKey:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *did = [self authenticateRequest:request response:response];
    if (!did) return;

    NSDictionary *params = request.queryParams ?: @{};
    NSString *targetDid = params[@"did"];

    if (!targetDid || targetDid.length == 0) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"InvalidRequest",
                                @"message": @"Missing did parameter"}];
        return;
    }

    NSError *error = nil;
    NSData *anchorKey = [self.identityService getAnchorKeyForDid:targetDid
                                                          error:&error];
    if (!anchorKey) {
        response.statusCode = 404;
        [response setJsonBody:@{@"error": @"NotFound",
                                @"message": error.localizedDescription ?: @"No anchor key found for DID"}];
        return;
    }

    // Parse the algorithm byte from the TypedKeyMaterial
    const uint8_t *bytes = (const uint8_t *)anchorKey.bytes;
    NSString *algorithm = @"unknown";
    if (bytes[0] == 0x03) {
        algorithm = @"curve25519Signing";
    }

    // Get key history
    NSArray<NSData *> *keyHistory = [self.identityService getKeyHistoryForDid:targetDid
                                                                        error:nil] ?: @[];

    // Convert key history to base64 $bytes format
    NSMutableArray *historyArray = [NSMutableArray arrayWithCapacity:keyHistory.count];
    for (NSData *keyData in keyHistory) {
        [historyArray addObject:@{@"$bytes": [keyData base64EncodedStringWithOptions:0]}];
    }

    NSString *anchorKeyBase64 = [anchorKey base64EncodedStringWithOptions:0];

    response.statusCode = 200;
    [response setJsonBody:@{
        @"anchorKey": @{@"$bytes": anchorKeyBase64},
        @"algorithm": algorithm,
        @"keyHistory": historyArray
    }];
}

@end
