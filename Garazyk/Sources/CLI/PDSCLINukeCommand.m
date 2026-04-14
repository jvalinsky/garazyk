#import "PDSCLIDefinitions.h"
#import "Debug/PDSLogger.h"
#import "PDSCLIInputHelper.h"

#pragma mark - Nuke Command

@interface PDSCLINukeCommand : PDSBaseCommand
@end

@implementation PDSCLINukeCommand : PDSBaseCommand

- (NSString *)name {
    return @"nuke-data";
}

- (NSString *)summary {
    return @"⚠️  DANGER: Delete all PDS data";
}

- (NSString *)usage {
    return @"kaszlak nuke-data --confirm";
}

- (NSString *)helpText {
    return @"⚠️  DANGER ZONE ⚠️\n\n"
           @"This command will DELETE ALL PDS DATA including:\n"
           @"  - All accounts\n"
           @"  - All repositories\n"
           @"  - All blobs\n"
           @"  - All databases\n\n"
           @"This action is IRREVERSIBLE!\n\n"
           @"Options:\n"
           @"  --confirm    Required to confirm deletion\n"
           @"  --keep-config    Keep configuration files";
}

- (NSArray<NSString *> *)aliases {
    return @[@"reset", @"nuke"];
}

- (int)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    BOOL confirmed = NO;
    BOOL keepConfig = NO;

    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg isEqualToString:@"--confirm"]) {
            confirmed = YES;
        } else if ([arg isEqualToString:@"--keep-config"]) {
            keepConfig = YES;
        }
    }

    if (!confirmed) {
        if ([PDSCLIInputHelper isInteractiveTTY]) {
            printf("\n");
            printf("⚠️  DANGER ZONE ⚠️\n");
            printf("================\n\n");
            printf("This command will DELETE ALL PDS DATA.\n");
            printf("This action is IRREVERSIBLE!\n\n");
            printf("Data directory: %s\n\n", [context.dataDir UTF8String]);
            
            if (![PDSCLIInputHelper promptForConfirmation:@"Permanently delete all data?" defaultYes:NO]) {
                printf("\nAborted.\n");
                return 0;
            }
            confirmed = YES;
        } else {
            printf("\n");
            printf("⚠️  DANGER ZONE ⚠️\n");
            printf("================\n\n");
            printf("This command will DELETE ALL PDS DATA.\n");
            printf("This action is IRREVERSIBLE!\n\n");
            printf("To proceed, run:\n");
            printf("  atprotopds-cli nuke-data --confirm\n\n");
            printf("Data directory: %s\n", [context.dataDir UTF8String]);
            return 0;
        }
    }

    printf("\n");
    printf("🔥 NUKING ALL DATA 🔥\n");
    printf("=====================\n\n");
    printf("Data directory: %s\n\n", [context.dataDir UTF8String]);

    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;

    // List what we're about to delete
    NSArray<NSString *> *dataFiles = @[
        @"di",           // Per-user databases
        @"blobs",        // Blob storage
        @"service",      // Service database directory
        @"sequencer",    // Sequencer database directory
        @"did_cache"     // DID cache database directory
    ];

    NSUInteger deletedCount = 0;
    NSUInteger failedCount = 0;

    for (NSString *file in dataFiles) {
        NSString *fullPath = [context.dataDir stringByAppendingPathComponent:file];
        BOOL isDirectory = NO;
        
        if ([fm fileExistsAtPath:fullPath isDirectory:&isDirectory]) {
            printf("  Deleting: %s", [file UTF8String]);
            
            if ([fm removeItemAtPath:fullPath error:&error]) {
                printf(" ✓\n");
                deletedCount++;
            } else {
                printf(" ✗ (%s)\n", [error.localizedDescription UTF8String]);
                failedCount++;
            }
        }
    }

    // Handle sqlite directories that might contain their own db files
    NSArray<NSString *> *dirs = [fm contentsOfDirectoryAtPath:context.dataDir error:nil];
    for (NSString *item in dirs) {
        // Skip config files if requested
        if (keepConfig && ([item hasSuffix:@".json"] || [item hasSuffix:@".yaml"] || [item hasSuffix:@".yml"])) {
            printf("  Keeping config: %s\n", [item UTF8String]);
            continue;
        }
        
        // Delete any remaining database files
        if ([item hasSuffix:@".db"] || [item hasSuffix:@".sqlite"] || 
            [item hasSuffix:@"-shm"] || [item hasSuffix:@"-wal"] || [item hasSuffix:@"-journal"]) {
            NSString *fullPath = [context.dataDir stringByAppendingPathComponent:item];
            printf("  Deleting: %s", [item UTF8String]);
            
            if ([fm removeItemAtPath:fullPath error:&error]) {
                printf(" ✓\n");
                deletedCount++;
            } else {
                printf(" ✗ (%s)\n", [error.localizedDescription UTF8String]);
                failedCount++;
            }
        }
    }

    printf("\n");
    printf("Summary:\n");
    printf("  Deleted: %lu items\n", (unsigned long)deletedCount);
    if (failedCount > 0) {
        printf("  Failed:  %lu items\n", (unsigned long)failedCount);
    }
    printf("\n");
    
    if (failedCount == 0) {
        printf("✅ All data has been nuked. You can now start fresh.\n");
    } else {
        printf("⚠️  Some items could not be deleted. Check permissions.\n");
    }
    return 0;
}

@end

#pragma mark - Register

@interface PDSNukeCommandRegistrar : NSObject
@end

@implementation PDSNukeCommandRegistrar

+ (void)load {
    [[PDSCLIDispatcher sharedDispatcher] addCommand:[PDSCLINukeCommand command]];
}

@end
