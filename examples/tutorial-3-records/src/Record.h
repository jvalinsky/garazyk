#import <Foundation/Foundation.h>

@interface Record : NSObject

@property (nonatomic, copy) NSString *uri;
@property (nonatomic, copy) NSString *cid;
@property (nonatomic, copy) NSDictionary *value;
@property (nonatomic, assign) NSTimeInterval createdAt;

@end
