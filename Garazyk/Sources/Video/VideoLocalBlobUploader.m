// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/VideoLocalBlobUploader.h"
#import "Core/CID.h"

@implementation VideoLocalBlobUploader

- (instancetype)initWithBlobProvider:(id<PDSBlobProvider>)blobProvider {
    self = [super init];
    if (self) {
        _blobProvider = blobProvider;
    }
    return self;
}

- (nullable NSDictionary *)uploadBlob:(NSData *)blobData
                             mimeType:(NSString *)mimeType
                          serviceAuth:(nullable NSString *)token
                                error:(NSError **)error {
    CID *cid = [CID sha256:blobData];
    BOOL stored = [self.blobProvider storeBlobData:blobData forCID:cid error:error];
    if (!stored) {
        return nil;
    }

    return @{
        @"cid": cid.stringValue,
        @"mimeType": mimeType,
        @"size": @(blobData.length)
    };
}

@end
