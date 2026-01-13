#import <Foundation/Foundation.h>
#import "PLCClient.h"
#import "DIDKey.h"
#import "PLCOperation.h"
#import "PLCOperationSigner.h"
#import "Identity/ATProtoHandleValidator.h"

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const PLCAccountCreatorErrorDomain;

typedef NS_ENUM(NSInteger, PLCAccountCreatorError) {
    PLCAccountCreatorErrorInvalidHandle = 1,
    PLCAccountCreatorErrorKeyGenerationFailed = 2,
    PLCAccountCreatorErrorSigningFailed = 3,
    PLCAccountCreatorErrorSubmissionFailed = 4,
    PLCAccountCreatorErrorKeyStorageFailed = 5
};

@interface PLCAccountCreator : NSObject

@property (nonatomic, copy, readonly) NSString *plcDirectoryURL;
@property (nonatomic, copy, readonly) NSString *pdsURL;

- (instancetype)initWithPlcDirectoryURL:(NSString *)plcDirectoryURL
                                 pdsURL:(NSString *)pdsURL;

- (nullable NSDictionary *)createAccountWithHandle:(NSString *)handle
                                             email:(NSString *)email
                                         password:(NSString *)password
                                             error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
