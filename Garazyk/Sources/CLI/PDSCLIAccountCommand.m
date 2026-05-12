// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSCLIDefinitions.h"
#import "Debug/GZLogger.h"
#import "PDSCLIInputHelper.h"
#import "Database/PDSDatabase.h"
#import "App/PDSConfiguration.h"
#import "CLI/PDSCLIAccountManager.h"
#import "Identity/ATProtoHandleValidator.h"

#ifndef kCCSuccess
#define kCCSuccess 0
#endif

#pragma mark - Account Command

@interface PDSCLIAccountCommand : PDSBaseCommand

@end

@implementation PDSCLIAccountCommand

- (NSString *)name {
    return @"account";
}

- (NSString *)summary {
    return @"Manage PDS accounts";
}

- (NSString *)usage {
    return @"kaszlak account <subcommand> [options]";
}

- (NSString *)helpText {
    return @"Manage PDS accounts.\n\n"
           @"Usage: kaszlak account <subcommand> [options]\n\n"
           @"Subcommands:\n"
           @"  list                   List all accounts\n"
           @"  info <did|handle>      Show account details\n"
           @"  create --email <email> --handle <handle> [--password <pw>]  Create a new account\n"
           @"  deactivate <did>       Deactivate an account\n"
           @"  reactivate <did>       Reactivate a deactivated account\n"
           @"  delete <did>           Permanently delete an account\n"
           @"  update-email <did> <email>  Update account email\n"
           @"  update-handle <did> <handle>  Update account handle\n"
           @"  update-plc-endpoint <did> <endpoint>  Update the account PLC service endpoint\n\n"
           @"Options for 'list':\n"
           @"  --limit, -l <n>        Limit results (default: 100)\n"
           @"  --filter, -f <text>    Filter by handle, email, or DID\n\n"
           @"Examples:\n"
           @"  kaszlak account list                      # List all accounts\n"
           @"  kaszlak account list --limit 10           # List first 10 accounts\n"
           @"  kaszlak account create --email a@b.com --handle test.mypds.xyz --password secret\n"
           @"  kaszlak account info did:plc:abc123       # Show account details";
}

- (NSArray<NSString *> *)aliases {
    return @[ @"a", @"account" ];
}

- (NSArray<NSString *> *)subcommands {
    return @[@"list", @"info", @"create", @"deactivate", @"reactivate", @"delete", @"update-email", @"update-handle", @"update-plc-endpoint"];
}

- (int)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printInfo:[self helpText]];
        return 0;
    }

    NSString *subcommand = args[0];
    NSArray *subArgs = args.count > 1 ? [args subarrayWithRange:NSMakeRange(1, args.count - 1)] : @[];

    if ([subcommand isEqualToString:@"list"]) {
        return [self executeListWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"info"]) {
        return [self executeInfoWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"create"]) {
        return [self executeCreateWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"deactivate"]) {
        return [self executeDeactivateWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"reactivate"]) {
        return [self executeReactivateWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"delete"]) {
        return [self executeDeleteWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"update-email"]) {
        return [self executeUpdateEmailWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"update-handle"]) {
        return [self executeUpdateHandleWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"update-plc-endpoint"]) {
        return [self executeUpdatePlcEndpointWithArgs:subArgs context:context];
    } else {
        [context printError:[NSString stringWithFormat:@"Unknown subcommand: %@", subcommand]];
        return 1;
    }
}

- (int)executeListWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    NSInteger limit = 100;
    NSString *filter = @"";

    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg isEqualToString:@"--limit"] || [arg isEqualToString:@"-l"]) {
            if (i + 1 < args.count) {
                limit = [args[++i] integerValue];
            }
        } else if ([arg isEqualToString:@"--filter"] || [arg isEqualToString:@"-f"]) {
            if (i + 1 < args.count) {
                filter = args[++i];
            }
        }
    }

    NSArray<PDSDatabaseAccount *> *accounts = [PDSCLIAccountManager listAccountsWithContext:context
                                                                                  filter:filter
                                                                                  limit:limit];

    if (context.jsonOutput) {
        NSMutableArray *output = [NSMutableArray array];
        for (PDSDatabaseAccount *account in accounts) {
            [output addObject:@{
                @"did": account.did ?: @"",
                @"handle": account.handle ?: @"",
                @"email": account.email ?: @"",
                @"created_at": @(account.createdAt),
                @"updated_at": @(account.updatedAt)
            }];
        }
        [context printJSON:output];
    } else {
        if (accounts.count == 0) {
            NSString *hostname = [PDSCLIAccountManager pdsHostnameForContext:context];
            GZ_LOG_INFO(@"No accounts found in database");
            [context printInfo:@"No accounts found."];
            [context printInfo:@"\nTo create your first account, run:"];
            [context printInfo:[NSString stringWithFormat:@"  kaszlak account create --email you@example.com --handle yourhandle.%@", hostname]];
            [context printInfo:@"\nFor testing, you can use the .test TLD:"];
            [context printInfo:@"  kaszlak account create -e test@test.com -h testuser.test"];
            return 0;
        }
        printf("%-44s %-30s %-30s %s\n", "DID", "Handle", "Email", "Created");
        printf("%-44s %-30s %-30s %s\n", "----", "------", "-----", "-------");

        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm";

        for (PDSDatabaseAccount *account in accounts) {
            NSDate *created = [NSDate dateWithTimeIntervalSince1970:account.createdAt];
            printf("%-44s %-30s %-30s %s\n",
                   [account.did UTF8String],
                   [account.handle UTF8String],
                   [account.email ? account.email : @"<none>" UTF8String],
                   [[formatter stringFromDate:created] UTF8String]);
        }

        printf("\nTotal accounts: %lu\n", (unsigned long)accounts.count);
    }
    return 0;
}

