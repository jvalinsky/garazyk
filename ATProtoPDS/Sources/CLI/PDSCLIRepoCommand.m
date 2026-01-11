#import "PDSCLIDefinitions.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Core/CID.h"
#import "Debug/PDSLogger.h"

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
           @"Subcommands:\n"
           @"  list <did>             List all records in the user's repository\n"
           @"  get <did> <uri>        Fetch a specific record\n"
           @"  root <did>             Return the current root CID of the repository";
}

- (NSArray<NSString *> *)subcommands {
    return @[@"list", @"get", @"root"];
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
    } else if ([subcommand isEqualToString:@"get"]) {
        [self executeGetWithArgs:subArgs context:context];
    } else if ([subcommand isEqualToString:@"root"]) {
        [self executeRootWithArgs:subArgs context:context];
    } else {
        [context printError:[NSString stringWithFormat:@"Unknown subcommand: %@", subcommand]];
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

@end
