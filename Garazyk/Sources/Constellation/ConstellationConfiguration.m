// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Constellation/ConstellationConfiguration.h"

@implementation ConstellationConfiguration

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _relayURLs = @[@"wss://bsky.network"];
    _dataDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Constellation"];
    _httpPort = 3210;
    _cursorCheckpointIntervalMs = 5000;
    _ingestEnabled = YES;
    return self;
}

+ (instancetype)defaultConfiguration {
    return [[self alloc] init];
}

+ (instancetype)configurationFromEnvironment {
    ConstellationConfiguration *config = [[self alloc] init];
    NSDictionary *env = [[NSProcessInfo processInfo] environment];

    NSString *relays = env[@"CONSTELLATION_RELAY_URLS"];
    if (relays.length > 0) config.relayURLs = [self splitCSV:relays];

    NSString *dataDir = env[@"CONSTELLATION_DATA_DIR"];
    if (dataDir.length > 0) config.dataDirectory = dataDir;

    NSString *port = env[@"CONSTELLATION_HTTP_PORT"];
    if (port.integerValue > 0) config.httpPort = (NSUInteger)port.integerValue;

    NSString *checkpoint = env[@"CONSTELLATION_CURSOR_CHECKPOINT_MS"];
    if (checkpoint.integerValue > 0) config.cursorCheckpointIntervalMs = (NSUInteger)checkpoint.integerValue;

    NSString *ingest = env[@"CONSTELLATION_INGEST_ENABLED"];
    if (ingest.length > 0) config.ingestEnabled = [ingest boolValue];

    return config;
}

- (void)loadFromDictionary:(NSDictionary *)dictionary {
    id relays = dictionary[@"relay_urls"] ?: dictionary[@"relays"];
    if ([relays isKindOfClass:[NSArray class]]) {
        self.relayURLs = relays;
    } else if ([relays isKindOfClass:[NSString class]]) {
        self.relayURLs = [ConstellationConfiguration splitCSV:relays];
    }

    NSString *dataDir = dictionary[@"data_directory"] ?: dictionary[@"data_dir"];
    if (dataDir.length > 0) self.dataDirectory = dataDir;

    id port = dictionary[@"http.port"] ?: dictionary[@"port"];
    if ([port isKindOfClass:[NSNumber class]]) {
        NSInteger value = [port integerValue];
        if (value >= 0 && value <= UINT16_MAX) self.httpPort = (NSUInteger)value;
    } else if ([port isKindOfClass:[NSString class]] && [(NSString *)port length] > 0) {
        NSInteger value = -1;
        NSScanner *scanner = [NSScanner scannerWithString:(NSString *)port];
        scanner.charactersToBeSkipped = nil;
        if ([scanner scanInteger:&value] && scanner.isAtEnd && value >= 0 && value <= UINT16_MAX) {
            self.httpPort = (NSUInteger)value;
        }
    }

    id checkpoint = dictionary[@"cursor.checkpoint_interval_ms"] ?: dictionary[@"checkpoint_interval_ms"];
    if ([checkpoint respondsToSelector:@selector(integerValue)] && [checkpoint integerValue] > 0) {
        self.cursorCheckpointIntervalMs = (NSUInteger)[checkpoint integerValue];
    }

    id ingest = dictionary[@"ingest.enabled"] ?: dictionary[@"ingest_enabled"];
    if (ingest) self.ingestEnabled = [ingest boolValue];
}

- (BOOL)validate:(NSError **)error {
    if (self.dataDirectory.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"ConstellationConfiguration"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"data_directory must be set"}];
        return NO;
    }
    if (self.httpPort > UINT16_MAX) {
        if (error) *error = [NSError errorWithDomain:@"ConstellationConfiguration"
                                                code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"http port must fit in uint16; 0 requests an ephemeral port"}];
        return NO;
    }
    if (self.ingestEnabled && self.relayURLs.count == 0) {
        if (error) *error = [NSError errorWithDomain:@"ConstellationConfiguration"
                                                code:3
                                            userInfo:@{NSLocalizedDescriptionKey: @"relay_urls must not be empty when ingest is enabled"}];
        return NO;
    }
    return YES;
}

+ (NSArray<NSString *> *)splitCSV:(NSString *)value {
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    for (NSString *part in [value componentsSeparatedByString:@","]) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [items addObject:trimmed];
    }
    return [items copy];
}

@end
