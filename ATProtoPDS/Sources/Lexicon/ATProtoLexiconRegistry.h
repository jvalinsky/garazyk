/*!
 @file ATProtoLexiconRegistry.h

 @abstract Registry for loading and caching lexicon schemas.

 @discussion Loads lexicon JSON files from directories and provides
 lookup by NSID. Schemas are cached in memory for performance.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ATProtoLexiconSchema;

/*!
 @class ATProtoLexiconRegistry

 @abstract Singleton registry for lexicon schemas.

 @discussion Loads and caches lexicon schemas from directories.
 Thread-safe for concurrent access.
 */
@interface ATProtoLexiconRegistry : NSObject

/*!
 @method sharedRegistry

 @abstract Returns the shared registry instance.

 @return Singleton instance.
 */
+ (instancetype)sharedRegistry;

/*!
 @method loadLexiconsFromDirectory:error:

 @abstract Recursively loads all lexicon JSON files from a directory.

 @param path Directory path to scan for *.json files.
 @param error Output parameter for loading errors.

 @return YES if all files loaded successfully, NO if any errors occurred.

 @discussion Continues loading even if some files fail to parse.
 Malformed schemas are logged but don't stop the loading process.
 */
- (BOOL)loadLexiconsFromDirectory:(NSString *)path error:(NSError **)error;

/*!
 @method loadLexiconFromFile:error:

 @abstract Loads a single lexicon file.

 @param filePath Path to lexicon JSON file.
 @param error Output parameter for loading errors.

 @return YES if loaded successfully, NO on error.
 */
- (BOOL)loadLexiconFromFile:(NSString *)filePath error:(NSError **)error;

/*!
 @method registerSchema:

 @abstract Registers a schema explicitly (useful for testing or dynamic registration).

 @param schema The schema object to register.
 */
- (void)registerSchema:(ATProtoLexiconSchema *)schema;

/*!
 @method schemaForNSID:

 @abstract Looks up a lexicon schema by NSID.

 @param nsid Namespaced identifier (e.g., "app.bsky.feed.post").

 @return Schema if found, nil otherwise.
 */
- (nullable ATProtoLexiconSchema *)schemaForNSID:(NSString *)nsid;

/*!
 @method hasSchemaForNSID:

 @abstract Checks if a schema is loaded for the given NSID.

 @param nsid Namespaced identifier.

 @return YES if schema is loaded, NO otherwise.
 */
- (BOOL)hasSchemaForNSID:(NSString *)nsid;

/*!
 @method clearCache

 @abstract Clears all loaded schemas.

 @discussion Primarily for testing. Not recommended for production use.
 */
- (void)clearCache;

/*!
 @method loadedNSIDs

 @abstract Returns all loaded NSIDs.

 @return Array of NSID strings.
 */
- (NSArray<NSString *> *)loadedNSIDs;

/*!
 @method searchPathsForDirectory:

 @abstract Returns ordered search paths for lexicon directories.

 @param dataDirectory Optional data directory to include in search paths.

 @return Array of directory paths in search order.

 @discussion Search order:
 1. PDS_LEXICON_PATH environment variable (if set)
 2. Bundle resources/lexicons
 3. Working directory variants (for development)
 4. Data directory/lexicons (if provided and exists)
 */
- (NSArray<NSString *> *)searchPathsForDirectory:(nullable NSString *)dataDirectory;

@end

NS_ASSUME_NONNULL_END
