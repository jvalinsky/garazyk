#import "PDSCLIDefinitions.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/TID.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Repository/MST.h"
#import "Repository/RepoCommit.h"
#import "Debug/PDSLogger.h"
#import "App/Services/PDSRecordService.h"

@interface PDSCLIRepoCommand : PDSBaseCommand

@end

@implementation PDSCLIRepoCommand

- (NSString *)name {
    return @"repo";
}

- (NSString *)summary {
    return @"Inspect user repositories";
}

- (NSString *)usage {
    return @"pds repo <subcommand> [options]";
}

- (NSString *)helpText {
    return @"Inspect user repositories.\n\n"
           @"Usage: pds repo <subcommand> [options]\n\n"
           @"Subcommands:\n"
           @"  list <did>             List all records in the user's repository\n"
           @"  get <did> <uri>        Fetch a specific record\n"
           @"  root <did>             Return the current root CID of the repository\n"
           @"  create-record <did> <col> [rkey] <json>  Create a new record\n"
           @"  delete-record <did> <col> <rkey>         Delete a record\n"
           @"  repair <did>           Force reinitialize a corrupted repository\n\n"
           @"Examples:\n"
           @"  pds repo list did:plc:abc123           # List all records for user\n"
           @"  pds repo get did:plc:abc123 at://did:plc:abc123/app.bsky.feed.post/abc\n"
           @"  pds repo root did:plc:abc123           # Get current repo root";
}

- (NSArray<NSString *> *)subcommands {
    return @[@"list", @"get", @"root", @"create-record", @"delete-record", @"repair"];
}

- (NSArray<NSString *> *)aliases {
    return @[ @"r", @"repo" ];
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
    } else if ([subcommand isEqualToString:@"get"]) {
        [self executeGetWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"root"]) {
        [self executeRootWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"create-record"]) {
        [self executeCreateRecordWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"delete-record"]) {
        [self executeDeleteRecordWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"repair"]) {
        [self executeRepairWithArgs:subArgs context:context];
    } else {
        [context printError:[NSString stringWithFormat:@"Unknown subcommand: %@", subcommand]];
    }
    return 0;
}

- (void)executeCreateRecordWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count < 3) {
        [context printError:@"Usage: pds repo create-record <did> <collection> [rkey] <json_value>"];
        return;
    }

    NSString *did = args[0];
    NSString *collection = args[1];
    NSString *rkey = nil;
    NSString *jsonValue = nil;
    
    if (args.count >= 4) {
        rkey = args[2];
        jsonValue = args[3];
    } else {
        jsonValue = args[2];
    }
    
    if ([rkey isKindOfClass:[NSString class]]) {
        rkey = [rkey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }

    PDSDatabasePool *pool = [[PDSDatabasePool alloc] initWithDbDirectory:context.dataDir maxSize:10];
    PDSRecordService *recordService = [[PDSRecordService alloc] initWithDatabasePool:pool];
    
    NSError *jsonError = nil;
    NSData *jsonData = [jsonValue dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *value = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
    
    if (!value) {
        [context printError:[NSString stringWithFormat:@"Invalid JSON value: %@", jsonError.localizedDescription]];
        return;
    }

    if (rkey.length == 0) {
        if ([collection isEqualToString:@"app.bsky.feed.post"]) {
            NSString *createdAtString = [value[@"createdAt"] isKindOfClass:[NSString class]] ? value[@"createdAt"] : nil;
            NSDate *createdAt = [NSDateFormatter atproto_dateFromString:createdAtString];
            rkey = createdAt ? [TID tidWithDate:createdAt].stringValue : [TID tid].stringValue;
        } else {
            [context printError:@"rkey is required for non-post collections. For app.bsky.feed.post, omit rkey to auto-generate a TID."];
            return;
        }
    }

    NSError *error = nil;
    BOOL success = [recordService putRecord:collection
                                      rkey:rkey
                                     value:value
                                    forDid:did
                                  actorDid:did // Direct CLI access as actor
                            validationMode:PDSValidationModeOptimistic
                                     error:&error];

    if (success) {
        [context printInfo:[NSString stringWithFormat:@"Record created/updated successfully: at://%@/%@/%@", did, collection, rkey]];
        // Fetch the record back to show its CID
        NSDictionary *newRecord = [recordService getRecord:[NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey] forDid:did error:nil];
        if (newRecord[@"cid"]) {
            printf("CID: %s\n", [newRecord[@"cid"] UTF8String]);
        }
    } else {
        [context printError:[NSString stringWithFormat:@"Failed to create record: %@", error.localizedDescription]];
    }
}

- (void)executeDeleteRecordWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count < 3) {
        [context printError:@"Usage: pds repo delete-record <did> <collection> <rkey>"];
        return;
    }

    NSString *did = args[0];
    NSString *collection = args[1];
    NSString *rkey = args[2];

    PDSDatabasePool *pool = [[PDSDatabasePool alloc] initWithDbDirectory:context.dataDir maxSize:10];
    PDSRecordService *recordService = [[PDSRecordService alloc] initWithDatabasePool:pool];
    
    NSError *error = nil;
    BOOL success = [recordService deleteRecord:collection
                                          rkey:rkey
                                        forDid:did
                                      actorDid:did
                                         error:&error];

    if (success) {
        [context printInfo:[NSString stringWithFormat:@"Record deleted successfully: at://%@/%@/%@", did, collection, rkey]];
    } else {
        [context printError:[NSString stringWithFormat:@"Failed to delete record: %@", error.localizedDescription]];
    }
}

