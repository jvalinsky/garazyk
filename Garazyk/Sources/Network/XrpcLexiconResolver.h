// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Core/DID.h"

NS_ASSUME_NONNULL_BEGIN

@class ATProtoServiceConfiguration;
@class XrpcDispatcher;

extern NSErrorDomain const XrpcLexiconResolverErrorDomain;

@interface XrpcLexiconResolver : NSObject

/**
 * @abstract Performs the resolveLexiconResponseForNSID operation.
 */
+ (nullable NSDictionary *)resolveLexiconResponseForNSID:(NSString *)nsid
                                           configuration:(ATProtoServiceConfiguration *)configuration
                                                   error:(NSError **)error;

/**
 * @abstract Performs the registerResolveLexiconMethodOnDispatcher operation.
 */
+ (void)registerResolveLexiconMethodOnDispatcher:(XrpcDispatcher *)dispatcher
                                   configuration:(ATProtoServiceConfiguration *)configuration;

/*! Extracts the PDS service endpoint from a DID document. */
+ (nullable NSString *)pdsEndpointFromDidDocument:(DIDDocument *)document
                                            error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

