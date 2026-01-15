#import "CLI/PDSCLIDispatcher.h"
#import "Debug/PDSLogger.h"

@implementation PDSCLICommandContext

- (instancetype)init {
    self = [super init];
    if (self) {
        _dataDir = @"./data";
        _configPath = @"./config.json";
        _verbose = NO;
        _jsonOutput = NO;
    }
    return self;
}

- (NSDictionary *)loadConfig {
    NSError *error = nil;
    NSString *configPath = self.configPath;

    if (![[NSFileManager defaultManager] fileExistsAtPath:configPath]) {
        return @{};
    }

#if defined(__APPLE__)
    NSData *data = [NSData dataWithContentsOfFile:configPath options:0 error:&error];
#else
    NSData *data = [NSData dataWithContentsOfFile:configPath];
    if (!data) {
        error = [NSError errorWithDomain:@"PDSCLI" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to read config"}];
    }
#endif
    if (error || !data) {
        [self printError:[NSString stringWithFormat:@"Failed to read config: %@", error.localizedDescription]];
        return @{};
    }

    id config = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![config isKindOfClass:[NSDictionary class]]) {
        [self printError:[NSString stringWithFormat:@"Failed to parse config: %@", error.localizedDescription]];
        return @{};
    }

    return config;
}

- (id)databaseConnection {
    return nil;
}

- (void)printError:(NSString *)error {
    if (self.jsonOutput) {
        NSError *jsonError = nil;
        NSDictionary *obj = @{@"error": error};
        NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:&jsonError];
        if (data) {
            printf("%s\n", (const char *)data.bytes);
        }
    } else {
        PDS_LOG_ERROR_C(PDSLogComponentCLI, @"Error: %@", error);
    }
}

- (void)printInfo:(NSString *)info {
    if (self.jsonOutput) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"info": info} options:0 error:nil];
        if (data) {
            printf("%s\n", (const char *)data.bytes);
        }
    } else {
        printf("%s\n", [info UTF8String]);
    }
}

- (void)printJSON:(id)object {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:&error];
    if (error) {
        [self printError:[NSString stringWithFormat:@"Failed to serialize JSON: %@", error.localizedDescription]];
    } else {
        printf("%s\n", data.bytes);
    }
}

@end

#pragma mark - Base Command

@implementation PDSBaseCommand

+ (instancetype)command {
    return [[self alloc] init];
}

- (NSString *)name {
    return @"base";
}

- (NSString *)summary {
    return @"Base command";
}

- (NSString *)usage {
    return [NSString stringWithFormat:@"pds %@", [self name]];
}

- (NSString *)helpText {
    return nil;
}

- (NSArray<NSString *> *)aliases {
    return @[];
}

- (void)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    [context printInfo:[self usage]];
}

@end

#pragma mark - Help Command

@interface PDSCLIHelpCommand : PDSBaseCommand
@end

@implementation PDSCLIHelpCommand : PDSBaseCommand

- (NSString *)name {
    return @"help";
}

- (NSString *)summary {
    return @"Show help information";
}

- (NSString *)usage {
    return @"pds help [command]";
}

- (NSString *)helpText {
    return @"Show help for pds commands. If no command is specified, show general help.";
}

- (void)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count > 0) {
        NSString *commandName = args[0];
        id<PDSCLICommand> command = [[PDSCLIDispatcher sharedDispatcher] commandForName:commandName];
        if (command) {
            [[PDSCLIDispatcher sharedDispatcher] printUsageForCommand:command];
        } else {
            [context printError:[NSString stringWithFormat:@"Unknown command: %@", commandName]];
        }
    } else {
        [[PDSCLIDispatcher sharedDispatcher] printUsage];
    }
}

@end

#pragma mark - Version Command

@interface PDSCLIVersionCommand : PDSBaseCommand
@end

@implementation PDSCLIVersionCommand : PDSBaseCommand

- (NSString *)name {
    return @"version";
}

- (NSString *)summary {
    return @"Show version information";
}

- (NSString *)usage {
    return @"pds version";
}

- (NSString *)helpText {
    return @"Show the version of the PDS software.";
}

