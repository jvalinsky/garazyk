#import <Foundation/Foundation.h>
#import "../CID.h"
#import "../TID.h"
#import "../Auth/Secp256k1.h"

NS_ASSUME_NONNULL_BEGIN

@interface RepoCommit : NSObject <NSSecureCoding>

@property (nonatomic, copy) NSString *did;
@property (nonatomic, assign) NSInteger version;
@property (nonatomic, strong, nullable) CID *dataCID;
@property (nonatomic, copy) NSString *rev;
@property (nonatomic, strong, nullable) CID *prevCID;
@property (nonatomic, strong, nullable) NSData *signature;

+ (instancetype)createCommitWithDid:(NSString *)did
                              data:(nullable CID *)dataCID
                               rev:(nullable NSString *)rev
                             prev:(nullable CID *)prevCID;

- (NSData *)serialize;
- (nullable NSData *)computeHash;
- (CID *)computeCID;

- (BOOL)signWithPrivateKey:(NSData *)privateKey error:(NSError **)error;
- (BOOL)verifySignatureWithPublicKey:(NSData *)publicKey error:(NSError **)error;

+ (nullable instancetype)fromCARData:(NSData *)carData error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
