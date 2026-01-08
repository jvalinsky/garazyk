#import "PDSCLIDefinitions.h"
#import "Debug/PDSLogger.h"
#import "Database/PDSDatabase.h"
#import "Database/Schema.h"

@interface PDSAccountManager : NSObject

+ (NSArray<PDSDatabaseAccount *> *)listAccountsWithContext:(PDSCLICommandContext *)context
                                                   filter:(NSString *)filter
                                                   limit:(NSInteger)limit;
+ (nullable PDSDatabaseAccount *)getAccountWithContext:(PDSCLICommandContext *)context
                                             identifier:(NSString *)identifier;
+ (BOOL)createAccountWithContext:(PDSCLICommandContext *)context
                           email:(NSString *)email
                         handle:(NSString *)handle
                       password:(NSString *)password;
+ (BOOL)deactivateAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did;
+ (BOOL)reactivateAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did;
+ (BOOL)deleteAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did;
+ (BOOL)updateEmailWithContext:(PDSCLICommandContext *)context
                            did:(NSString *)did
                          email:(NSString *)email;
+ (BOOL)updateHandleWithContext:(PDSCLICommandContext *)context
                             did:(NSString *)did
                          handle:(NSString *)handle;

+ (NSString *)databasePathForContext:(PDSCLICommandContext *)context;

@end

@implementation PDSAccountManager

+ (NSString *)databasePathForContext:(PDSCLICommandContext *)context {
    NSDictionary *config = [context loadConfig];
    NSString *dataDir = context.dataDir;
    if (config[@"pds"][@"data_dir"]) {
        dataDir = config[@"pds"][@"data_dir"];
    }
    return [dataDir stringByAppendingPathComponent:@"pds.db"];
}

+ (NSArray<PDSDatabaseAccount *> *)listAccountsWithContext:(PDSCLICommandContext *)context
                                                   filter:(NSString *)filter
                                                   limit:(NSInteger)limit {
    NSMutableArray<PDSDatabaseAccount *> *accounts = [NSMutableArray array];

    NSString *dbPath = [self databasePathForContext:context];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
        if (context.verbose) {
            PDS_LOG_WARN(@"Database not found at %@", dbPath);
        }
        return @[];
    }

    NSError *error = nil;
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:&error]) {
        if (context.verbose) {
            PDS_LOG_ERROR(@"Failed to open database: %@", error.localizedDescription);
        }
        return @[];
    }

    NSString *sql = @"SELECT * FROM accounts ORDER BY created_at DESC";
    if (limit > 0) {
        sql = [NSString stringWithFormat:@"%@ LIMIT %ld", sql, (long)limit];
    }

    NSArray *rows = [db executeQuery:sql error:&error];
    if (error) {
        if (context.verbose) {
            PDS_LOG_ERROR(@"Failed to query accounts: %@", error.localizedDescription);
        }
        [db close];
        return @[];
    }

    for (NSDictionary *row in rows) {
        PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
        account.did = row[@"did"];
        account.handle = row[@"handle"];
        account.email = row[@"email"];
        account.createdAt = [row[@"created_at"] doubleValue];
        account.updatedAt = [row[@"updated_at"] doubleValue];

        if (filter.length > 0) {
            BOOL matches = NO;
            if ([account.handle containsString:filter] ||
                [account.email containsString:filter] ||
                [account.did containsString:filter]) {
                matches = YES;
            }
            if (!matches) continue;
        }

        [accounts addObject:account];
    }

    [db close];
    return accounts;
}

+ (nullable PDSDatabaseAccount *)getAccountWithContext:(PDSCLICommandContext *)context
                                             identifier:(NSString *)identifier {
    NSString *dbPath = [self databasePathForContext:context];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
        return nil;
    }

    NSError *error = nil;
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:&error]) {
        return nil;
    }

    PDSDatabaseAccount *account = [db getAccountByDid:identifier error:&error];
    if (!account || error) {
        account = [db getAccountByHandle:identifier error:&error];
    }

    [db close];
    return account;
}