- (void)executeListWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing DID"];
        return;
    }

    NSString *did = args[0];
    PDSDatabasePool *pool = [[PDSDatabasePool alloc] initWithDbDirectory:context.dataDir maxSize:10];
    NSError *error = nil;

    PDSActorStore *store = [pool storeForDid:did error:&error];
    if (!store) {
        [context printError:[NSString stringWithFormat:@"Failed to open store for %@: %@", did, error.localizedDescription]];
        return;
    }

    NSArray<PDSDatabaseRecord *> *records = [store listRecordsForDid:did
                                                          collection:nil
                                                                limit:100
                                                               offset:0
                                                                error:&error];
    if (error) {
        [context printError:[NSString stringWithFormat:@"Failed to list records: %@", error.localizedDescription]];
        return;
    }

    if (context.jsonOutput) {
        NSMutableArray *output = [NSMutableArray array];
        for (PDSDatabaseRecord *record in records) {
            [output addObject:@{
                @"uri": record.uri ?: @"",
                @"cid": record.cid ?: @"",
                @"collection": record.collection ?: @"",
                @"rkey": record.rkey ?: @""
            }];
        }
        [context printJSON:output];
    } else {
        if (records.count == 0) {
            printf("No records found for DID: %s\n", [did UTF8String]);
            return;
        }

        printf("%-60s %-40s\n", "URI", "CID");
        printf("%-60s %-40s\n", "---", "---");

        for (PDSDatabaseRecord *record in records) {
            printf("%-60s %-40s\n",
                   [record.uri UTF8String],
                   [record.cid UTF8String]);
        }

        printf("\nTotal records: %lu\n", (unsigned long)records.count);
    }
}

- (void)executeGetWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count < 2) {
        [context printError:@"Usage: pds repo get <did> <uri>"];
        return;
    }

    NSString *did = args[0];
    NSString *uri = args[1];

    PDSDatabasePool *pool = [[PDSDatabasePool alloc] initWithDbDirectory:context.dataDir maxSize:10];
    NSError *error = nil;

    PDSDatabaseRecord *record = [pool getRecord:uri forDid:did error:&error];
    if (!record) {
        [context printError:[NSString stringWithFormat:@"Record not found: %@", uri]];
        return;
    }

    if (context.jsonOutput) {
        id value = nil;
        if (record.value) {
            NSData *data = [record.value dataUsingEncoding:NSUTF8StringEncoding];
            if (data) {
                value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            }
        }
        [context printJSON:@{
            @"uri": record.uri ?: @"",
            @"cid": record.cid ?: @"",
            @"collection": record.collection ?: @"",
            @"rkey": record.rkey ?: @"",
            @"value": value ?: @{}
        }];
    } else {
        printf("URI:        %s\n", [record.uri UTF8String]);
        printf("CID:        %s\n", [record.cid UTF8String]);
        printf("Collection: %s\n", [record.collection UTF8String]);
        printf("RKey:       %s\n", [record.rkey UTF8String]);
        printf("Value:      %s\n", [record.value UTF8String]);
    }
}

