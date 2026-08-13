// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MediaCore/ATProtoCAMediaDenylist.h"
#import "Core/CID.h"
#import "Compat/PDSTypes.h"

@interface ATProtoCAMediaDenylistMemory ()
@property (nonatomic, strong) NSMutableSet<NSString *> *deniedCIDs;
@property (nonatomic, strong) NSMutableSet<NSString *> *deniedRecordURIs;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t queue;
@end

@implementation ATProtoCAMediaDenylistMemory

- (instancetype)init {
    self = [super init];
    if (self) {
        _deniedCIDs = [NSMutableSet set];
        _deniedRecordURIs = [NSMutableSet set];
        _queue = dispatch_queue_create("com.atproto.ca.denylist", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)isDeniedCID:(ATProtoCID *)cid {
    if (![cid isKindOfClass:[ATProtoCID class]]) {
        return NO;
    }
    __block BOOL denied = NO;
    NSString *key = cid.stringValue;
    dispatch_sync(self.queue, ^{
        denied = [self.deniedCIDs containsObject:key];
    });
    return denied;
}

- (BOOL)isDeniedRecordURI:(nullable NSString *)recordURI {
    if (recordURI.length == 0) {
        return NO;
    }
    __block BOOL denied = NO;
    dispatch_sync(self.queue, ^{
        denied = [self.deniedRecordURIs containsObject:recordURI];
    });
    return denied;
}

- (void)denyCID:(ATProtoCID *)cid {
    if (![cid isKindOfClass:[ATProtoCID class]]) {
        return;
    }
    dispatch_sync(self.queue, ^{
        [self.deniedCIDs addObject:cid.stringValue];
    });
}

- (void)allowCID:(ATProtoCID *)cid {
    if (![cid isKindOfClass:[ATProtoCID class]]) {
        return;
    }
    dispatch_sync(self.queue, ^{
        [self.deniedCIDs removeObject:cid.stringValue];
    });
}

- (void)denyRecordURI:(NSString *)recordURI {
    if (recordURI.length == 0) {
        return;
    }
    dispatch_sync(self.queue, ^{
        [self.deniedRecordURIs addObject:recordURI];
    });
}

- (void)allowRecordURI:(NSString *)recordURI {
    if (recordURI.length == 0) {
        return;
    }
    dispatch_sync(self.queue, ^{
        [self.deniedRecordURIs removeObject:recordURI];
    });
}

@end
