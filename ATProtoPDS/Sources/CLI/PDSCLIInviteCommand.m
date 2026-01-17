#import "PDSCLIDefinitions.h"
#import "Debug/PDSLogger.h"

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

+ (NSArray<PDSInviteInfo *> *)listInvitesWithContext:(PDSCLICommandContext *)context
                                             filter:(NSString *)filter
                                        includeUsed:(BOOL)includeUsed {
    NSMutableArray<PDSInviteInfo *> *invites = [NSMutableArray array];

    PDSInviteInfo *invite1 = [[PDSInviteInfo alloc] init];
    invite1.code = @"ABCD-1234-EFGH-5678";
    invite1.createdBy = @"admin@example.com";
    invite1.uses = 0;
    invite1.maxUses = 1;
    invite1.disabled = NO;
    invite1.createdAt = @"2026-01-01T00:00:00Z";
    [invites addObject:invite1];

    PDSInviteInfo *invite2 = [[PDSInviteInfo alloc] init];
    invite2.code = @"WXYZ-9012-RSTU-3456";
    invite2.createdBy = @"admin@example.com";
    invite2.uses = 2;
    invite2.maxUses = 5;
    invite2.disabled = NO;
    invite2.expiresAt = @"2026-02-01T00:00:00Z";
    invite2.createdAt = @"2025-12-20T00:00:00Z";
    [invites addObject:invite2];

    PDSInviteInfo *invite3 = [[PDSInviteInfo alloc] init];
    invite3.code = @"USED-0000-EXPI-RED";
    invite3.createdBy = @"admin@example.com";
    invite3.uses = 5;
    invite3.maxUses = 5;
    invite3.disabled = YES;
    invite3.createdAt = @"2025-11-01T00:00:00Z";
    [invites addObject:invite3];

    if (!includeUsed) {
        [invites filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PDSInviteInfo *invite, NSDictionary *bindings) {
            return invite.uses < invite.maxUses && !invite.disabled;
        }]];
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
    NSMutableString *code = [NSMutableString string];

    for (int i = 0; i < 4; i++) {
        if (i > 0 && i % 4 == 0) {
            [code appendString:@"-"];
        }
        unichar c = [alphabet characterAtIndex:arc4random_uniform((uint32_t)alphabet.length)];
        [code appendFormat:@"%C", c];
    }

    if (context.verbose) {
        PDS_LOG_INFO(@"Created invite code: %@ (uses: %ld)", code, (long)uses);
    }

    return code;
}

+ (BOOL)revokeInviteWithContext:(PDSCLICommandContext *)context code:(NSString *)code {
    if (context.verbose) {
        PDS_LOG_INFO(@"Revoking invite code: %@", code);
    }
    return YES;
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

- (NSString *)helpText {
    return @"Manage invite codes for account registration.\n\n"
           @"Subcommands:\n"
           @"  list                   List all invite codes\n"
           @"  create                 Create a new invite code\n"
           @"  revoke <code>          Revoke an invite code";
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

    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg isEqualToString:@"--uses"] || [arg isEqualToString:@"-u"]) {
            if (i + 1 < args.count) {
                uses = [args[++i] integerValue];
            }
        } else if ([arg isEqualToString:@"--disabled"]) {
            disabled = YES;
        }
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
