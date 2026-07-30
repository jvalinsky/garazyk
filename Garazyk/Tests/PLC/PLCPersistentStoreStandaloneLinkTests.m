// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
// Standalone link coverage for ATProtoPLC's public dependency closure.

#import <Foundation/Foundation.h>
#import "PLC/PLCPersistentStore.h"

static void RemoveDatabaseArtifacts(NSString *path) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:path error:nil];
    [fileManager removeItemAtPath:[path stringByAppendingString:@"-wal"] error:nil];
    [fileManager removeItemAtPath:[path stringByAppendingString:@"-shm"] error:nil];
}

int main(void) {
    @autoreleasepool {
        NSString *path = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:@"plc-standalone-%@.db", NSUUID.UUID.UUIDString]];
        RemoveDatabaseArtifacts(path);

        NSError *error = nil;
        PLCPersistentStore *store = [PLCPersistentStore storeWithPath:path error:&error];
        if (store == nil || !store.isOpen) {
            NSLog(@"PLCPersistentStore standalone link test failed to open: %@", error);
            RemoveDatabaseArtifacts(path);
            return 1;
        }

        [store close];
        RemoveDatabaseArtifacts(path);
        NSLog(@"PLCPersistentStore standalone link test passed");
    }
    return 0;
}
