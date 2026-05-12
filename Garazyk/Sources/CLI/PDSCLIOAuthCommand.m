// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSCLIDefinitions.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/GZLogger.h"

#pragma mark - OAuth Command

@interface PDSCLIOAuthCommand : PDSBaseCommand

@end

@implementation PDSCLIOAuthCommand

- (NSString *)name {
    return @"oauth";
}

- (NSString *)summary {
    return @"Manage OAuth clients";
}

- (NSString *)usage {
    return @"kaszlak oauth <subcommand> [options]";
}

- (NSString *)helpText {
    return @"Manage OAuth clients for ATProto authentication.\n\n"
           @"Subcommands:\n"
           @"  client register --client-id <id> --redirect-uri <uri> [--secret <secret>]\n"
           @"                         Register a new OAuth client\n"
           @"  client list             List all registered OAuth clients\n"
           @"  client delete <id>      Delete an OAuth client\n\n"
           @"Examples:\n"
           @"  kaszlak oauth client register --client-id my-app --redirect-uri http://localhost:3000/callback\n"
           @"  kaszlak oauth client list\n"
           @"  kaszlak oauth client delete my-app";
}

- (NSArray<NSString *> *)subcommands {
    return @[@"client"];
}

- (int)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printInfo:[self helpText]];
        return 0;
    }

    NSString *subcommand = args[0];
    NSArray *subArgs = args.count > 1 ? [args subarrayWithRange:NSMakeRange(1, args.count - 1)] : @[];

    if ([subcommand isEqualToString:@"client"]) {
        return [self executeClientWithArgs:subArgs context:context];
    } else {
        [context printError:[NSString stringWithFormat:@"Unknown subcommand: %@", subcommand]];
        return 1;
    }
}

- (int)executeClientWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printInfo:@"OAuth client subcommands:\n"
                       @"  register --client-id <id> --redirect-uri <uri> [--secret <secret>]\n"
                       @"  list\n"
                       @"  delete <client-id>"];
        return 0;
    }

    NSString *subcommand = args[0];
    NSArray *subArgs = args.count > 1 ? [args subarrayWithRange:NSMakeRange(1, args.count - 1)] : @[];

    if ([subcommand isEqualToString:@"register"]) {
        return [self executeClientRegisterWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"list"]) {
        return [self executeClientListWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"delete"]) {
        return [self executeClientDeleteWithArgs:subArgs context:context];
    } else {
        [context printError:[NSString stringWithFormat:@"Unknown client subcommand: %@", subcommand]];
        return 1;
    }
}

- (int)executeClientRegisterWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    NSString *clientID = nil;
    NSMutableArray *redirectURIs = [NSMutableArray array];
    NSString *secret = nil;
    NSString *scope = @"atproto";

    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg isEqualToString:@"--client-id"] || [arg isEqualToString:@"-i"]) {
            if (i + 1 < args.count) clientID = args[++i];
        } else if ([arg isEqualToString:@"--redirect-uri"] || [arg isEqualToString:@"-r"]) {
            if (i + 1 < args.count) [redirectURIs addObject:args[++i]];
        } else if ([arg isEqualToString:@"--secret"] || [arg isEqualToString:@"-s"]) {
            if (i + 1 < args.count) secret = args[++i];
        } else if ([arg isEqualToString:@"--scope"]) {
            if (i + 1 < args.count) scope = args[++i];
        }
    }

    if (!clientID) {
        [context printError:@"Missing required argument: --client-id"];
        return 1;
    }
    if (redirectURIs.count == 0) {
        [context printError:@"Missing required argument: --redirect-uri"];
        return 1;
    }

    NSError *dbError = nil;
    PDSDatabase *db = [self databaseWithContext:context error:&dbError];
    if (!db) {
        [context printError:[NSString stringWithFormat:@"Failed to open database: %@", dbError.localizedDescription]];
        return 1;
    }

    NSDictionary *client = @{
        @"client_id": clientID,
        @"redirect_uris": redirectURIs,
        @"grant_types": @"authorization_code,refresh_token",
        @"scope": scope
    };
    if (secret) {
        NSMutableDictionary *mutableClient = [client mutableCopy];
        mutableClient[@"client_secret"] = secret;
        client = mutableClient;
    }

    NSError *createError = nil;
    if ([db createClient:client error:&createError]) {
        [context printInfo:[NSString stringWithFormat:@"Registered OAuth client: %@", clientID]];
        [context printInfo:[NSString stringWithFormat:@"Redirect URIs: %@", [redirectURIs componentsJoinedByString:@", "]]];
        [db close];
        return 0;
    } else {
        [context printError:[NSString stringWithFormat:@"Failed to register client: %@", createError.localizedDescription]];
        [db close];
        return 1;
    }
}

- (int)executeClientListWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    NSError *dbError = nil;
    PDSDatabase *db = [self databaseWithContext:context error:&dbError];
    if (!db) {
        [context printError:[NSString stringWithFormat:@"Failed to open database: %@", dbError.localizedDescription]];
        return 1;
    }

    NSArray *clients = [db getAllOAuthClientsWithError:&dbError];
    [db close];

    if (context.jsonOutput) {
        [context printJSON:clients ?: @[]];
    } else {
        if (!clients || clients.count == 0) {
            [context printInfo:@"No OAuth clients registered."];
        } else {
            printf("Registered OAuth clients:\n");
            for (NSDictionary *client in clients) {
                NSString *cid = client[@"client_id"] ?: @"unknown";
                NSArray *uris = client[@"redirect_uris"] ?: @[];
                NSString *urisStr = [uris componentsJoinedByString:@", "];
                printf("  %s\n    Redirect URIs: %s\n", [cid UTF8String], [urisStr UTF8String]);
            }
        }
    }
    return 0;
}

- (int)executeClientDeleteWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing client-id argument"];
        return 1;
    }

    NSString *clientID = args[0];

    NSError *dbError = nil;
    PDSDatabase *db = [self databaseWithContext:context error:&dbError];
    if (!db) {
        [context printError:[NSString stringWithFormat:@"Failed to open database: %@", dbError.localizedDescription]];
        return 1;
    }

    NSError *deleteError = nil;
    if ([db deleteOAuthClientWithID:clientID error:&deleteError]) {
        [context printInfo:[NSString stringWithFormat:@"Deleted OAuth client: %@", clientID]];
        [db close];
        return 0;
    } else {
        [context printError:[NSString stringWithFormat:@"Failed to delete client: %@", deleteError.localizedDescription]];
        [db close];
        return 1;
    }
}

- (PDSDatabase *)databaseWithContext:(PDSCLICommandContext *)context error:(NSError **)error {
    NSString *dbPath = [context.dataDir stringByAppendingPathComponent:@"service/service.db"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSCLIOAuthCommand"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Database not found. Run 'kaszlak serve' first."}];
        }
        return nil;
    }
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:error]) {
        return nil;
    }
    return db;
}

@end

#pragma mark - Register

@interface PDSCLIOAuthCommandRegistrar : NSObject
@end

@implementation PDSCLIOAuthCommandRegistrar

+ (void)load {
    [[PDSCLIDispatcher sharedDispatcher] addCommand:[[PDSCLIOAuthCommand alloc] init]];
}

@end
