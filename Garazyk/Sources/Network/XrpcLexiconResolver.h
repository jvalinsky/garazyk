#import <Foundation/Foundation.h>
#import "Core/DID.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSConfiguration;
@class XrpcDispatcher;

extern NSErrorDomain const XrpcLexiconResolverErrorDomain;

@interface XrpcLexiconResolver : NSObject

+ (nullable NSDictionary *)resolveLexiconResponseForNSID:(NSString *)nsid
                                           configuration:(PDSConfiguration *)configuration
                                                   error:(NSError **)error;

+ (void)registerResolveLexiconMethodOnDispatcher:(XrpcDispatcher *)dispatcher
                                   configuration:(PDSConfiguration *)configuration;

/*! Extracts the PDS service endpoint from a DID document. */
+ (nullable NSString *)pdsEndpointFromDidDocument:(DIDDocument *)document
                                            error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

