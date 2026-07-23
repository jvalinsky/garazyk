// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIBackendClient+Chat.h"
#import "AdminUIServer/UIBackendClient_Internal.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/ATProtoSafeHTTPClient.h"

@implementation UIBackendClient (Chat)

- (NSDictionary *)fetchChatConvosWithLimit:(NSUInteger)limit cursor:(NSString *)cursor {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"limit"] = [@(limit ?: 25) stringValue];
    if (cursor.length > 0) params[@"cursor"] = cursor;
    NSURL *url = [self URLByAppendingPath:@"/xrpc/chat.bsky.convo.listConvos" queryItems:params baseURL:self.configuration.chatBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.chatAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"chat_convos_failed", @"message": error.localizedDescription ?: @"Chat convos fetch failed"};
    }
    return response;
}

- (NSDictionary *)fetchChatMessagesForConvoID:(NSString *)convoID limit:(NSUInteger)limit cursor:(NSString *)cursor {
    if (!convoID.length) return @{@"error": @"convo_id_required"};
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"convoId"] = convoID;
    params[@"limit"] = [@(limit ?: 50) stringValue];
    if (cursor.length > 0) params[@"cursor"] = cursor;
    NSURL *url = [self URLByAppendingPath:@"/xrpc/chat.bsky.convo.getMessages" queryItems:params baseURL:self.configuration.chatBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.chatAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"chat_messages_failed", @"message": error.localizedDescription ?: @"Chat messages fetch failed"};
    }
    return response;
}

- (NSDictionary *)lockChatConvo:(NSString *)convoID {
    if (!convoID.length) return @{@"error": @"convo_id_required"};
    NSURL *url = [self URLByAppendingPath:@"/xrpc/chat.bsky.convo.lockConvo" queryItems:nil baseURL:self.configuration.chatBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *body = @{@"convoId": convoID};
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.chatAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"lock_convo_failed", @"message": error.localizedDescription ?: @"Lock conversation failed"};
    }
    return response;
}

@end