- (int)executeInfoWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing account identifier"];
        [context printInfo:@"\nUsage: kaszlak account info <did|handle>"];
        NSString *hostname = [PDSCLIAccountManager pdsHostnameForContext:context];
        [context printInfo:@"\nExamples:"];
        [context printInfo:@"  kaszlak account info did:plc:abc123"];
        [context printInfo:[NSString stringWithFormat:@"  kaszlak account info username.%@", hostname]];
        return 1;
    }

    NSString *identifier = args[0];
    PDSDatabaseAccount *account = [PDSCLIAccountManager getAccountWithContext:context identifier:identifier];

    if (!account) {
        GZ_LOG_WARN(@"Account not found: %@", identifier);
        [context printError:[NSString stringWithFormat:@"Account not found: %@", identifier]];
        [context printInfo:@"\nTo find accounts, run:"];
        [context printInfo:@"  kaszlak account list"];
        return 1;
    }

    if (context.jsonOutput) {
        [context printJSON:@{
            @"did": account.did ?: @"",
            @"handle": account.handle ?: @"",
            @"email": account.email ?: @"",
            @"created_at": @(account.createdAt),
            @"updated_at": @(account.updatedAt)
        }];
    } else {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss Z";
        NSDate *created = [NSDate dateWithTimeIntervalSince1970:account.createdAt];
        NSDate *updated = [NSDate dateWithTimeIntervalSince1970:account.updatedAt];

        printf("Account Information:\n");
        printf("  DID:        %s\n", [account.did UTF8String]);
        printf("  Handle:     %s\n", [account.handle UTF8String]);
        printf("  Email:      %s\n", [account.email ?: @"<none>" UTF8String]);
        printf("  Created:    %s\n", [[formatter stringFromDate:created] UTF8String]);
        printf("  Updated:    %s\n", [[formatter stringFromDate:updated] UTF8String]);
    }
    return 0;
}

