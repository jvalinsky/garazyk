#import <Foundation/Foundation.h>
#import "PLCOperation.h"
#import "DIDKey.h"

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const PLCOperationSignerErrorDomain;

typedef NS_ENUM(NSInteger, PLCOperationSignerError) {
    PLCOperationSignerErrorSerializationFailed = 1,
    PLCOperationSignerErrorSigningFailed = 2
};

@interface PLCOperationSigner : NSObject

@property (nonatomic, copy, readonly) NSString *signingKeyDIDKey;

- (instancetype)initWithPrivateKeyData:(NSData *)privateKeyData
                         publicKeyData:(NSData *)publicKeyData;

- (instancetype)initWithDIDKey:(DIDKey *)didKey;

- (BOOL)signOperation:(PLCOperation *)operation error:(NSError **)error;

+ (NSString *)base64urlEncode:(NSData *)data;
+ (nullable NSData *)base64urlDecode:(NSString *)string error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
