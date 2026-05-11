// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol VideoBlobUploader <NSObject>

- (nullable NSDictionary *)uploadBlob:(NSData *)blobData
                             mimeType:(NSString *)mimeType
                          serviceAuth:(nullable NSString *)token
                                error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
