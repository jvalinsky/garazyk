// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewGenericIndexer.h

 @abstract Generic record indexer for lexicon-driven collections.

 @discussion Falls back when no domain-specific indexer claims a collection.
 Validates records against the lexicon schema, then stores in the generic
 records table. Domain-specific indexers (FeedIndexer, GraphIndexer, etc.)
 take priority — the generic indexer only claims collections that have a
 loaded lexicon with a record definition AND no domain-specific indexer
 claims them.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "AppView/Server/Indexers/AppViewIndexer.h"

NS_ASSUME_NONNULL_BEGIN

@class ATProtoLexiconRegistry;
@class AppViewDatabase;
@class ATProtoLexiconValidator;

/*!
 @class AppViewGenericIndexer

 @abstract Generic record indexer for third-party lexicon collections.
 */
@interface AppViewGenericIndexer : NSObject <AppViewIndexer>

/*!
 @method initWithRegistry:database:validator:domainIndexerCollections:

 @abstract Initialize the generic indexer.

 @param registry                The lexicon registry for schema lookups.
 @param database                The AppView database for record storage.
 @param validator               The lexicon validator for record validation.
 @param domainIndexerCollections  Set of collections claimed by domain-specific indexers.
                                 The generic indexer will not claim these.
 */
- (instancetype)initWithRegistry:(ATProtoLexiconRegistry *)registry
                         database:(AppViewDatabase *)database
                       validator:(ATProtoLexiconValidator *)validator
       domainIndexerCollections:(NSSet<NSString *> *)domainIndexerCollections;

/*!
 @method addDomainIndexerCollection:

 @abstract Add a collection that should not be claimed by the generic indexer.

 @param collection The collection NSID to exclude.
 */
- (void)addDomainIndexerCollection:(NSString *)collection;

@end

NS_ASSUME_NONNULL_END
