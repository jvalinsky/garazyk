// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSCLIDefinitions.h"
#import "PDSCLIInputHelper.h"
#import "App/PDSConfiguration.h"
#import <Foundation/Foundation.h>

#pragma mark - Init Command

@interface PDSCLIInitCommand : PDSBaseCommand
@end

@implementation PDSCLIInitCommand

- (NSString *)name {
    return @"init";
}

- (NSString *)summary {
    return @"Setup wizard to initialize PDS configuration";
}

- (NSString *)usage {
    return @"kaszlak init [--output <path>] [--force]";
}

- (NSString *)helpText {
    return @"Interactive setup wizard to create your PDS configuration file.\n\n"
           @"Usage: kaszlak init [--output <path>] [--force]\n\n"
           @"Options:\n"
           @"  --output <path>    Path to write config file (default: ./config.json)\n"
           @"  --force            Overwrite existing config without prompting\n\n"
           @"Examples:\n"
           @"  kaszlak init                        # Interactive setup wizard\n"
           @"  kaszlak init --output /etc/pds.json # Write config to custom path\n"
           @"  kaszlak init --force                # Overwrite existing config\n\n"
           @"Shell completions available in:\n"
           @"  scripts/completions/kaszlak.bash (bash)\n"
           @"  scripts/completions/kaszlak.zsh (zsh)";
}

- (int)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    NSString *outputPath = @"config.json";
    BOOL force = NO;

    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg isEqualToString:@"--output"] && i + 1 < args.count) {
            outputPath = args[++i];
        } else if ([arg isEqualToString:@"--force"]) {
            force = YES;
        }
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:outputPath] && !force) {
        if (![PDSCLIInputHelper promptForConfirmation:[NSString stringWithFormat:@"File %@ already exists. Overwrite?", outputPath] defaultYes:NO]) {
            printf("Aborted.\n");
            return 0;
        }
    }

    printf("\nWelcome to the PDS Setup Wizard!\n");
    printf("================================\n\n");
    printf("This wizard will help you generate a configuration file for your PDS.\n\n");

    // 1. Server Settings
    NSString *host = [PDSCLIInputHelper promptForInput:@"Server Host" defaultValue:@"localhost"];
    NSString *portStr = [PDSCLIInputHelper promptForInput:@"Server Port" defaultValue:@"8080"];
    NSUInteger port = (NSUInteger)[portStr integerValue];
    
    NSString *defaultDataDir = context.dataDir ?: @"./data";
    NSString *dataDir = [PDSCLIInputHelper promptForInput:@"Data Directory" defaultValue:defaultDataDir];

    // 2. PLC Settings
    NSInteger plcChoice = [PDSCLIInputHelper promptForChoice:@"PLC Directory Service"
                                                   choices:@[@"Production (plc.directory)", @"Mock", @"Custom URL"]
                                              defaultIndex:0];
    NSString *plcUrl = @"https://plc.directory";
    if (plcChoice == 1) {
        plcUrl = @"mock";
    } else if (plcChoice == 2) {
        plcUrl = [PDSCLIInputHelper promptForInput:@"Custom PLC URL" defaultValue:nil];
    }

    // 3. Email Settings
    NSInteger emailChoice = [PDSCLIInputHelper promptForChoice:@"Email Provider"
                                                      choices:@[@"None (Disabled)", @"SMTP (Unsupported)", @"Resend API"]
                                                 defaultIndex:0];
    
    NSMutableDictionary *emailConfig = [NSMutableDictionary dictionary];
    NSString *emailProvider = @"none";
    
    if (emailChoice == 1) {
        emailProvider = @"smtp";
        printf("\nWarning: SMTP delivery is not implemented. All sends will fail closed with an error.\nUse Resend API for working email delivery.\n\n");
        emailConfig[@"host"] = [PDSCLIInputHelper promptForInput:@"SMTP Host" defaultValue:@"smtp.gmail.com"];
        emailConfig[@"port"] = @([[PDSCLIInputHelper promptForInput:@"SMTP Port" defaultValue:@"587"] integerValue]);
        emailConfig[@"username"] = [PDSCLIInputHelper promptForInput:@"SMTP Username" defaultValue:nil];
        emailConfig[@"password"] = [PDSCLIInputHelper promptForPassword:@"SMTP Password"];
        emailConfig[@"use_tls"] = @([PDSCLIInputHelper promptForConfirmation:@"Use TLS?" defaultYes:YES]);
    } else if (emailChoice == 2) {
        emailProvider = @"resend";
        emailConfig[@"api_key_source"] = @"env";
        emailConfig[@"from_address"] = [PDSCLIInputHelper promptForInput:@"Email from address" defaultValue:nil];
        printf("\nNote: Resend API key will be read from PDS_RESEND_API_KEY environment variable.\n");
    }

    // 4. Registration Settings
    BOOL inviteRequired = [PDSCLIInputHelper promptForConfirmation:@"Require invite codes for registration?" defaultYes:NO];

    // Build the configuration dictionary
    NSMutableDictionary *config = [NSMutableDictionary dictionary];
    config[@"server"] = @{
        @"host": host,
        @"port": @(port),
        @"data_dir": dataDir
    };
    config[@"plc"] = @{
        @"url": plcUrl,
        @"retry_count": @5,
        @"retry_delay_ms": @2000
    };
    config[@"session"] = @{
        @"invite_code_required": @(inviteRequired),
        @"access_token_ttl_seconds": @1800,
        @"refresh_token_ttl_seconds": @2592000
    };
    
    if (![emailProvider isEqualToString:@"none"]) {
        config[@"email"] = @{
            @"provider": emailProvider,
            @"smtp": emailChoice == 1 ? emailConfig : @{},
            @"resend": emailChoice == 2 ? emailConfig : @{}
        };
    }

    // Default performance / logging sections
    config[@"database"] = @{
        @"user_pool_max_size": @200,
        @"service_pool_max_size": @20
    };
    config[@"logging"] = @{
        @"level": @"info",
        @"format": @"text"
    };

    // Serialize to JSON
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:config options:NSJSONWritingPrettyPrinted error:&error];
    if (!jsonData) {
        [context printError:[NSString stringWithFormat:@"Failed to generate JSON: %@", error.localizedDescription]];
        return 1;
    }

    // Write to file
    if (![jsonData writeToFile:outputPath options:NSDataWritingAtomic error:&error]) {
        [context printError:[NSString stringWithFormat:@"Failed to write config to %@: %@", outputPath, error.localizedDescription]];
        return 1;
    }

    printf("\n✅ Configuration written to %s\n\n", [outputPath UTF8String]);
    printf("Next steps:\n");
    int step = 1;
    printf("%d. Set your admin password: export PDS_ADMIN_PASSWORD=your_secret\n", step++);
    if (emailChoice == 2) {
        printf("%d. Set Resend API key: export PDS_RESEND_API_KEY=re_...\n", step++);
    }
    printf("%d. Start the PDS: kaszlak serve --config %s\n", step++, [outputPath UTF8String]);
    printf("%d. Create your first account: kaszlak account create\n\n", step++);

    return 0;
}

@end

#pragma mark - Register

@interface PDSInitCommandRegistrar : NSObject
@end

@implementation PDSInitCommandRegistrar

+ (void)load {
    [[PDSCLIDispatcher sharedDispatcher] addCommand:[[PDSCLIInitCommand alloc] init]];
}

@end