- (int)executeCreateWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    NSString *email = @"";
    NSString *handle = @"";
    NSString *password = @"";

    BOOL passwordProvided = NO;

    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg isEqualToString:@"--email"] || [arg isEqualToString:@"-e"]) {
            if (i + 1 < args.count) email = args[++i];
        } else if ([arg isEqualToString:@"--handle"] || [arg isEqualToString:@"-h"]) {
            if (i + 1 < args.count) handle = args[++i];
        } else if ([arg isEqualToString:@"--password"] || [arg isEqualToString:@"-p"]) {
            if (i + 1 < args.count) {
                password = args[++i];
                passwordProvided = YES;
            }
        } else if ([arg isEqualToString:@"--verbose"] || [arg isEqualToString:@"-v"]) {
            context.verbose = YES;
            [[GZLogger sharedLogger] setLogLevel:GZLogLevelDebug];
        }
    }
    
    if (email.length == 0 || handle.length == 0 || !passwordProvided) {
        if ([PDSCLIInputHelper isInteractiveTTY]) {
            if (email.length == 0) {
                email = [PDSCLIInputHelper promptForInput:@"Email address" defaultValue:nil];
                if (email.length == 0) return 1;
            }
            if (handle.length == 0) {
                NSString *hostname = [PDSCLIAccountManager pdsHostnameForContext:context];
                NSString *prompt = [NSString stringWithFormat:@"Handle (e.g. user.%@)", hostname];
                handle = [PDSCLIInputHelper promptForInput:prompt defaultValue:nil];
                if (handle.length == 0) return 1;
            }
            if (!passwordProvided) {
                password = [PDSCLIInputHelper promptForPasswordWithConfirmation:@"Password"
                                                                   confirmPrompt:@"Confirm Password"
                                                                        minLength:8
                                                                      maxAttempts:3];
                if (password.length == 0) return 1;
            }
        } else if (email.length == 0 || handle.length == 0 || !passwordProvided) {
            [context printError:@"Missing required arguments: --email and --handle"];
            NSString *hostname = [PDSCLIAccountManager pdsHostnameForContext:context];
            [context printInfo:@"\nUsage: kaszlak account create --email <email> --handle <handle> [--password <pw>]"];
            [context printInfo:[NSString stringWithFormat:@"\nExamples:"]];
            [context printInfo:[NSString stringWithFormat:@"  kaszlak account create --email alice@example.com --handle alice.%@", hostname]];
            [context printInfo:@"  kaszlak account create -e bob@test.com -h bob.test -p secret123"];
            return 1;
        }
    }

    NSError *emailError = nil;
    if (![ATProtoHandleValidator validateEmail:email error:&emailError]) {
        [context printError:[NSString stringWithFormat:@"Invalid email: %@", emailError.localizedDescription]];
        if (emailError.userInfo[NSLocalizedRecoverySuggestionErrorKey]) {
            [context printInfo:emailError.userInfo[NSLocalizedRecoverySuggestionErrorKey]];
        }
        return 1;
    }

    NSError *handleError = nil;
    NSString *normalizedHandle = [ATProtoHandleValidator validateAndNormalizeHandle:handle error:&handleError];
    if (!normalizedHandle) {
        [context printError:[NSString stringWithFormat:@"Invalid handle '%@': %@", handle, handleError.localizedDescription]];
        if (handleError.userInfo[NSLocalizedRecoverySuggestionErrorKey]) {
            [context printInfo:handleError.userInfo[NSLocalizedRecoverySuggestionErrorKey]];
        }
        NSString *hostname = [PDSCLIAccountManager pdsHostnameForContext:context];
        [context printInfo:[NSString stringWithFormat:@"\nValid handle formats:"]];
        [context printInfo:[NSString stringWithFormat:@"  username.%@       (uses this PDS)", hostname]];
        [context printInfo:@"  bob.test              (test TLD for development)"];
        [context printInfo:@"  carol.com             (any valid domain)"];
        return 1;
    }

    BOOL success = [PDSCLIAccountManager createAccountWithContext:context
                                                          email:email
                                                         handle:normalizedHandle
                                                       password:password];

    if (success) {
        GZ_LOG_INFO(@"Account created successfully: %@", normalizedHandle);
        [context printInfo:@"Account created successfully"];
        [context printInfo:[NSString stringWithFormat:@"Handle: %@", normalizedHandle]];
        [context printInfo:[NSString stringWithFormat:@"Email: %@", email]];
        return 0;
    } else {
        NSString *dbPath = [PDSCLIAccountManager databasePathForContext:context];
        if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
            GZ_LOG_ERROR(@"Database not found at %@", dbPath);
            [context printError:@"Database not found. Make sure the PDS data directory exists."];
            [context printInfo:[NSString stringWithFormat:@"Expected database at: %@", dbPath]];
        } else {
            GZ_LOG_ERROR(@"Failed to create account for handle: %@", normalizedHandle);
            [context printError:@"Failed to create account"];
            [context printInfo:@"Possible causes:"];
            [context printInfo:@"  - Handle already in use"];
            [context printInfo:@"  - Email already registered"];
            [context printInfo:@"  - Database error"];
        }
        return 1;
    }
}

- (int)executeDeactivateWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing account DID"];
        return 1;
    }

    NSString *did = args[0];
    BOOL success = [PDSCLIAccountManager deactivateAccountWithContext:context did:did];

    if (success) {
        [context printInfo:@"Account deactivated"];
        return 0;
    } else {
        [context printError:@"Failed to deactivate account"];
        return 1;
    }
}

- (int)executeReactivateWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing account DID"];
        return 1;
    }

    NSString *did = args[0];
    BOOL success = [PDSCLIAccountManager reactivateAccountWithContext:context did:did];

    if (success) {
        [context printInfo:@"Account reactivated"];
        return 0;
    } else {
        [context printError:@"Failed to reactivate account"];
        return 1;
    }
}

- (int)executeDeleteWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing account DID"];
        return 1;
    }

    NSString *did = args[0];
    BOOL success = [PDSCLIAccountManager deleteAccountWithContext:context did:did];

    if (success) {
        [context printInfo:@"Account deleted"];
        return 0;
    } else {
        [context printError:@"Failed to delete account"];
        return 1;
    }
}

