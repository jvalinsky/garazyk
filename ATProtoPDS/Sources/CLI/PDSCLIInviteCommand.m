#import "PDSCLIDefinitions.h"
#import "Debug/PDSLogger.h"
#import "PDSCLIInputHelper.h"
#import "PDSCLIAccountManager.h"
#import "Database/PDSDatabase.h"

@interface PDSInviteInfo : NSObject
@property (nonatomic, copy) NSString *code;
@property (nonatomic, copy) NSString *createdBy;
@property (nonatomic, assign) NSInteger uses;
@property (nonatomic, assign) NSInteger maxUses;
@property (nonatomic, assign) BOOL disabled;
@property (nonatomic, copy, nullable) NSString *expiresAt;
@property (nonatomic, copy) NSString *createdAt;
@end

@implementation PDSInviteInfo
@end

@interface PDSInviteManager : NSObject

+ (NSArray<PDSInviteInfo *> *)listInvitesWithContext:(PDSCLICommandContext *)context
                                              filter:(NSString *)filter
                                         includeUsed:(BOOL)includeUsed;
+ (NSString *)createInviteWithContext:(PDSCLICommandContext *)context
                               uses:(NSInteger)uses
                             disabled:(BOOL)disabled;
+ (BOOL)revokeInviteWithContext:(PDSCLICommandContext *)context code:(NSString *)code;

@end

@implementation PDSInviteManager

+ (NSString *)databasePathForContext:(PDSCLICommandContext *)context {
    return [PDSCLIAccountManager databasePathForContext:context];
}

+ (NSArray<PDSInviteInfo *> *)listInvitesWithContext:(PDSCLICommandContext *)context
                                              filter:(NSString *)filter
                                         includeUsed:(BOOL)includeUsed {
    NSString *dbPath = [self databasePathForContext:context];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
        return @[];
    }

    NSError *error = nil;
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:&error]) {
        return @[];
    }

    NSString *sql = includeUsed
        ? @"SELECT code, account_did, uses, max_uses, disabled, created_at FROM invite_codes ORDER BY created_at DESC"
        : @"SELECT code, account_did, uses, max_uses, disabled, created_at FROM invite_codes WHERE disabled = 0 AND uses < max_uses ORDER BY created_at DESC";

    NSArray<NSDictionary *> *rows = [db executeParameterizedQuery:sql params:@[] error:&error];
    [db close];

    if (!rows) {
        return @[];
    }

    NSMutableArray<PDSInviteInfo *> *invites = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        PDSInviteInfo *info = [[PDSInviteInfo alloc] init];
        info.code = row[@"code"] ?: @"";
        info.createdBy = row[@"account_did"] ?: @"";
        info.uses = [row[@"uses"] integerValue];
        info.maxUses = [row[@"max_uses"] integerValue];
        info.disabled = [row[@"disabled"] integerValue] != 0;
        info.createdAt = row[@"created_at"] ?: @"";
        [invites addObject:info];
    }

    if (filter.length > 0) {
        [invites filterUsingPredicate:[NSPredicate predicateWithFormat:@"code CONTAINS[cd] %@", filter]];
    }

    return invites;
}

+ (NSString *)createInviteWithContext:(PDSCLICommandContext *)context
                                 uses:(NSInteger)uses
                             disabled:(BOOL)disabled {
    NSString *alphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    NSMutableString *code = [NSMutableString stringWithCapacity:19];

    for (int g = 0; g < 4; g++) {
        if (g > 0) [code appendString:@"-"];
        for (int i = 0; i < 4; i++) {
            unichar c = [alphabet characterAtIndex:arc4random_uniform((uint32_t)alphabet.length)];
            [code appendFormat:@"%C", c];
        }
    }

    NSString *dbPath = [self databasePathForContext:context];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
        PDS_LOG_ERROR(@"Database not found at %@", dbPath);
        return nil;
    }

    NSError *error = nil;
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:&error]) {
        PDS_LOG_ERROR(@"Failed to open database: %@", error.localizedDescription);
        return nil;
    }

    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    fmt.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    NSString *now = [fmt stringFromDate:[NSDate date]];

    NSString *sql = @"INSERT INTO invite_codes (id, code, account_did, created_at, uses, max_uses, disabled) "
                    @"VALUES (?, ?, ?, ?, 0, ?, ?)";
    BOOL success = [db executeParameterizedUpdate:sql
                                           params:@[uuid, code, @"admin", now, @(uses), @(disabled ? 1 : 0)]
                                            error:&error];
    [db close];

    if (!success) {
        PDS_LOG_ERROR(@"Failed to insert invite code into database: %@", error.localizedDescription);
        return nil;
    }

    if (context.verbose) {
        PDS_LOG_INFO(@"Created invite code: %@ (max_uses: %ld)", code, (long)uses);
    }

    return code;
}

+ (BOOL)revokeInviteWithContext:(PDSCLICommandContext *)context code:(NSString *)code {
    NSString *dbPath = [self databasePathForContext:context];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
        return NO;
    }

    NSError *error = nil;
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:&error]) {
        return NO;
    }

    NSString *sql = @"UPDATE invite_codes SET disabled = 1 WHERE code = ?";
    BOOL success = [db executeParameterizedUpdate:sql params:@[code] error:&error];

    if (success) {
        NSArray<NSDictionary *> *rows = [db executeParameterizedQuery:@"SELECT changes() AS cnt" params:@[] error:nil];
        if ([rows.firstObject[@"cnt"] integerValue] == 0) {
            success = NO;
        }
    }

    [db close];
    return success;
}

@end

#pragma mark - Invite Command

@interface PDSCLIInviteCommand : PDSBaseCommand
@end

@implementation PDSCLIInviteCommand : PDSBaseCommand

