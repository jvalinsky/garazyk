#import <Foundation/Foundation.h>

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

@end

NS_ASSUME_NONNULL_END

