// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler_Internal.h"

NS_ASSUME_NONNULL_BEGIN

@interface OAuth2Handler (ClientMetadataFetch)
- (void)fetchClientMetadataFromURL:(NSString *)url
                        completion:(void (^)(NSDictionary *_Nullable metadata,
                                             NSError *_Nullable error))completion;
- (NSDictionary *)parseClientMetadataFromInput:(id)clientMetadataInput;
@end

NS_ASSUME_NONNULL_END
