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
    config.plcUrl = @"https://plc.directory";
    config.serviceDomain = nil; // will be computed
    return config;
}

- (NSString *)serviceDID {
    NSString *domain = self.serviceDomain ?: [NSString stringWithFormat:@"localhost:%lu", (unsigned long)self.httpPort];
    NSString *didHost = domain;
    NSArray<NSString *> *parts = [domain componentsSeparatedByString:@":"];
    if (parts.count == 2) {
        NSString *host = parts[0];
        NSUInteger port = (NSUInteger)[parts[1] integerValue];
        if (port != 0 && port != 80 && port != 443) {
            didHost = [NSString stringWithFormat:@"%@%%3A%lu", host, (unsigned long)port];
        } else {
            didHost = host;
        }
    }
    return [NSString stringWithFormat:@"did:web:%@", didHost];
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
    if (json[@"plcUrl"]) self.plcUrl = json[@"plcUrl"];
    if (json[@"serviceDomain"]) self.serviceDomain = json[@"serviceDomain"];
    
    return YES;
}

- (void)loadFromEnvironment {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    
    if (env[@"CHAT_DATA_DIR"]) self.dataDirectory = env[@"CHAT_DATA_DIR"];
    if (env[@"CHAT_HTTP_PORT"]) self.httpPort = (NSUInteger)[env[@"CHAT_HTTP_PORT"] integerValue];
    if (env[@"CHAT_ADMIN_SECRET"]) self.adminSecret = env[@"CHAT_ADMIN_SECRET"];
    if (env[@"CHAT_PDS_URL"]) self.pdsUrl = env[@"CHAT_PDS_URL"];
    if (env[@"PDS_URL"]) self.pdsUrl = env[@"PDS_URL"];
    if (env[@"CHAT_PLC_URL"]) self.plcUrl = env[@"CHAT_PLC_URL"];
    if (env[@"PLC_URL"]) self.plcUrl = env[@"PLC_URL"];
    if (env[@"CHAT_SERVICE_DOMAIN"]) self.serviceDomain = env[@"CHAT_SERVICE_DOMAIN"];
}

@end
