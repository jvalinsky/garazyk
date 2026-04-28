/*!
 @file OAuthServerMetadata.h

 @abstract OAuth 2.0 Authorization Server Metadata.

 @discussion Generates OAuth server metadata per RFC 8414. Provides discovery
 endpoint information for OAuth clients.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class OAuthServerMetadata

 @abstract OAuth 2.0 server metadata provider.

 @discussion Generates .well-known/oauth-authorization-server metadata
 for OAuth 2.0 client discovery per RFC 8414.
 */
@interface OAuthServerMetadata : NSObject

/*! OAuth server metadata dictionary. */
@property (nonatomic, readonly) NSDictionary *metadata;

/*! Initialize with base URL for metadata generation. */
- (instancetype)initWithBaseURL:(NSString *)baseURL;

@end

NS_ASSUME_NONNULL_END