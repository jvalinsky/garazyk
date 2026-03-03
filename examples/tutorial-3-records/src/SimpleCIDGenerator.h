#import <Foundation/Foundation.h>

@interface SimpleCIDGenerator : NSObject

+ (NSString *)generateCIDForData:(NSData *)data;
+ (NSString *)generateCIDForJSON:(NSDictionary *)json;

@end
