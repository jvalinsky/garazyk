#import "PLCOperationSigner.h"
#import "Auth/Secp256k1.h"
#import "Identity/DIDKey.h"

NSErrorDomain const PLCOperationSignerErrorDomain = @"com.atproto.plc.signer";

@interface PLCOperationSigner ()
@property (nonatomic, strong) NSData *privateKeyData;
@property (nonatomic, strong) NSData *publicKeyData;
@property (nonatomic, copy) NSString *signingKeyDIDKey;
@end

@implementation PLCOperationSigner

- (instancetype)initWithPrivateKeyData:(NSData *)privateKeyData
                         publicKeyData:(NSData *)publicKeyData {
    self = [super init];
    if (self) {
        _privateKeyData = [privateKeyData copy];
        _publicKeyData = [publicKeyData copy];
        _signingKeyDIDKey = [self computeDIDKey];
    }
    return self;
}

- (instancetype)initWithDIDKey:(DIDKey *)didKey {
    return [self initWithPrivateKeyData:didKey.privateKeyData
                          publicKeyData:didKey.publicKeyData];
}

- (NSString *)computeDIDKey {
    NSMutableData *multicodecData = [NSMutableData data];
    uint8_t multicodec = 0xe7;
    [multicodecData appendBytes:&multicodec length:1];
    [multicodecData appendData:self.publicKeyData];

    NSString *base58 = [DIDKey base58Encode:multicodecData];
    return [NSString stringWithFormat:@"did:key:z%@", base58];
}

- (BOOL)signOperation:(PLCOperation *)operation error:(NSError **)error {
    NSData *cborBytes = [operation serializeForSigning:error];
    if (!cborBytes) {
        return NO;
    }

    NSData *signature = [[Secp256k1 shared] signHash:cborBytes
                                       withPrivateKey:self.privateKeyData
                                                  error:error];
    if (!signature) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:PLCOperationSignerErrorDomain
                                         code:PLCOperationSignerErrorSigningFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signing failed"}];
        }
        return NO;
    }

    NSString *base64urlSig = [PLCOperationSigner base64urlEncode:signature];
    operation.sig = base64urlSig;

    return YES;
}

+ (NSString *)base64urlEncode:(NSData *)data {
    NSData *base64Data = [data base64EncodedDataWithOptions:0];
    NSMutableString *base64 = [[NSMutableString alloc] initWithData:base64Data encoding:NSUTF8StringEncoding];
    [base64 replaceOccurrencesOfString:@"+" withString:@"-"
                                options:0
                                  range:NSMakeRange(0, base64.length)];
    [base64 replaceOccurrencesOfString:@"/" withString:@"_"
                                options:0
                                  range:NSMakeRange(0, base64.length)];
    while ([base64 hasSuffix:@"="]) {
        [base64 deleteCharactersInRange:NSMakeRange(base64.length - 1, 1)];
    }
    return [base64 copy];
}

+ (nullable NSData *)base64urlDecode:(NSString *)string error:(NSError **)error {
    NSMutableString *base64 = [string mutableCopy];
    [base64 replaceOccurrencesOfString:@"-" withString:@"+"
                                options:0
                                  range:NSMakeRange(0, base64.length)];
    [base64 replaceOccurrencesOfString:@"_" withString:@"/"
                                options:0
                                  range:NSMakeRange(0, base64.length)];

    NSUInteger padding = (4 - (base64.length % 4)) % 4;
    for (NSUInteger i = 0; i < padding; i++) {
        [base64 appendString:@"="];
    }

    NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    if (!data && error) {
        *error = [NSError errorWithDomain:PLCOperationSignerErrorDomain
                                     code:-1
                                 userInfo:@{NSLocalizedDescriptionKey: @"Invalid base64url encoding"}];
    }
    return data;
}

@end
