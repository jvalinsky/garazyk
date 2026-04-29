#import <Foundation/Foundation.h>

@class Record;
@class TutorialSQLiteHelper;

NS_ASSUME_NONNULL_BEGIN

@interface RecordRepository : NSObject

- (instancetype)initWithDatabasePath:(NSString *)path;
- (BOOL)saveRecord:(Record *)record forDid:(NSString *)did error:(NSError **)error;
- (nullable Record *)getRecordAtURI:(NSString *)uri forDid:(NSString *)did error:(NSError **)error;
- (nullable NSArray<Record *> *)listRecords:(NSString *)collection
                                      forDid:(NSString *)did
                                       limit:(NSUInteger)limit
                                       error:(NSError **)error;
- (BOOL)deleteRecordAtURI:(NSString *)uri forDid:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
