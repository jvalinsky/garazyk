#import <Foundation/Foundation.h>
#import "Video/VideoAuthProvider.h"

@class DIDResolver;

NS_ASSUME_NONNULL_BEGIN

@interface VideoJWTAuthProvider : NSObject <VideoAuthProvider>

@property (nonatomic, copy, readonly) NSString *audience;
@property (nonatomic, copy, nullable, readonly) NSDictionary *signingKeyJWK;
@property (nonatomic, strong, nullable, readonly) DIDResolver *didResolver;

- (instancetype)initWithExpectedAudience:(NSString *)audience
                            signingKeyJWK:(nullable NSDictionary *)signingKeyJWK;

- (instancetype)initWithExpectedAudience:(NSString *)audience
                                 pdsURL:(NSString *)pdsURL
                                 plcURL:(nullable NSString *)plcURL;

@end

NS_ASSUME_NONNULL_END
