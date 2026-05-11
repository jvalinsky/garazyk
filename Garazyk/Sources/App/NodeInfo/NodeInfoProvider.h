// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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
@property (nonatomic, copy, readonly) NSString *baseURL;

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

/*! Total number of registered users. */
@property (nonatomic, assign) NSUInteger totalUsers;

/*! Number of active users in the last 30 days. */
@property (nonatomic, assign) NSUInteger activeUsersMonth;

/*! Number of active users in the last 180 days. */
@property (nonatomic, assign) NSUInteger activeUsersHalfyear;

/*! Number of local posts. */
@property (nonatomic, assign) NSUInteger localPosts;

/*! Number of local comments. */
@property (nonatomic, assign) NSUInteger localComments;

/*!
 @brief Initialize with base URL and configuration.

 @param baseURL The base URL of the server (e.g., "https://pds.example.com")
 @param configuration The PDS configuration instance

 @return Initialized provider, or nil if validation fails.
 */
- (nullable instancetype)initWithBaseURL:(NSString *)baseURL
                           configuration:(PDSConfiguration *)configuration;

/*!
 @brief Refresh NodeInfo documents with current statistics.

 @discussion Call this method after updating usage properties to regenerate
 the JSON documents.
 */
- (void)refreshUsageStatistics;

@end

NS_ASSUME_NONNULL_END