+ (BOOL)createAccountWithContext:(PDSCLICommandContext *)context
                           email:(NSString *)email
                         handle:(NSString *)handle
                       password:(NSString *)password {
    NSString *dbPath = [self databasePathForContext:context];

    NSError *error = nil;
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:&error]) {
        if (context.verbose) {
            PDS_LOG_ERROR(@"Failed to open database: %@", error.localizedDescription);
        }
        return NO;
    }

    if (context.verbose) {
        PDS_LOG_INFO(@"Creating account: email=%@, handle=%@", email, handle);
    }

    PDSDatabaseAccount *existing = [db getAccountByHandle:handle error:&error];
    if (existing) {
        if (context.verbose) {
            PDS_LOG_WARN(@"Account with handle %@ already exists", handle);
        }
        [db close];
        return NO;
    }

    NSString *did = [self generatePlcDid];
    if (context.verbose) {
        PDS_LOG_INFO(@"Generated DID: %@", did);
    }

    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = did;
    account.handle = handle;
    account.email = email;
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = account.createdAt;

    BOOL success = [db createAccount:account error:&error];
    if (!success) {
        if (context.verbose) {
            PDS_LOG_ERROR(@"Failed to create account: %@", error.localizedDescription);
        }
    }

    [db close];
    return success;
}

+ (NSString *)generatePlcDid {
    NSString *alphabet = @"abcdefghijklmnopqrstuvwxyz234567";
    NSMutableString *identifier = [NSMutableString stringWithCapacity:24];
    for (int i = 0; i < 24; i++) {
        unichar c = [alphabet characterAtIndex:arc4random_uniform((uint32_t)alphabet.length)];
        [identifier appendFormat:@"%C", c];
    }
    return [NSString stringWithFormat:@"did:plc:%@", identifier];
}

+ (BOOL)isValidPlcDid:(NSString *)did {
    if (![did hasPrefix:@"did:plc:"]) {
        return NO;
    }
    
    NSString *idPart = [did substringFromIndex:8];
    if (idPart.length != 24) {
        return NO;
    }
    
    NSCharacterSet *validChars = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz234567"];
    NSCharacterSet *inputChars = [NSCharacterSet characterSetWithCharactersInString:idPart];
    
    return [validChars isSupersetOfSet:inputChars];
}

+ (BOOL)deactivateAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did {
    if (context.verbose) {
        PDS_LOG_INFO(@"Deactivating account: %@", did);
    }
    return YES;
}

+ (BOOL)reactivateAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did {
    if (context.verbose) {
        PDS_LOG_INFO(@"Reactivating account: %@", did);
    }
    return YES;
}

+ (BOOL)deleteAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did {
    NSString *dbPath = [self databasePathForContext:context];

    NSError *error = nil;
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:&error]) {
        return NO;
    }

    BOOL success = [db deleteAccount:did error:&error];
    if (context.verbose) {
        if (success) {
            PDS_LOG_INFO(@"Deleted account: %@", did);
        } else {
            PDS_LOG_ERROR(@"Failed to delete account: %@", error.localizedDescription);
        }
    }

    [db close];
    return success;
}

+ (BOOL)updateEmailWithContext:(PDSCLICommandContext *)context
                            did:(NSString *)did
                          email:(NSString *)email {
    NSString *dbPath = [self databasePathForContext:context];

    NSError *error = nil;
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:&error]) {
        return NO;
    }

    PDSDatabaseAccount *account = [db getAccountByDid:did error:&error];
    if (!account) {
        [db close];
        return NO;
    }

    account.email = email;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    BOOL success = [db updateAccount:account error:&error];

    [db close];
    return success;
}

+ (BOOL)updateHandleWithContext:(PDSCLICommandContext *)context
                             did:(NSString *)did
                          handle:(NSString *)handle {
    NSString *dbPath = [self databasePathForContext:context];

    NSError *error = nil;
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:&error]) {
        return NO;
    }

    PDSDatabaseAccount *account = [db getAccountByDid:did error:&error];
    if (!account) {
        [db close];
        return NO;
    }

    account.handle = handle;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    BOOL success = [db updateAccount:account error:&error];

    [db close];
    return success;
}

@end

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
    return @"pds account <subcommand> [options]";
}

- (NSString *)helpText {
    return @"Manage PDS accounts.\n\n"
           @"Subcommands:\n"
           @"  list                   List all accounts\n"
           @"  info <did|handle>      Show account details\n"
           @"  create                 Create a new account\n"
           @"  deactivate <did>       Deactivate an account\n"
           @"  reactivate <did>       Reactivate a deactivated account\n"
           @"  delete <did>           Permanently delete an account\n"
           @"  update-email <did> <email>  Update account email\n"
           @"  update-handle <did> <handle>  Update account handle";
}

