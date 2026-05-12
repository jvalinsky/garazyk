// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 * @file PDSQueryDatabase.h
 * @abstract Protocol defining common query operations for ATProto databases.
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "PDSBlock.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @protocol PDSQueryDatabase
 @abstract Abstract interface for ATProto-compatible data stores.
 */
@protocol PDSQueryDatabase <NSObject>

/*!
 @method executeParameterizedQuery:params:error:
 @abstract Execute a SELECT query with parameters.
 */
- (nullable NSArray<NSDictionary *> *)executeParameterizedQuery:(NSString *)sql 
                                                        params:(NSArray *)params 
                                                         error:(NSError **)error;

/*!
 @method executeParameterizedUpdate:params:error:
 @abstract Execute an INSERT/UPDATE/DELETE query with parameters.
 */
- (BOOL)executeParameterizedUpdate:(NSString *)sql 
                           params:(NSArray *)params 
                            error:(NSError **)error;

/*!
 @method executeUnsafeRawSQL:error:
 @abstract Execute raw SQL without parameters (UNSAFE).
 */
- (BOOL)executeUnsafeRawSQL:(NSString *)sql error:(NSError **)error;

/*!
 @method getBlockWithCid:repoDid:error:
 @abstract Retrieve a content block by CID and repo DID.
 */
- (nullable PDSDatabaseBlock *)getBlockWithCid:(NSData *)cid 
                                      repoDid:(NSString *)repoDid 
                                        error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
