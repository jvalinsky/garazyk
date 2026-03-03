#import <Foundation/Foundation.h>
#import "Account.h"

@interface AccountRepository : NSObject {
}

- (instancetype)initWithDatabasePath:(NSString *)path;
- (BOOL)saveAccount:(Account *)account error:(NSError **)error;
- (nullable Account *)accountForHandle:(NSString *)handle error:(NSError **)error;
- (nullable Account *)accountForEmail:(NSString *)email error:(NSError **)error;
- (nullable Account *)accountForDid:(NSString *)did error:(NSError **)error;

@end
