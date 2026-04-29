#import <Foundation/Foundation.h>
#import "Video/VideoAuthProvider.h"

NS_ASSUME_NONNULL_BEGIN

@interface VideoJWTAuthProvider : NSObject <VideoAuthProvider>

@property (nonatomic, copy, readonly) NSString *audience;
@property (nonatomic, copy, nullable, readonly) NSDictionary *signingKeyJWK;

- (instancetype)initWithExpectedAudience:(NSString *)audience
                            signingKeyJWK:(nullable NSDictionary *)signingKeyJWK;

@end

NS_ASSUME_NONNULL_END
