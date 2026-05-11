// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "ChatConfiguration.h"

@implementation ChatConfiguration

+ (instancetype)defaultConfiguration {
    ChatConfiguration *config = [[ChatConfiguration alloc] init];
    config.dataDirectory = @"./data/chat";
    config.httpPort = 2585; // Default port for chat
    config.adminSecret = @"";
    config.pdsUrl = @"http://localhost:2583";
    return config;
}

- (BOOL)loadFromFile:(NSString *)path error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) return NO;
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!json) return NO;
    
    if (json[@"dataDirectory"]) self.dataDirectory = json[@"dataDirectory"];
    if (json[@"httpPort"]) self.httpPort = [json[@"httpPort"] unsignedIntegerValue];
    if (json[@"adminSecret"]) self.adminSecret = json[@"adminSecret"];
    if (json[@"pdsUrl"]) self.pdsUrl = json[@"pdsUrl"];
    
    return YES;
}

- (void)loadFromEnvironment {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    
    if (env[@"CHAT_DATA_DIR"]) self.dataDirectory = env[@"CHAT_DATA_DIR"];
    if (env[@"CHAT_HTTP_PORT"]) self.httpPort = (NSUInteger)[env[@"CHAT_HTTP_PORT"] integerValue];
    if (env[@"CHAT_ADMIN_SECRET"]) self.adminSecret = env[@"CHAT_ADMIN_SECRET"];
    if (env[@"PDS_URL"]) self.pdsUrl = env[@"PDS_URL"];
}

@end
