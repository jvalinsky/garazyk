// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "XrpcGermMailboxPack.h"
#import "Germ/Server/Services/GermMailboxService.h"
#import "Chat/Server/ChatAuthManager.h"
#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/PDSLogger.h"

@interface XrpcGermMailboxPack ()
@property (nonatomic, strong) GermMailboxService *mailboxService;
@property (nonatomic, strong) ChatAuthManager *authManager;
@end

@implementation XrpcGermMailboxPack

- (instancetype)initWithMailboxService:(GermMailboxService *)mailboxService
                          authManager:(ChatAuthManager *)authManager {
    self = [super init];
    if (self) {
        _mailboxService = mailboxService;
        _authManager = authManager;
    }
    return self;
}

- (void)registerHandlersWithDispatcher:(XrpcDispatcher *)dispatcher {
    // com.germnetwork.mailbox.claimAddresses
    [dispatcher registerMethod:@"com.germnetwork.mailbox.claimAddresses"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleClaimAddresses:request response:response];
    }];

    // com.germnetwork.mailbox.deliver
    [dispatcher registerMethod:@"com.germnetwork.mailbox.deliver"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleMailboxDeliver:request response:response];
    }];

    // com.germnetwork.mailbox.poll
    [dispatcher registerMethod:@"com.germnetwork.mailbox.poll"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleMailboxPoll:request response:response];
    }];

    // com.germnetwork.rendezvous.register
    [dispatcher registerMethod:@"com.germnetwork.rendezvous.register"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleRendezvousRegister:request response:response];
    }];

    // com.germnetwork.rendezvous.deliver
    [dispatcher registerMethod:@"com.germnetwork.rendezvous.deliver"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleRendezvousDeliver:request response:response];
    }];

    PDS_LOG_INFO(@"Registered com.germnetwork.mailbox.* + com.germnetwork.rendezvous.* endpoints");
}

#pragma mark - Authentication

- (nullable NSString *)authenticateRequest:(HttpRequest *)request
                                  response:(HttpResponse *)response {
    // Reuse ChatAuthManager for JWT verification — Germ mailbox
    // uses the same auth infrastructure as chat.bsky.*
    NSString *did = [self.authManager authenticateRequest:request response:response];
    if (!did) {
        // ChatAuthManager already set the error response
        return nil;
    }
    return did;
}

#pragma mark - com.germnetwork.mailbox.claimAddresses

- (void)handleClaimAddresses:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *did = [self authenticateRequest:request response:response];
    if (!did) return;

    NSDictionary *body = request.jsonBody ?: @{};
    NSString *agentRef = body[@"agentRef"];
    NSNumber *countNum = body[@"count"];

    if (!agentRef || ![countNum isKindOfClass:[NSNumber class]]) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"InvalidRequest",
                                @"message": @"Missing agentRef or count"}];
        return;
    }

    NSInteger count = [countNum integerValue];
    if (count < 1 || count > 100) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"InvalidRequest",
                                @"message": @"Count must be between 1 and 100"}];
        return;
    }

    NSError *error = nil;
    NSArray<NSString *> *addresses = [self.mailboxService claimAddressesForAgent:agentRef
                                                                           count:count
                                                                           error:&error];
    if (!addresses) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"ClaimFailed",
                                @"message": error.localizedDescription ?: @"Failed to claim addresses"}];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{@"addresses": addresses}];
}

#pragma mark - com.germnetwork.mailbox.deliver

- (void)handleMailboxDeliver:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *did = [self authenticateRequest:request response:response];
    if (!did) return;

    NSDictionary *body = request.jsonBody ?: @{};
    NSString *address = body[@"address"];
    NSDictionary *ciphertextObj = body[@"ciphertext"];

    if (!address || !ciphertextObj) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"InvalidRequest",
                                @"message": @"Missing address or ciphertext"}];
        return;
    }

    // Decode base64-encoded ciphertext
    NSData *ciphertext = [self decodeBytesField:ciphertextObj];
    if (!ciphertext) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"InvalidRequest",
                                @"message": @"Invalid ciphertext encoding"}];
        return;
    }

    NSError *error = nil;
    BOOL delivered = [self.mailboxService deliverCiphertext:ciphertext
                                                  toAddress:address
                                                       error:&error];
    if (!delivered) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"DeliveryFailed",
                                @"message": error.localizedDescription ?: @"Delivery failed"}];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{@"delivered": @YES}];
}

