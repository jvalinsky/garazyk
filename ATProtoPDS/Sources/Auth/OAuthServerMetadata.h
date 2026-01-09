#import <Foundation/Foundation.h>

@interface OAuthServerMetadata : NSObject
@property (nonatomic, readonly) NSDictionary *metadata;
- (instancetype)initWithBaseURL:(NSString *)baseURL;
@end