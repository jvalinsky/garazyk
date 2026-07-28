// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewGenericIndexer.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Indexers/AppViewGenericIndexer.h"
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/Config/AppViewCollectionFilter.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Lexicon/ATProtoLexiconSchema.h"
#import "Lexicon/ATProtoLexiconDef.h"
#import "Lexicon/ATProtoLexiconValidator.h"
#import "Debug/GZLogger.h"

@interface AppViewGenericIndexer ()

@property (nonatomic, strong) ATProtoLexiconRegistry *registry;
@property (nonatomic, strong) AppViewDatabase *database;
@property (nonatomic, strong) ATProtoLexiconValidator *validator;
@property (nonatomic, strong) NSMutableSet<NSString *> *domainIndexerCollections;

@end

@implementation AppViewGenericIndexer

- (instancetype)initWithRegistry:(ATProtoLexiconRegistry *)registry
                         database:(AppViewDatabase *)database
                       validator:(ATProtoLexiconValidator *)validator
       domainIndexerCollections:(NSSet<NSString *> *)domainIndexerCollections {
    self = [super init];
    if (self) {
        _registry = registry;
        _database = database;
        _validator = validator;
        _domainIndexerCollections = [NSMutableSet setWithSet:domainIndexerCollections];
    }
    return self;
}

- (void)addDomainIndexerCollection:(NSString *)collection {
    if (collection) {
        [self.domainIndexerCollections addObject:collection];
    }
}

#pragma mark - AppViewIndexer

- (BOOL)canIndexCollection:(NSString *)collection {
    if (!collection) return NO;

    // Collection allowlist filter (S2 scoping)
    if (self.collectionFilter && ![self.collectionFilter shouldIndexCollection:collection]) {
        return NO;
    }

    // Don't claim collections that domain-specific indexers handle
    if ([self.domainIndexerCollections containsObject:collection]) {
        return NO;
    }

    // Only claim collections that have a loaded lexicon with a record definition
    ATProtoLexiconSchema *schema = [self.registry schemaForNSID:collection];
    if (!schema) return NO;

    ATProtoLexiconDef *mainDef = [schema definitionForName:@"main"];
    if (!mainDef) return NO;

    return mainDef.type == ATProtoLexiconDefTypeRecord;
}

- (BOOL)indexRecord:(NSDictionary *)record
                did:(NSString *)did
         collection:(NSString *)collection
               rkey:(NSString *)rkey
                cid:(nullable NSString *)cid
              error:(NSError **)error {
    if (!record || !did || !collection) {
        if (error) {
            *error = [NSError errorWithDomain:@"AppViewGenericIndexer"
                                         code:400
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Missing required parameters"
            }];
        }
        return NO;
    }

    // Validate against lexicon schema
    if (self.validator) {
        NSError *validationError = nil;
        BOOL valid = [self.validator validateRecord:record
                                        collection:collection
                                              mode:ATProtoValidationModeOptimistic
                                             error:&validationError];
        if (!valid && validationError) {
            GZ_LOG_DEBUG(@"[GenericIndexer] Validation failed for %@ in %@: %@",
                          collection, did, validationError.localizedDescription);
            // In optimistic mode, we still index even if the schema is unknown
            // but we log validation failures for known schemas
            if ([self.registry hasSchemaForNSID:collection]) {
                // Known schema but validation failed — still store (optimistic)
                // but record in dead-letter if the error is severe
                if (validationError.code != 0) {
                    [self.database recordDeadLetterEvent:collection
                                                    seq:0
                                                    did:did
                                                    rev:nil
                                                    cid:cid
                                              rawRecord:[NSJSONSerialization dataWithJSONObject:record options:0 error:nil]
                                        validationError:validationError.localizedDescription
                                                  error:nil];
                }
            }
        }
    }

    // Use the rkey parameter (passed from ingest/backfill), or fall back to record data
    NSString *effectiveRkey = rkey;
    if (effectiveRkey.length == 0) {
        id recordRkey = record[@"rkey"] ?: record[@"$rkey"];
        effectiveRkey = [recordRkey isKindOfClass:[NSString class]] ? recordRkey : nil;
    }
    if (effectiveRkey.length == 0) {
        // Generate a random rkey if not present. A generated key is not derivable
        // by deleteRecord:, so such a row is only removable via a DID-scoped purge.
        effectiveRkey = [[[NSUUID UUID] UUIDString] lowercaseString];
    }

    // Build URI
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, effectiveRkey];

    // Serialize value
    NSData *valueData = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
    NSString *valueStr = valueData
        ? [[NSString alloc] initWithData:valueData encoding:NSUTF8StringEncoding]
        : nil;

    // Extract subject DID if present
    NSString *subjectDid = record[@"subject"] ?: record[@"subjectDid"];
    if (subjectDid && ![subjectDid isKindOfClass:[NSString class]]) {
        subjectDid = nil;
    }

    // Store in the generic records table. The rkey column must agree with the
    // rkey embedded in the URI above, so both come from effectiveRkey.
    return [self.database saveRecordWithURI:uri
                                        did:did
                                 collection:collection
                                       rkey:effectiveRkey
                                        cid:cid ?: @""
                                     handle:nil
                                      value:valueStr
                                 subjectDid:subjectDid
                                      error:error];
}

- (BOOL)deleteRecord:(NSString *)rkey
                 did:(NSString *)did
          collection:(NSString *)collection
               error:(NSError **)error {
    // An empty rkey cannot address a stored row: indexRecord: never writes a URI
    // with an empty last segment (it falls back to the record's rkey, then to a
    // generated one), so treat it like a missing parameter instead of issuing a
    // DELETE that silently matches nothing.
    if (rkey.length == 0 || !did || !collection) {
        if (error) {
            *error = [NSError errorWithDomain:@"AppViewGenericIndexer"
                                         code:400
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Missing required parameters"
            }];
        }
        return NO;
    }

    // Mirrors the URI construction in indexRecord:; for records stored under a
    // caller-supplied or record-supplied rkey the two agree exactly.
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];

    // Delete from the records table
    NSString *query = @"DELETE FROM records WHERE uri = ?";
    return [self.database executeParameterizedUpdate:query
                                              params:@[uri]
                                               error:error];
}

@end
