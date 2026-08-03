// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

#import "Database/ActorStore/ActorStore.h"

int main(void) {
    @autoreleasepool {
        NSString *directory = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:@"storage-link-%@", NSUUID.UUID.UUIDString]];
        NSError *error = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&error]) {
            NSLog(@"Could not create temporary directory: %@", error);
            return 1;
        }

        NSString *dbPath = [directory stringByAppendingPathComponent:@"actor.sqlite"];
        PDSActorStore *store = [PDSActorStore storeWithDid:@"did:plc:storage-link-test"
                                                     dbPath:dbPath
                                                      error:&error];
        BOOL passed = store != nil && store.keyManager != nil && store.spaceKeyManager != nil;
        if (!passed) {
            NSLog(@"Could not open ActorStore from ATProtoStorage's declared closure: %@", error);
        }
        [store close];
        [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
        return passed ? 0 : 1;
    }
}