#pragma mark - com.germnetwork.mailbox.poll

- (void)handleMailboxPoll:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *did = [self authenticateRequest:request response:response];
    if (!did) return;

    NSDictionary *params = request.queryParams ?: @{};
    NSString *agentRef = params[@"agentRef"];

    if (!agentRef || agentRef.length == 0) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"InvalidRequest",
                                @"message": @"Missing agentRef parameter"}];
        return;
    }

    NSError *error = nil;
    NSArray<NSDictionary *> *messages = [self.mailboxService pollMessagesForAgent:agentRef
                                                                           error:&error];
    if (!messages) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"PollFailed",
                                @"message": error.localizedDescription ?: @"Poll failed"}];
        return;
    }

    // Convert NSData ciphertexts to base64 $bytes format for JSON
    NSMutableArray *outputMessages = [NSMutableArray arrayWithCapacity:messages.count];
    for (NSDictionary *msg in messages) {
        NSData *ciphertext = msg[@"ciphertext"];
        NSString *base64 = ciphertext ? [ciphertext base64EncodedStringWithOptions:0] : @"";
        [outputMessages addObject:@{
            @"address": msg[@"address"] ?: @"",
            @"ciphertext": @{@"$bytes": base64}
        }];
    }

    response.statusCode = 200;
    [response setJsonBody:@{@"messages": outputMessages}];
}

#pragma mark - com.germnetwork.rendezvous.register

- (void)handleRendezvousRegister:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *did = [self authenticateRequest:request response:response];
    if (!did) return;

    NSDictionary *body = request.jsonBody ?: @{};
    NSString *address = body[@"address"];
    NSString *agentRef = body[@"agentRef"];
    NSNumber *epochNum = body[@"epoch"];

    if (!address || !agentRef || ![epochNum isKindOfClass:[NSNumber class]]) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"InvalidRequest",
                                @"message": @"Missing address, agentRef, or epoch"}];
        return;
    }

    NSInteger epoch = [epochNum integerValue];

    NSError *error = nil;
    BOOL registered = [self.mailboxService registerRendezvousAddress:address
                                                           forAgent:agentRef
                                                              epoch:epoch
                                                              error:&error];
    if (!registered) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"RegistrationFailed",
                                @"message": error.localizedDescription ?: @"Registration failed"}];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{@"registered": @YES}];
}

#pragma mark - com.germnetwork.rendezvous.deliver

- (void)handleRendezvousDeliver:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *did = [self authenticateRequest:request response:response];
    if (!did) return;

    NSDictionary *body = request.jsonBody ?: @{};
    NSString *address = body[@"address"];
    NSDictionary *ciphertextObj = body[@"ciphertext"];

    if (!address || !ciphertextObj) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"InvalidRequest",
                                @"message": @"Missing address or ciphertext"}];
        return;
    }

    NSData *ciphertext = [self decodeBytesField:ciphertextObj];
    if (!ciphertext) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"InvalidRequest",
                                @"message": @"Invalid ciphertext encoding"}];
        return;
    }

    NSError *error = nil;
    BOOL delivered = [self.mailboxService deliverToRendezvous:ciphertext
                                                      address:address
                                                       error:&error];
    if (!delivered) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"DeliveryFailed",
                                @"message": error.localizedDescription ?: @"Delivery failed"}];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{@"delivered": @YES}];
}

#pragma mark - Helpers

- (nullable NSData *)decodeBytesField:(id)bytesField {
    if (![bytesField isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *base64 = bytesField[@"$bytes"];
    if (![base64 isKindOfClass:[NSString class]]) {
        return nil;
    }

    // Convert base64url to standard base64
    NSMutableString *standard = [base64 mutableCopy];
    [standard replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, standard.length)];
    [standard replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, standard.length)];

    // Add padding if missing
    while (standard.length % 4 != 0) {
        [standard appendString:@"="];
    }

    return [[NSData alloc] initWithBase64EncodedString:standard options:0];
}

@end
