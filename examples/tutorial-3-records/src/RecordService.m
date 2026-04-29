#import "RecordService.h"
#import "TutorialCIDGenerator.h"

@interface RecordService ()
@property (nonatomic, strong) RecordRepository *repository;
@end

@implementation RecordService

- (instancetype)initWithRepository:(RecordRepository *)repository {
    self = [super init];
    if (!self) return nil;
    self.repository = repository;
    return self;
}

- (nullable NSDictionary *)createRecord:(NSString *)collection
                                   rkey:(NSString *)rkey
                                  value:(NSDictionary *)value
                                 forDid:(NSString *)did
                                  error:(NSError **)error {
    if (!collection || !rkey || !value || !did) {
        if (error) {
            *error = [NSError errorWithDomain:@"Record" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required fields"}];
        }
        return nil;
    }

    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    NSString *cid = [TutorialCIDGenerator generateCIDForJSON:value];

    Record *record = [[Record alloc] init];
    record.uri = uri;
    record.cid = cid;
    record.value = value;
    record.createdAt = [[NSDate date] timeIntervalSince1970];

    NSError *dbError = nil;
    if (![self.repository saveRecord:record forDid:did error:&dbError]) {
        if (error) *error = dbError;
        return nil;
    }

    return @{
        @"uri": uri,
        @"cid": cid
    };
}

- (nullable NSDictionary *)getRecord:(NSString *)uri
                              forDid:(NSString *)did
                               error:(NSError **)error {
    NSError *dbError = nil;
    Record *record = [self.repository getRecordAtURI:uri forDid:did error:&dbError];

    if (!record) {
        if (error) {
            *error = [NSError errorWithDomain:@"Record" code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Record not found"}];
        }
        return nil;
    }

    return @{
        @"uri": record.uri,
        @"cid": record.cid,
        @"value": record.value
    };
}

- (nullable NSArray *)listRecords:(NSString *)collection
                           forDid:(NSString *)did
                            limit:(NSUInteger)limit
                            error:(NSError **)error {
    NSError *dbError = nil;
    NSArray<Record *> *records = [self.repository listRecords:collection
                                                       forDid:did
                                                        limit:limit
                                                        error:&dbError];

    if (!records) {
        if (error) *error = dbError;
        return nil;
    }

    NSMutableArray *result = [NSMutableArray array];
    for (Record *record in records) {
        [result addObject:@{
            @"uri": record.uri,
            @"cid": record.cid,
            @"value": record.value
        }];
    }

    return result;
}

- (BOOL)deleteRecord:(NSString *)uri
              forDid:(NSString *)did
               error:(NSError **)error {
    return [self.repository deleteRecordAtURI:uri forDid:did error:error];
}

@end
