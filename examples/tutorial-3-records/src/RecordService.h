#import <Foundation/Foundation.h>
#import "Record.h"
#import "RecordRepository.h"

NS_ASSUME_NONNULL_BEGIN

@interface RecordService : NSObject

- (instancetype)initWithRepository:(RecordRepository *)repository;

- (nullable NSDictionary *)createRecord:(NSString *)collection
                                   rkey:(NSString *)rkey
                                  value:(NSDictionary *)value
                                 forDid:(NSString *)did
                                  error:(NSError **)error;

- (nullable NSDictionary *)getRecord:(NSString *)uri
                              forDid:(NSString *)did
                               error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)listRecords:(NSString *)collection
                                           forDid:(NSString *)did
                                            limit:(NSUInteger)limit
                                            error:(NSError **)error;

- (BOOL)deleteRecord:(NSString *)uri
              forDid:(NSString *)did
               error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
