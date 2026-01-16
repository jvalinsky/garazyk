/*!
 @file NodeInfoProvider.h

 @abstract NodeInfo metadata provider.

 @discussion Generates NodeInfo 2.0 and 2.1 schema documents and discovery
 endpoint responses. Follows the pattern established by OAuthServerMetadata.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class PDSConfiguration;

NS_ASSUME_NONNULL_BEGIN

/*!
 @class NodeInfoProvider

 @abstract NodeInfo metadata document provider.

 @discussion Generates NodeInfo schema documents and discovery responses
 for the ATProtoPDS server.
 */
@interface NodeInfoProvider : NSObject

/*! Base URL for generating href links in discovery document. */
@property (nonatomic, readonly) NSString *baseURL;

/*! Server configuration. */
@property (nonatomic, readonly) PDSConfiguration *configuration;

/*! NodeInfo 2.0 discovery document (JRD with links). */
@property (nonatomic, readonly) NSDictionary *discoveryDocument20;

/*! NodeInfo 2.1 discovery document (JRD with links). */
@property (nonatomic, readonly) NSDictionary *discoveryDocument21;

/*! NodeInfo 2.0 schema document. */
@property (nonatomic, readonly) NSDictionary *nodeInfo20;

/*! NodeInfo 2.1 schema document. */
@property (nonatomic, readonly) NSDictionary *nodeInfo21;

/*!
 @brief Initialize with base URL and configuration.

 @param baseURL The base URL of the server (e.g., "https://pds.example.com")
 @param configuration The PDS configuration instance

 @return Initialized provider, or nil if validation fails.
 */
- (nullable instancetype)initWithBaseURL:(NSString *)baseURL
                          configuration:(PDSConfiguration *)configuration;

/*!
 @brief Refresh usage statistics from database.

 @discussion Call this method to update the usage counts returned in
 the NodeInfo document. Expensive database queries should not be called
 on every request.
 */
- (void)refreshUsageStatistics;

/*!
 @brief Get total number of registered users.

 @return Total user count, or 0 if unknown.
 */
- (NSUInteger)totalUsers;

/*!
 @brief Get number of active users in the last 30 days.

 @return Active user count, or 0 if unknown.
 */
- (NSUInteger)activeUsersMonth;

/*!
 @brief Get number of active users in the last 180 days.

 @return Active user count, or 0 if unknown.
 */
- (NSUInteger)activeUsersHalfyear;

/*!
 @brief Get number of local posts.

 @return Post count, or 0 if unknown.
 */
- (NSUInteger)localPosts;

/*!
 @brief Get number of local comments.

 @return Comment count, or 0 if unknown.
 */
- (NSUInteger)localComments;

@end

NS_ASSUME_NONNULL_END