- (int)executeUpdateEmailWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count < 2) {
        [context printError:@"Missing arguments: --update-email <did> <email>"];
        [context printInfo:@"\nUsage: kaszlak account update-email <did> <new-email>"];
        [context printInfo:@"\nExample:"];
        [context printInfo:@"  kaszlak account update-email did:plc:abc123 newemail@example.com"];
        return 1;
    }

    NSString *did = args[0];
    NSString *email = args[1];

    NSError *emailError = nil;
    if (![ATProtoHandleValidator validateEmail:email error:&emailError]) {
        [context printError:[NSString stringWithFormat:@"Invalid email: %@", emailError.localizedDescription]];
        if (emailError.userInfo[NSLocalizedRecoverySuggestionErrorKey]) {
            [context printInfo:emailError.userInfo[NSLocalizedRecoverySuggestionErrorKey]];
        }
        return 1;
    }

    BOOL success = [PDSCLIAccountManager updateEmailWithContext:context did:did email:email];

    if (success) {
        GZ_LOG_INFO(@"Email updated for account %@: %@", did, email);
        [context printInfo:@"Email updated successfully"];
        [context printInfo:[NSString stringWithFormat:@"New email: %@", email]];
        return 0;
    } else {
        GZ_LOG_ERROR(@"Failed to update email for account %@", did);
        [context printError:@"Failed to update email"];
        [context printInfo:@"Possible causes:"];
        [context printInfo:@"  - Account not found"];
        [context printInfo:@"  - Database error"];
        return 1;
    }
}

- (int)executeUpdatePlcEndpointWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count < 2) {
        [context printError:@"Missing arguments: update-plc-endpoint <did> <endpoint>"];
        [context printInfo:@"\nUsage: kaszlak account update-plc-endpoint <did> <new-endpoint>"];
        [context printInfo:@"\nExample:"];
        [context printInfo:@"  kaszlak account update-plc-endpoint did:plc:abc123 http://127.0.0.1:8002"];
        return 1;
    }

    NSString *did = args[0];
    NSString *newEndpoint = args[1];

    BOOL success = [PDSCLIAccountManager updatePlcEndpointWithContext:context did:did newEndpoint:newEndpoint];

    if (success) {
        [context printInfo:@"PLC endpoint updated successfully"];
        return 0;
    } else {
        [context printError:@"Failed to update PLC endpoint"];
        return 1;
    }
}

- (int)executeUpdateHandleWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count < 2) {
        [context printError:@"Missing arguments: --update-handle <did> <handle>"];
        [context printInfo:@"\nUsage: kaszlak account update-handle <did> <new-handle>"];
        [context printInfo:@"\nExample:"];
        [context printInfo:@"  kaszlak account update-handle did:plc:abc123 newhandle.example.com"];
        return 1;
    }

    NSString *did = args[0];
    NSString *handle = args[1];

    NSError *handleError = nil;
    NSString *normalizedHandle = [ATProtoHandleValidator validateAndNormalizeHandle:handle error:&handleError];
    if (!normalizedHandle) {
        [context printError:[NSString stringWithFormat:@"Invalid handle '%@': %@", handle, handleError.localizedDescription]];
        if (handleError.userInfo[NSLocalizedRecoverySuggestionErrorKey]) {
            [context printInfo:handleError.userInfo[NSLocalizedRecoverySuggestionErrorKey]];
        }
        return 1;
    }

    BOOL success = [PDSCLIAccountManager updateHandleWithContext:context did:did handle:normalizedHandle];

    if (success) {
        GZ_LOG_INFO(@"Handle updated for account %@: %@", did, normalizedHandle);
        [context printInfo:@"Handle updated successfully"];
        [context printInfo:[NSString stringWithFormat:@"New handle: %@", normalizedHandle]];
        return 0;
    } else {
        GZ_LOG_ERROR(@"Failed to update handle for account %@", did);
        [context printError:@"Failed to update handle"];
        [context printInfo:@"Possible causes:"];
        [context printInfo:@"  - Account not found"];
        [context printInfo:@"  - Handle already in use by another account"];
        [context printInfo:@"  - Database error"];
        return 1;
    }
}

@end

#pragma mark - Register

@interface PDSAccountCommandRegistrar : NSObject
@end

@implementation PDSAccountCommandRegistrar

+ (void)load {
    [[PDSCLIDispatcher sharedDispatcher] addCommand:[[PDSCLIAccountCommand alloc] init]];
}

@end
