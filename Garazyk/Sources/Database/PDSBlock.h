// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 * @file PDSBlock.h
 * @abstract Represents a content block stored in the database.
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSDatabaseBlock
 
 @abstract Represents a content block stored in the database.
 
 @discussion Blocks are content-addressed data units stored in CAR format.
 Each block is identified by its CID and belongs to a specific repository.
 */
@class PDSDatabase;
@protocol PDSDatabaseModel;

@interface PDSDatabaseBlock : NSObject <PDSDatabaseModel>

/*! The CID of this block. */
@property (nonatomic, copy) NSData *cid;

/*! The DID of the repository that owns this block. */
@property (nonatomic, copy) NSString *repoDid;

/*! The serialized block data in CAR format. */
@property (nonatomic, copy, nullable) NSData *blockData;

/*! The content type of the block (e.g., application/json). */
@property (nonatomic, copy, nullable) NSString *contentType;

/*! The size of the block data in bytes. */
@property (nonatomic, assign) NSInteger size;

/*! Date when the block was stored. */
@property (nonatomic, strong) NSDate *createdAt;

/*! Revision TID when this block was first written/materialized. */
@property (nonatomic, copy, nullable) NSString *rev;

@end

NS_ASSUME_NONNULL_END