- (void)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (context.jsonOutput) {
        [context printJSON:@{
            @"version": @"1.0.0",
            @"build": @"debug",
            @"platform": @"macOS"
        }];
    } else {
        printf("PDS Version 1.0.0 (debug build)\n");
    }
}

@end

#pragma mark - PDSCLIDispatcher

@interface PDSCLIDispatcher ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, id<PDSCLICommand>> *commands;
@end

@interface PDSCLIRepoCommand : PDSBaseCommand
@end

@implementation PDSCLIDispatcher

+ (instancetype)sharedDispatcher {
    static PDSCLIDispatcher *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSCLIDispatcher alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _commands = [NSMutableDictionary dictionary];
        [self registerDefaultCommands];
    }
    return self;
}

- (void)registerDefaultCommands {
    [self addCommand:[PDSCLIHelpCommand command]];
    [self addCommand:[PDSCLIVersionCommand command]];
}

- (void)addCommand:(id<PDSCLICommand>)command {
    self.commands[command.name] = command;
    for (NSString *alias in [command aliases]) {
        self.commands[alias] = command;
    }
}

- (id<PDSCLICommand>)commandForName:(NSString *)name {
    return self.commands[name];
}

- (void)removeCommandWithName:(NSString *)name {
    [self.commands removeObjectForKey:name];
}

- (void)dispatchWithCommandName:(NSString *)commandName
                       arguments:(NSArray<NSString *> *)args
                        context:(PDSCLICommandContext *)context {
    id<PDSCLICommand> command = self.commands[commandName];

    if (!command) {
        [context printError:[NSString stringWithFormat:@"Unknown command: %@", commandName]];
        [self printUsage];
        exit(PDSCLIExitCodeInvalidArguments);
    }

    if (context.verbose) {
        PDS_LOG_INFO(@"Executing command: %@ with args: %@", commandName, [args componentsJoinedByString:@" "]);
    }

    @try {
        [command executeWithArguments:args context:context];
    } @catch (NSException *exception) {
        [context printError:[NSString stringWithFormat:@"Command failed: %@", exception.reason]];
        exit(PDSCLIExitCodeGeneralError);
    }
}

- (void)printUsage {
    printf("Usage: pds <command> [options]\n\n");
    printf("Available commands:\n");

    NSArray *sortedKeys = [[self.commands allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableSet *seenCommands = [NSMutableSet set];

    for (NSString *key in sortedKeys) {
        if ([seenCommands containsObject:key]) continue;
        if ([key isEqualToString:[self.commands[key] name]]) {
            id<PDSCLICommand> cmd = self.commands[key];
            printf("  %-20s %s\n", [cmd.name UTF8String], [[cmd summary] UTF8String]);
            [seenCommands addObject:key];
        }
    }

    printf("\nUse 'pds help <command>' for more information about a command.\n");
}

- (void)printUsageForCommand:(id<PDSCLICommand>)command {
    printf("Usage: %s\n", [command.usage UTF8String]);
    printf("\n");
    if ([command helpText]) {
        printf("%s\n", [[command helpText] UTF8String]);
        printf("\n");
    }
    printf("Aliases: %s\n", [[[command aliases] componentsJoinedByString:@", "] UTF8String]);
}

@end

@implementation PDSCLIDispatcher (Testing)

- (void)resetCommandsToDefaults {
    [self.commands removeAllObjects];
    [self registerDefaultCommands];
}

@end

@implementation PDSCLIServiceStub

+ (instancetype)sharedStub {
    static PDSCLIServiceStub *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _serviceDid = @"did:plc:service-stub";
        _serviceHost = @"localhost";
    }
    return self;
}

- (NSDictionary *)payloadForAudience:(NSString *)audience method:(NSString *)method expiry:(NSTimeInterval)expiry {
    if (self.payloadProvider) {
        NSDictionary *custom = self.payloadProvider(audience, method, expiry);
        if (custom) return custom;
    }

    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"iss"] = self.serviceDid;
    payload[@"aud"] = audience;
    payload[@"exp"] = @((long long)expiry);
    if (method.length > 0) {
        payload[@"lxm"] = method;
    }
    payload[@"serviceHost"] = self.serviceHost;
    return payload;
}

@end
