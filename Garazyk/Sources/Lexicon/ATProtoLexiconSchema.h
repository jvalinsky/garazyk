// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoLexiconSchema.h

 @abstract Root lexicon schema representation.

 @discussion Represents a complete lexicon schema parsed from JSON,
 including all definitions and metadata.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ATProtoLexiconDef;

/*!
 @class ATProtoLexiconSchema

 @abstract Root lexicon schema.

 @discussion Represents a complete lexicon file with all definitions.
 Lexicon schemas define record types, XRPC methods, and other API contracts.
 */
@interface ATProtoLexiconSchema : NSObject

/*! Lexicon version (always 1). */
@property (nonatomic, assign) NSInteger lexicon;

/*! NSID of this lexicon (e.g., "app.bsky.feed.post"). */
@property (nonatomic, copy) NSString *nsid;

/*! Human-readable description. */
@property (nonatomic, copy, nullable) NSString *schemaDescription;

/*! Map of definition names to definitions. */
@property (nonatomic, strong) NSDictionary<NSString *, ATProtoLexiconDef *> *defs;

/*!
 @method schemaFromJSONData:error:

 @abstract Parses a lexicon schema from JSON data.

 @param data JSON data representing the lexicon.
 @param error Output parameter for parsing errors.

 @return ATProtoLexiconSchema instance or nil on error.
 */
+ (nullable instancetype)schemaFromJSONData:(NSData *)data error:(NSError **)error;

/*!
 @method schemaFromJSONObject:error:

 @abstract Parses a lexicon schema from JSON dictionary.

 @param json JSON dictionary representing the lexicon.
 @param error Output parameter for parsing errors.

 @return ATProtoLexiconSchema instance or nil on error.
 */
+ (nullable instancetype)schemaFromJSONObject:(NSDictionary *)json error:(NSError **)error;

/*!
 @method mainDefinition

 @abstract Returns the main definition (keyed as "main").

 @return The main definition, or nil if not found.
 */
- (nullable ATProtoLexiconDef *)mainDefinition;

/*!
 @method definitionForName:

 @abstract Returns a definition by name.

 @param name Definition name (e.g., "main", "reply", "post").

 @return The definition, or nil if not found.
 */
- (nullable ATProtoLexiconDef *)definitionForName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
