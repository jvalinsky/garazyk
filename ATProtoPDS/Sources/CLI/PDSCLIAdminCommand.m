#import "PDSCLIDefinitions.h"
#import "Admin/PDSAdminAuth.h"
#import "CLI/PDSCLIAccountManager.h"
#import "Debug/PDSLogger.h"
#import "PDSCLIInputHelper.h"
#import "Identity/ATProtoHandleValidator.h"
#import "App/Services/PDSRecordService.h"

#pragma mark - Admin Command

@interface PDSCLIAdminCommand : PDSBaseCommand

@end

@implementation PDSCLIAdminCommand

- (NSString *)name {
    return @"admin";
}

- (NSString *)summary {
    return @"Manage PDS administrators";
}

- (NSString *)usage {
    return @"pds admin <subcommand> [options]";
}

- (NSString *)helpText {
    return @"Manage PDS administrators.\n\n"
           @"Subcommands:\n"
           @"  list                   List all administrator DIDs\n"
           @"  add <did|handle>       Grant administrator privileges to an account\n"
           @"  remove <did>          Revoke administrator privileges from an account\n"
           @"  create --email <e> --handle <h> [--password <p>]  Create a new admin account\n"
           @"  notify <did>          Notify relays about a specific account (triggers crawl)\n\n"
           @"Note: Administrative privileges allow access to the PDS dashboard and admin XRPC endpoints.";
}

- (NSArray<NSString *> *)subcommands {
    return @[@"list", @"add", @"remove", @"create", @"notify"];
}

- (int)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    // Ensure PDSAdminAuth has data directory for persistence
    [PDSAdminAuth sharedAuth].dataDirectory = context.dataDir;

    if (args.count == 0) {
        [context printInfo:[self helpText]];
        return 0;
    }

    NSString *subcommand = args[0];
    NSArray *subArgs = args.count > 1 ? [args subarrayWithRange:NSMakeRange(1, args.count - 1)] : @[];

    if ([subcommand isEqualToString:@"list"]) {
        return [self executeListWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"add"]) {
        return [self executeAddWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"remove"]) {
        return [self executeRemoveWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"create"]) {
        return [self executeCreateWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"notify"]) {
        return [self executeNotifyWithArgs:subArgs context:context];
    } else {
        [context printError:[NSString stringWithFormat:@"Unknown subcommand: %@", subcommand]];
        return 1;
    }
}

- (int)executeListWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    NSArray<NSString *> *dids = [[PDSAdminAuth sharedAuth] listAdminDids];
    
    if (context.jsonOutput) {
        [context printJSON:dids];
    } else {
        if (dids.count == 0) {
            [context printInfo:@"No administrator DIDs configured (other than the master password)."];
        } else {
            printf("Administrator DIDs:\n");
            for (NSString *did in dids) {
                printf("  %s\n", [did UTF8String]);
            }
        }
    }
    return 0;
}

- (int)executeAddWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing account DID or handle"];
        return 1;
    }

    NSString *identifier = args[0];
    PDSDatabaseAccount *account = [PDSCLIAccountManager getAccountWithContext:context identifier:identifier];
    
    if (!account) {
        [context printError:[NSString stringWithFormat:@"Account not found: %@", identifier]];
        return 1;
    }

    NSError *error = nil;
    if ([[PDSAdminAuth sharedAuth] addAdminDid:account.did error:&error]) {
        [context printInfo:[NSString stringWithFormat:@"Granted administrator privileges to %@ (%@)", account.handle, account.did]];
        return 0;
    } else {
        [context printError:[NSString stringWithFormat:@"Failed to grant admin privileges: %@", error.localizedDescription]];
        return 1;
    }
}

- (int)executeRemoveWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing account DID"];
        return 1;
    }

    NSString *did = args[0];
    NSError *error = nil;
    if ([[PDSAdminAuth sharedAuth] removeAdminDid:did error:&error]) {
        [context printInfo:[NSString stringWithFormat:@"Revoked administrator privileges from %@", did]];
        return 0;
    } else {
        [context printError:[NSString stringWithFormat:@"Failed to revoke admin privileges: %@", error.localizedDescription]];
        return 1;
    }
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
        }
    }

    if (email.length == 0 || handle.length == 0) {
        if ([PDSCLIInputHelper isInteractiveTTY]) {
            if (email.length == 0) email = [PDSCLIInputHelper promptForInput:@"Email address" defaultValue:nil];
            if (handle.length == 0) {
                NSString *hostname = [PDSCLIAccountManager pdsHostnameForContext:context];
                handle = [PDSCLIInputHelper promptForInput:[NSString stringWithFormat:@"Handle (e.g. admin.%@)", hostname] defaultValue:nil];
            }
            if (!passwordProvided) {
                password = [PDSCLIInputHelper promptForPasswordWithConfirmation:@"Password" confirmPrompt:@"Confirm Password" minLength:8 maxAttempts:3];
                passwordProvided = YES;
            }
        } else {
            [context printError:@"Missing required arguments: --email and --handle"];
            return 1;
        }
    }

    NSError *handleError = nil;
    NSString *normalizedHandle = [ATProtoHandleValidator validateAndNormalizeHandle:handle error:&handleError];
    if (!normalizedHandle) {
        [context printError:[NSString stringWithFormat:@"Invalid handle: %@", handleError.localizedDescription]];
        return 1;
    }

    if ([PDSCLIAccountManager createAccountWithContext:context email:email handle:normalizedHandle password:password]) {
        PDSDatabaseAccount *account = [PDSCLIAccountManager getAccountWithContext:context identifier:normalizedHandle];
        if (account) {
            NSError *adminError = nil;
            if ([[PDSAdminAuth sharedAuth] addAdminDid:account.did error:&adminError]) {
                [context printInfo:@"Admin account created successfully"];
                [context printInfo:[NSString stringWithFormat:@"Handle: %@", normalizedHandle]];
                [context printInfo:[NSString stringWithFormat:@"DID:    %@", account.did]];
                return 0;
            }
        }
    }

    [context printError:@"Failed to create admin account"];
    return 1;
}

- (int)executeNotifyWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing account DID"];
        return 1;
    }

    NSString *did = args[0];
    
    [context printInfo:[NSString stringWithFormat:@"Notifying relays about account: %@", did]];
    
    [[NSNotificationCenter defaultCenter]
        postNotificationName:PDSRecordDidChangeNotification
                      object:nil
                    userInfo:@{@"did" : did}];
    
    [context printInfo:@"Relay notification sent successfully"];
    return 0;
}

@end

#pragma mark - Register

@interface PDSAdminCommandRegistrar : NSObject
@end

@implementation PDSAdminCommandRegistrar

+ (void)load {
    [[PDSCLIDispatcher sharedDispatcher] addCommand:[[PDSCLIAdminCommand alloc] init]];
}

@end
