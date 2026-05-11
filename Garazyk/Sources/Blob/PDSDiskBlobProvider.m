// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDiskBlobProvider.h"
#import "Debug/PDSLogger.h"
#import "Compat/Foundation/NSDataCompat.h"

NSString * const PDSDiskBlobProviderErrorDomain = @"com.atproto.pds.diskblobprovider";

@interface PDSDiskBlobProvider ()
@property (nonatomic, strong) NSFileManager *fileManager;
@end

@implementation PDSDiskBlobProvider

- (instancetype)initWithStorageDirectory:(NSURL *)storageDirectory {
    self = [super init];
    if (self) {
        _storageDirectory = storageDirectory;
        _fileManager = [NSFileManager defaultManager];
        
        // Ensure directory exists
        NSError *error = nil;
        if (![_fileManager createDirectoryAtURL:storageDirectory
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:&error]) {
            PDS_LOG_ERROR_C(PDSLogComponentBlob, @"Failed to create blob storage directory: %@", error);
        }
    }
    return self;
}

- (BOOL)storeBlobData:(NSData *)data forCID:(CID *)cid error:(NSError **)error {
    NSURL *blobURL = [self blobURLForCID:cid];
    NSURL *dirURL = [blobURL URLByDeletingLastPathComponent];
    
    // Ensure parent directory exists (we shard by prefix)
    NSError *dirError = nil;
    if (![_fileManager createDirectoryAtURL:dirURL
                 withIntermediateDirectories:YES
                                  attributes:nil
                                       error:&dirError]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDiskBlobProviderErrorDomain
                                         code:1
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Failed to create blob directory",
                NSUnderlyingErrorKey: dirError
            }];
        }
        return NO;
    }
    
    return [data writeToURL:blobURL options:NSDataWritingAtomic error:error];
}

- (nullable NSData *)retrieveBlobDataForCID:(CID *)cid error:(NSError **)error {
    NSURL *blobURL = [self blobURLForCID:cid];
    
    if (![_fileManager fileExistsAtPath:blobURL.path]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDiskBlobProviderErrorDomain
                                         code:2 // FileNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Blob file not found on disk"}];
        }
        return nil;
    }
    
    // Efficiently load data (mapped if possible)
    return [NSData dataWithContentsOfURL:blobURL options:NSDataReadingMappedIfSafe error:error];
}

- (nullable NSInputStream *)retrieveBlobStreamForCID:(CID *)cid error:(NSError **)error {
    NSURL *blobURL = [self blobURLForCID:cid];
    if (![_fileManager fileExistsAtPath:blobURL.path]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDiskBlobProviderErrorDomain
                                         code:2 // FileNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Blob file not found on disk"}];
        }
        return nil;
    }
    return [NSInputStream inputStreamWithURL:blobURL];
}

- (BOOL)deleteBlobDataForCID:(CID *)cid error:(NSError **)error {
    NSURL *blobURL = [self blobURLForCID:cid];
    
    // If it doesn't exist, we consider deletion successful (idempotent)
    if (![_fileManager fileExistsAtPath:blobURL.path]) {
        return YES;
    }
    
    return [_fileManager removeItemAtURL:blobURL error:error];
}

- (BOOL)hasBlobDataForCID:(CID *)cid {
    NSURL *blobURL = [self blobURLForCID:cid];
    return [_fileManager fileExistsAtPath:blobURL.path];
}

- (nullable NSURL *)blobFileURLForCID:(CID *)cid error:(NSError **)error {
    NSURL *blobURL = [self blobURLForCID:cid];
    if (![_fileManager fileExistsAtPath:blobURL.path]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDiskBlobProviderErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Blob file not found on disk"}];
        }
        return nil;
    }
    return blobURL;
}

#pragma mark - Helper

- (NSURL *)blobURLForCID:(CID *)cid {
    NSString *cidString = cid.stringValue;
    
    if (cidString.length < 3) {
        return [_storageDirectory URLByAppendingPathComponent:cidString];
    }
    
    // Shard by first 2 chars
    NSString *dirName = [cidString substringToIndex:2];
    NSString *fileName = [cidString substringFromIndex:2];
    
    NSURL *dirURL = [_storageDirectory URLByAppendingPathComponent:dirName];
    return [dirURL URLByAppendingPathComponent:fileName];
}

- (nullable NSArray<CID *> *)listAllCIDsWithError:(NSError **)error {
    NSMutableArray *cids = [NSMutableArray array];
    
    // Disk storage is sharded: /storage/aa/bbccddeeff
    // We need to iterate over all 2-char directories
    NSArray *dirEntries = [_fileManager contentsOfDirectoryAtURL:_storageDirectory
                                     includingPropertiesForKeys:nil
                                                        options:0
                                                          error:error];
    if (!dirEntries) return nil;
    
    for (NSURL *dirURL in dirEntries) {
        BOOL isDir = NO;
        if ([_fileManager fileExistsAtPath:dirURL.path isDirectory:&isDir] && isDir) {
            NSArray *fileEntries = [_fileManager contentsOfDirectoryAtURL:dirURL
                                             includingPropertiesForKeys:nil
                                                                options:0
                                                                  error:nil];
            if (!fileEntries) continue;
            
            for (NSURL *fileURL in fileEntries) {
                NSString *dirName = dirURL.lastPathComponent;
                NSString *fileName = fileURL.lastPathComponent;
                
                // Only treat 2-char directory as sharded part
                if (dirName.length != 2) continue;
                
                NSString *cidString = [dirName stringByAppendingString:fileName];
                CID *cid = [CID cidFromString:cidString];
                if (cid) {
                    [cids addObject:cid];
                }
            }
        }
    }
    
    return cids;
}

@end
