// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcLexiconResolver.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @category XrpcLexiconResolver (Testing)
 @abstract Exposes internal methods for unit testing.

 @discussion
 These methods are implementation details of the lexicon resolution pipeline
 exposed here so that XCTest can verify the pure-logic components (NSID
 parsing, endpoint extraction, URL construction) without requiring a live
 network, DNS resolver, or PLC directory.
 */
@interface XrpcLexiconResolver (Testing)

+ (nullable NSString *)authorityDomainForNSID:(NSString *)nsid error:(NSError **)error;
+ (nullable NSString *)pdsEndpointFromDidDocument:(DIDDocument *)document error:(NSError **)error;
+ (nullable NSDictionary *)buildResolveResponseWithSchema:(NSDictionary *)schema nsid:(NSString *)nsid configuration:(ATProtoServiceConfiguration *)configuration error:(NSError **)error;
+ (nullable NSDictionary *)loadLexiconJSONForNSID:(NSString *)nsid dataDirectory:(NSString *)dataDirectory error:(NSError **)error;
+ (nullable NSURL *)lexiconRecordURLForEndpoint:(NSString *)endpoint did:(NSString *)did nsid:(NSString *)nsid error:(NSError **)error;
+ (void)persistLexiconSchema:(NSDictionary *)schema forNSID:(NSString *)nsid dataDirectory:(NSString *)dataDirectory;

@end

NS_ASSUME_NONNULL_END
