#import <Foundation/Foundation.h>

@class Account;
@class TutorialSQLiteHelper;

NS_ASSUME_NONNULL_BEGIN

@interface AccountRepository : NSObject

- (instancetype)initWithDatabasePath:(NSString *)path;

- (BOOL)saveAccount:(Account *)account error:(NSError **)error;
- (nullable Account *)accountForHandle:(NSString *)handle error:(NSError **)error;
- (nullable Account *)accountForEmail:(NSString *)email error:(NSError **)error;
- (nullable Account *)accountForDid:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
