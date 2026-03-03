#import <Foundation/Foundation.h>

@interface OAuth2Handler : NSObject

- (instancetype)init;

- (void)handleAuthorize:(NSDictionary *)params completion:(void (^)(NSString *redirectURL, NSError *error))completion;
- (void)handleToken:(NSDictionary *)params completion:(void (^)(NSDictionary *result, NSError *error))completion;
- (void)handleRefresh:(NSDictionary *)params completion:(void (^)(NSDictionary *result, NSError *error))completion;

@end