- (void)executeRootWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printError:@"Missing DID"];
        return;
    }

    NSString *did = args[0];
    PDSDatabasePool *pool = [[PDSDatabasePool alloc] initWithDbDirectory:context.dataDir maxSize:10];
    NSError *error = nil;

    NSData *rootCidData = [pool getRepoRoot:did error:&error];
    if (!rootCidData) {
        if (error) {
            [context printError:[NSString stringWithFormat:@"Failed to get root CID: %@", error.localizedDescription]];
        } else {
            [context printError:[NSString stringWithFormat:@"No repository found for DID: %@", did]];
        }
        return;
    }

    CID *cid = [CID cidFromBytes:rootCidData];
    NSString *cidString = cid ? [cid stringValue] : [rootCidData base64EncodedStringWithOptions:0];

    if (context.jsonOutput) {
        [context printJSON:@{
            @"did": did,
            @"rootCid": cidString ?: @""
        }];
    } else {
        printf("DID:      %s\n", [did UTF8String]);
        printf("Root CID: %s\n", [cidString UTF8String]);
    }
}

- (void)executeRepairWithArgs:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count < 1) {
        [context printError:@"Usage: pds repo repair <did>"];
        return;
    }

    NSString *did = args[0];
    
    PDSDatabasePool *pool = [[PDSDatabasePool alloc] initWithDbDirectory:context.dataDir maxSize:10];
    NSError *error = nil;
    
    PDSActorStore *store = [pool storeForDid:did error:&error];
    if (!store) {
        [context printError:[NSString stringWithFormat:@"Failed to open store for %@: %@", did, error.localizedDescription ?: @"unknown error"]];
        return;
    }
    
    printf("Clearing repo_root for %s...\n", [did UTF8String]);
    
    if (![store clearRepoRootWithError:&error]) {
        [context printError:[NSString stringWithFormat:@"Failed to clear repo_root: %@", error.localizedDescription ?: @"unknown error"]];
        return;
    }
    
    printf("Re-initializing repository...\n");
    
    // Create empty MST and commit
    MST *mst = [[MST alloc] init];
    CID *dataCID = mst.rootCID;
    if (!dataCID) {
        [context printError:@"Failed to compute empty MST root"];
        return;
    }
    
    NSString *rev = [[TID tid] stringValue];
    RepoCommit *commit = [RepoCommit createCommitWithDid:did
                                                    data:dataCID
                                                     rev:rev
                                                    prev:nil];
    
    NSData *signature = [store signData:[commit serialize] error:&error];
    if (!signature) {
        [context printError:[NSString stringWithFormat:@"Failed to sign commit: %@", error.localizedDescription ?: @"unknown error"]];
        return;
    }
    commit.signature = signature;
    
    CID *commitCID = [commit computeCID];
    NSData *commitData = [commit serializeSigned];
    if (!commitData) {
        [context printError:@"Failed to serialize commit"];
        return;
    }
    
    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    block.cid = [commitCID bytes];
    block.blockData = commitData;
    block.size = commitData.length;
    
    __block BOOL success = NO;
    [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        if (![transactor putBlock:block forDid:did error:blockError]) {
            return;
        }
        success = [transactor updateRepoRoot:did rootCid:[commitCID bytes] rev:rev error:blockError];
    } error:&error];
    
    if (!success) {
        [context printError:[NSString stringWithFormat:@"Failed to store commit: %@", error.localizedDescription ?: @"unknown error"]];
        return;
    }
    
    if (context.jsonOutput) {
        [context printJSON:@{
            @"did": did,
            @"status": @"repaired",
            @"commit": [commitCID stringValue] ?: @""
        }];
    } else {
        printf("Repository repaired successfully.\n");
        printf("DID:    %s\n", [did UTF8String]);
        printf("Commit: %s\n", [[commitCID stringValue] UTF8String]);
    }
}

@end

#pragma mark - Register

@interface PDSRepoCommandRegistrar : NSObject
@end

@implementation PDSRepoCommandRegistrar

+ (void)load {
    [[PDSCLIDispatcher sharedDispatcher] addCommand:[[PDSCLIRepoCommand alloc] init]];
}

@end