- (NSString *)name {
    return @"invite";
}

- (NSString *)summary {
    return @"Manage invite codes";
}

- (NSString *)usage {
    return @"pds invite <subcommand> [options]";
}

- (NSArray<NSString *> *)aliases {
    return @[ @"i", @"invite" ];
}

- (NSString *)helpText {
    return @"Manage invite codes for account registration.\n\n"
           @"Usage: pds invite <subcommand> [options]\n\n"
           @"Subcommands:\n"
           @"  list                   List all invite codes\n"
           @"  create                 Create a new invite code\n"
           @"  revoke <code>          Revoke an invite code\n\n"
           @"Examples:\n"
           @"  pds invite list                        # List all invite codes\n"
           @"  pds invite create                     # Create new invite (uses default 1 max use)\n"
           @"  pds invite create --max-uses 5         # Create invite with 5 max uses\n"
           @"  pds invite revoke ABC123              # Revoke a specific invite code";
}

- (NSArray<NSString *> *)subcommands {
    return @[@"list", @"create", @"revoke"];
}

- (int)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printInfo:[self helpText]];
        return 0;
    }

    NSString *subcommand = args[0];
    NSArray *subArgs = args.count > 1 ? [args subarrayWithRange:NSMakeRange(1, args.count - 1)] : @[];

    if ([subcommand isEqualToString:@"list"]) {
        [self executeListWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"create"]) {
        [self executeCreateWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"revoke"]) {
        [self executeRevokeWithArgs:subArgs context:context];
    } else {
        [context printError:[NSString stringWithFormat:@"Unknown subcommand: %@", subcommand]];
        return 1;
    }
    return 0;
}

- (void)executeListWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    BOOL includeUsed = NO;
    NSString *filter = @"";

    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg isEqualToString:@"--used"] || [arg isEqualToString:@"-u"]) {
            includeUsed = YES;
        } else if ([arg isEqualToString:@"--filter"] || [arg isEqualToString:@"-f"]) {
            if (i + 1 < args.count) {
                filter = args[++i];
            }
        }
    }

    NSArray<PDSInviteInfo *> *invites = [PDSInviteManager listInvitesWithContext:context
                                                                         filter:filter
                                                                    includeUsed:includeUsed];

    if (context.jsonOutput) {
        NSMutableArray *output = [NSMutableArray array];
        for (PDSInviteInfo *invite in invites) {
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            dict[@"code"] = invite.code;
            dict[@"created_by"] = invite.createdBy;
            dict[@"uses"] = @(invite.uses);
            dict[@"max_uses"] = @(invite.maxUses);
            dict[@"disabled"] = @(invite.disabled);
            dict[@"created_at"] = invite.createdAt;
            if (invite.expiresAt) dict[@"expires_at"] = invite.expiresAt;
            [output addObject:dict];
        }
        [context printJSON:output];
    } else {
        printf("%-24s %-20s %-8s %-8s %-10s %s\n", "Code", "Created By", "Uses", "Max", "Status", "Created");
        printf("%-24s %-20s %-8s %-8s %-10s %s\n", "----", "----------", "----", "---", "------", "-------");

        for (PDSInviteInfo *invite in invites) {
            NSString *status;
            if (invite.disabled) {
                status = @"disabled";
            } else if (invite.uses >= invite.maxUses) {
                status = @"used";
            } else if (invite.expiresAt) {
                status = @"valid*";
            } else {
                status = @"valid";
            }

            printf("%-24s %-20s %-8ld %-8ld %-10s %s\n",
                   [invite.code UTF8String],
                   [invite.createdBy UTF8String],
                   (long)invite.uses,
                   (long)invite.maxUses,
                   [status UTF8String],
                   [invite.createdAt UTF8String]);
        }

        printf("\n* Has expiration date\n");
        printf("Total codes: %lu\n", (unsigned long)invites.count);
    }
}

- (void)executeCreateWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    NSInteger uses = 1;
    BOOL disabled = NO;

    BOOL usesProvided = NO;
    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg isEqualToString:@"--uses"] || [arg isEqualToString:@"-u"]) {
            if (i + 1 < args.count) {
                uses = [args[++i] integerValue];
                usesProvided = YES;
            }
        } else if ([arg isEqualToString:@"--disabled"]) {
            disabled = YES;
        }
    }

    if (!usesProvided && [PDSCLIInputHelper isInteractiveTTY]) {
        NSString *input = [PDSCLIInputHelper promptForInput:@"Max uses" defaultValue:@"1"];
        uses = [input integerValue];
    }

    NSString *code = [PDSInviteManager createInviteWithContext:context uses:uses disabled:disabled];

    if (context.jsonOutput) {
        [context printJSON:@{
            @"code": code,
            @"uses": @(uses),
            @"max_uses": @(uses),
            @"disabled": @(disabled),
            @"created_by": @"admin"
        }];
    } else {
        printf("Invite code created:\n");
        printf("  Code:     %s\n", [code UTF8String]);
        printf("  Uses:     %ld / %ld\n", (long)uses, (long)uses);
        printf("  Status:   %s\n", disabled ? "disabled" : "active");
    }
}

- (void)executeRevokeWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing invite code"];
        return;
    }

    NSString *code = args[0];
    BOOL success = [PDSInviteManager revokeInviteWithContext:context code:code];

    if (success) {
        [context printInfo:@"Invite code revoked"];
    } else {
        [context printError:@"Failed to revoke invite code"];
    }
}

@end

#pragma mark - Register

@interface PDSInviteCommandRegistrar : NSObject
@end

@implementation PDSInviteCommandRegistrar

+ (void)load {
    [[PDSCLIDispatcher sharedDispatcher] addCommand:[PDSCLIInviteCommand command]];
}

@end
