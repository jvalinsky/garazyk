// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Core/CID.h"
#import "Repository/RepoCommit.h"

NS_ASSUME_NONNULL_BEGIN

typedef NSData * _Nullable (^PDSBlockProvider)(NSData *cidBytes);
typedef NSArray<NSData *> * _Nullable (^PDSRevisionBlockListProvider)(NSString *rev);

/**
 * @abstract Declares the FirehoseCARBuilder public API.
 */
@interface FirehoseCARBuilder : NSObject

/**
 * @abstract Performs the buildCARForCommit operation.
 */
+ (NSData *)buildCARForCommit:(RepoCommit *)commit
                          ops:(NSArray<NSDictionary *> *)ops
                blockProvider:(PDSBlockProvider)blockProvider
          revBlockListProvider:(nullable PDSRevisionBlockListProvider)revBlockListProvider;

/**
 * @abstract Performs the buildCARForSyncCommitOnly operation.
 */
+ (NSData *)buildCARForSyncCommitOnly:(RepoCommit *)commit;

@end

NS_ASSUME_NONNULL_END
