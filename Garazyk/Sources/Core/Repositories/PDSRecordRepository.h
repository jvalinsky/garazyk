// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSRecordRepository.h
 @abstract Protocol for repository record management.
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabaseRecord;

/*!
 @protocol PDSRecordRepository
 @abstract Protocol for record CRUD operations within repositories.
 */
@protocol PDSRecordRepository <NSObject>

/*! Saves or updates a record. */
- (BOOL)saveRecord:(PDSDatabaseRecord *)record error:(NSError **)error;

/*! Retrieves a record by its AT-URI. */
- (nullable PDSDatabaseRecord *)recordForUri:(NSString *)uri error:(NSError **)error;

/*! Lists records for a DID, optionally filtered by collection. */
- (nullable NSArray<PDSDatabaseRecord *> *)recordsForDid:(NSString *)did 
                                             collection:(nullable NSString *)collection 
                                                  error:(NSError **)error;

/*! Deletes a record by URI. */
- (BOOL)deleteRecord:(NSString *)uri error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
