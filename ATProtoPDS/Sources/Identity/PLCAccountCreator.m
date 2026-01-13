#import "PLCAccountCreator.h"

NSErrorDomain const PLCAccountCreatorErrorDomain = @"com.atproto.plc.account";

@interface PLCAccountCreator ()
@property (nonatomic, strong) PLCClient *plcClient;
@end

@implementation PLCAccountCreator

- (instancetype)initWithPlcDirectoryURL:(NSString *)plcDirectoryURL
                                 pdsURL:(NSString *)pdsURL {
    self = [super init];
    if (self) {
        _plcDirectoryURL = [plcDirectoryURL copy];
        _pdsURL = [pdsURL copy];
        _plcClient = [[PLCClient alloc] initWithDirectoryURL:plcDirectoryURL];
    }
    return self;
}

- (nullable NSDictionary *)createAccountWithHandle:(NSString *)handle
                                             email:(NSString *)email
                                         password:(NSString *)password
                                             error:(NSError **)error {
    NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:handle];

    NSError *validationError = nil;
    if (![ATProtoHandleValidator validateHandle:normalizedHandle error:&validationError]) {
        if (error) {
            *error = [NSError errorWithDomain:PLCAccountCreatorErrorDomain
                                         code:PLCAccountCreatorErrorInvalidHandle
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid handle",
                                                NSUnderlyingErrorKey: validationError}];
        }
        return nil;
    }

    DIDKey *signingKey = [DIDKey generateSecp256k1];
    if (!signingKey) {
        if (error) {
            *error = [NSError errorWithDomain:PLCAccountCreatorErrorDomain
                                         code:PLCAccountCreatorErrorKeyGenerationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate signing key"}];
        }
        return nil;
    }

    DIDKey *rotationKeyPrimary = [DIDKey generateSecp256k1];
    DIDKey *rotationKeyRecovery = [DIDKey generateSecp256k1];
    if (!rotationKeyPrimary || !rotationKeyRecovery) {
        if (error) {
            *error = [NSError errorWithDomain:PLCAccountCreatorErrorDomain
                                         code:PLCAccountCreatorErrorKeyGenerationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate rotation keys"}];
        }
        return nil;
    }

    NSArray<NSString *> *rotationKeys = @[rotationKeyPrimary.didKey, rotationKeyRecovery.didKey];

    NSDictionary *verificationMethods = @{
        @"atproto": signingKey.didKey
    };

    NSString *handleURI = [NSString stringWithFormat:@"at://%@", normalizedHandle];
    NSArray<NSString *> *alsoKnownAs = @[handleURI];

    NSDictionary *services = @{
        @"atproto_pds": @{
            @"type": @"AtprotoPersonalDataServer",
            @"endpoint": self.pdsURL
        }
    };

    PLCOperation *genesisOp = [PLCOperation genesisOperationWithRotationKeys:rotationKeys
                                                            verificationMethods:verificationMethods
                                                                   alsoKnownAs:alsoKnownAs
                                                                      services:services];

    PLCOperationSigner *signer = [[PLCOperationSigner alloc] initWithDIDKey:rotationKeyPrimary];
    if (![signer signOperation:genesisOp error:error]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:PLCAccountCreatorErrorDomain
                                         code:PLCAccountCreatorErrorSigningFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to sign operation"}];
        }
        return nil;
    }

    NSError *cidError = nil;
    NSString *did = [NSString stringWithFormat:@"did:plc:%@", [genesisOp computeCID:&cidError]];
    if (!did) {
        if (error) {
            *error = [NSError errorWithDomain:PLCAccountCreatorErrorDomain
                                         code:PLCAccountCreatorErrorSigningFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute DID from operation",
                                                NSUnderlyingErrorKey: cidError}];
        }
        return nil;
    }

    if (![self.plcClient submitOperation:genesisOp forDID:did error:error]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:PLCAccountCreatorErrorDomain
                                         code:PLCAccountCreatorErrorSubmissionFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to submit operation to PLC directory"}];
        }
        return nil;
    }

    return @{
        @"did": did,
        @"handle": normalizedHandle,
        @"email": email,
        @"signingKey": signingKey.didKey,
        @"signingKeyPrivateKey": [signingKey.privateKeyData base64EncodedStringWithOptions:0],
        @"rotationKeys": rotationKeys,
        @"rotationKeyPrimaryPrivateKey": [rotationKeyPrimary.privateKeyData base64EncodedStringWithOptions:0],
        @"rotationKeyRecoveryPrivateKey": [rotationKeyRecovery.privateKeyData base64EncodedStringWithOptions:0]
    };
}

@end