- (NSArray<NSString *> *)aliases {
    return @[];
}

- (NSArray<NSString *> *)subcommands {
    return @[@"list", @"info", @"create", @"deactivate", @"reactivate", @"delete", @"update-email", @"update-handle"];
}

- (void)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printInfo:[self helpText]];
        return;
    }

    NSString *subcommand = args[0];
    NSArray *subArgs = args.count > 1 ? [args subarrayWithRange:NSMakeRange(1, args.count - 1)] : @[];

    if ([subcommand isEqualToString:@"list"]) {
        [self executeListWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"info"]) {
        [self executeInfoWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"create"]) {
        [self executeCreateWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"deactivate"]) {
        [self executeDeactivateWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"reactivate"]) {
        [self executeReactivateWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"delete"]) {
        [self executeDeleteWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"update-email"]) {
        [self executeUpdateEmailWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"update-handle"]) {
        [self executeUpdateHandleWithArgs:subArgs context:context];
    } else {
        [context printError:[NSString stringWithFormat:@"Unknown subcommand: %@", subcommand]];
    }
}

- (void)executeListWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
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

    NSArray<PDSDatabaseAccount *> *accounts = [PDSAccountManager listAccountsWithContext:context
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
            printf("No accounts found.\n");
            return;
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
}

- (void)executeInfoWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing account identifier"];
        return;
    }

    NSString *identifier = args[0];
    PDSDatabaseAccount *account = [PDSAccountManager getAccountWithContext:context identifier:identifier];

    if (!account) {
        [context printError:[NSString stringWithFormat:@"Account not found: %@", identifier]];
        return;
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
}

- (void)executeCreateWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    NSString *email = @"";
    NSString *handle = @"";
    NSString *password = @"";

    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg isEqualToString:@"--email"] || [arg isEqualToString:@"-e"]) {
            if (i + 1 < args.count) email = args[++i];
        } else if ([arg isEqualToString:@"--handle"] || [arg isEqualToString:@"-h"]) {
            if (i + 1 < args.count) handle = args[++i];
        } else if ([arg isEqualToString:@"--password"] || [arg isEqualToString:@"-p"]) {
            if (i + 1 < args.count) password = args[++i];
        }
    }

    if (email.length == 0 || handle.length == 0) {
        [context printError:@"Missing required arguments: --email and --handle"];
        return;
    }

    BOOL success = [PDSAccountManager createAccountWithContext:context
                                                        email:email
                                                      handle:handle
                                                    password:password];

    if (success) {
        [context printInfo:@"Account created successfully"];
    } else {
        [context printError:@"Failed to create account"];
    }
}

- (void)executeDeactivateWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing account DID"];
        return;
    }

    NSString *did = args[0];
    BOOL success = [PDSAccountManager deactivateAccountWithContext:context did:did];

    if (success) {
        [context printInfo:@"Account deactivated"];
    } else {
        [context printError:@"Failed to deactivate account"];
    }
}

- (void)executeReactivateWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing account DID"];
        return;
    }

    NSString *did = args[0];
    BOOL success = [PDSAccountManager reactivateAccountWithContext:context did:did];

    if (success) {
        [context printInfo:@"Account reactivated"];
    } else {
        [context printError:@"Failed to reactivate account"];
    }
}

- (void)executeDeleteWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing account DID"];
        return;
    }

    NSString *did = args[0];
    BOOL success = [PDSAccountManager deleteAccountWithContext:context did:did];

    if (success) {
        [context printInfo:@"Account deleted"];
    } else {
        [context printError:@"Failed to delete account"];
    }
}

- (void)executeUpdateEmailWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count < 2) {
        [context printError:@"Missing arguments: --update-email <did> <email>"];
        return;
    }

    NSString *did = args[0];
    NSString *email = args[1];
    BOOL success = [PDSAccountManager updateEmailWithContext:context did:did email:email];

    if (success) {
        [context printInfo:@"Email updated"];
    } else {
        [context printError:@"Failed to update email"];
    }
}

- (void)executeUpdateHandleWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count < 2) {
        [context printError:@"Missing arguments: --update-handle <did> <handle>"];
        return;
    }

    NSString *did = args[0];
    NSString *handle = args[1];
    BOOL success = [PDSAccountManager updateHandleWithContext:context did:did handle:handle];

    if (success) {
        [context printInfo:@"Handle updated"];
    } else {
        [context printError:@"Failed to update handle"];
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
