// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRepositoryService_Internal.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Repository/CAR.h"
#import "Repository/STAR.h"
#import "Core/CID.h"
#import "Debug/GZLogger.h"
#import "Core/Repositories/PDSBlockRepository.h"
#import "Core/Repositories/PDSRepoRepository.h"

#import "PDSRepositoryService+MST.h"
#import "PDSRepositoryService+Export.h"
#import "PDSRepositoryService+Commit.h"
#import "PDSRepositoryService+RecordMaterializer.h"
#import "PDSRepositoryService+RepoInit.h"

@implementation PDSRepositoryService

#pragma mark - Initialization

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool {
    if (self = [super init]) {
        self.databasePool = databasePool;
    }
    return self;
}

#pragma mark - Repo Operations

- (nullable NSData *)getBlocksForDid:(NSString *)did cids:(NSArray<NSString *> *)cids error:(NSError **)error {
    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) return nil;
    
    CID *rootCid = nil;
    if (cids.count > 0) {
        rootCid = [CID cidFromString:cids.firstObject];
    }
    
    CARWriter *writer = [CARWriter writerWithRootCID:rootCid];
    
    __block BOOL success = YES;
    
    for (NSString *cidStr in cids) {
        CID *cid = [CID cidFromString:cidStr];
        if (!cid) continue;
        
        PDSDatabaseBlock *block = [self.blockRepository blockWithCid:cid.bytes repoDid:did error:nil];
        if (block && block.blockData) {
            [writer addBlock:[CARBlock blockWithCID:cid data:block.blockData]];
        }
    }
    
    if (!success) return nil;
    return [writer serialize];
}

#pragma mark - Repo Import

- (BOOL)updateRepo:(NSString *)did commit:(NSData *)commitData error:(NSError **)error {
    if (STARDetectFormatFromData(commitData)) {
        NSError *starErr = nil;
        NSData *carData = [STARConverter carDataFromSTARData:commitData error:&starErr];
        if (!carData) {
            if (error) *error = starErr ?: [NSError errorWithDomain:@"com.atproto.repo"
                                                               code:7
                                                           userInfo:@{NSLocalizedDescriptionKey: @"Failed to convert STAR to CAR"}];
            return NO;
        }
        return [self updateRepo:did commit:carData error:error];
    }
    return NO;
}

@end
