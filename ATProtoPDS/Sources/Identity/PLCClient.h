#import <Foundation/Foundation.h>
#import "PLCOperation.h"

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const PLCClientErrorDomain;

typedef NS_ENUM(NSInteger, PLCClientError) {
    PLCClientErrorNetworkError = 1,
    PLCClientErrorInvalidResponse = 2,
    PLCClientErrorDIDNotFound = 3,
    PLCClientErrorValidationFailed = 4,
    PLCClientErrorServerError = 5
};

@interface PLCClient : NSObject

@property (nonatomic, copy, readonly) NSString *directoryURL;

- (instancetype)initWithDirectoryURL:(NSString *)directoryURL;

- (BOOL)submitOperation:(PLCOperation *)operation
               forDID:(NSString *)did
                error:(NSError **)error;

- (nullable NSDictionary *)getDocumentDataForDID:(NSString *)did
                                            error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)getAuditLogForDID:(NSString *)did
                                                   error:(NSError **)error;

- (nullable NSString *)resolveHandle:(NSString *)handle
                               error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
