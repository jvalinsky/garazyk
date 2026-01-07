#import "Repository/RepoCommit.h"
#import "Repository/CBOR.h"
#import "Core/CID.h"
#import "Core/TID.h"
#import "Repository/CAR.h"
#import "Auth/Secp256k1.h"

NSString * const RepoCommitErrorDomain = @"com.atproto.repo.commit";

@implementation RepoCommit

+ (instancetype)createCommitWithDid:(NSString *)did
                               data:(nullable CID *)dataCID
                                rev:(nullable NSString *)rev
                              prev:(nullable CID *)prevCID {
    RepoCommit *commit = [[self alloc] init];
    commit.did = did;
    commit.version = 3;
    commit.dataCID = dataCID;
    commit.rev = rev ?: [[TID tid] stringValue];
    commit.prevCID = prevCID;
    return commit;
}

- (NSData *)serialize {
    // Create CBOR map for unsigned commit (without signature)
    NSMutableDictionary<CBORValue *, CBORValue *> *commitMap = [NSMutableDictionary dictionary];

    // did (required)
    commitMap[[CBORValue textString:@"did"]] = [CBORValue textString:self.did];

    // version (required)
    commitMap[[CBORValue textString:@"version"]] = [CBORValue unsignedInteger:self.version];

    // data (optional)
    if (self.dataCID) {
        commitMap[[CBORValue textString:@"data"]] = [CBORValue textString:self.dataCID.stringValue];
    }

    // rev (required)
    commitMap[[CBORValue textString:@"rev"]] = [CBORValue textString:self.rev];

    // prev (optional)
    if (self.prevCID) {
        commitMap[[CBORValue textString:@"prev"]] = [CBORValue textString:self.prevCID.stringValue];
    }

    CBORValue *commitValue = [CBORValue map:commitMap];
    return [CBOREncoder encode:commitValue];
}

- (nullable NSData *)computeHash {
    NSData *serialized = [self serialize];
    return [CID sha256Digest:serialized];
}

- (CID *)computeCID {
    // Serialize the full signed commit (including signature)
    NSMutableDictionary<CBORValue *, CBORValue *> *commitMap = [NSMutableDictionary dictionary];

    // did
    commitMap[[CBORValue textString:@"did"]] = [CBORValue textString:self.did];

    // version
    commitMap[[CBORValue textString:@"version"]] = [CBORValue unsignedInteger:self.version];

    // data (optional)
    if (self.dataCID) {
        commitMap[[CBORValue textString:@"data"]] = [CBORValue textString:self.dataCID.stringValue];
    }

    // rev
    commitMap[[CBORValue textString:@"rev"]] = [CBORValue textString:self.rev];

    // prev (optional)
    if (self.prevCID) {
        commitMap[[CBORValue textString:@"prev"]] = [CBORValue textString:self.prevCID.stringValue];
    }

    // sig (required for signed commit)
    if (self.signature) {
        commitMap[[CBORValue textString:@"sig"]] = [CBORValue byteString:self.signature];
    }

    CBORValue *commitValue = [CBORValue map:commitMap];
    NSData *serialized = [CBOREncoder encode:commitValue];

    // Compute SHA-256 hash and create CID with DAG-CBOR codec (0x71)
    NSData *hash = [CID sha256Digest:serialized];
    return [CID cidWithMultihash:hash codec:0x71]; // DAG-CBOR codec
}

- (BOOL)signWithPrivateKey:(NSData *)privateKey error:(NSError **)error {
    NSData *hash = [self computeHash];
    if (!hash) {
        if (error) {
            *error = [NSError errorWithDomain:RepoCommitErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute commit hash"}];
        }
        return NO;
    }

    Secp256k1 *secp = [Secp256k1 shared];
    NSData *signature = [secp signHash:hash withPrivateKey:privateKey error:error];
    if (!signature) {
        return NO;
    }

    self.signature = signature;
    return YES;
}

- (BOOL)verifySignatureWithPublicKey:(NSData *)publicKey error:(NSError **)error {
    if (!self.signature) {
        if (error) {
            *error = [NSError errorWithDomain:RepoCommitErrorDomain
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Commit has no signature"}];
        }
        return NO;
    }

    NSData *hash = [self computeHash];
    if (!hash) {
        if (error) {
            *error = [NSError errorWithDomain:RepoCommitErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute commit hash"}];
        }
        return NO;
    }

    Secp256k1 *secp = [Secp256k1 shared];
    return [secp verifySignature:self.signature forHash:hash withPublicKey:publicKey error:error];
}

+ (nullable instancetype)fromCARData:(NSData *)carData error:(NSError **)error {
    CARReader *reader = [CARReader readFromData:carData error:error];
    if (!reader) {
        return nil;
    }

    // Find the commit block (the root CID)
    CARBlock *commitBlock = [reader blockWithCID:reader.rootCID];
    if (!commitBlock) {
        if (error) {
            *error = [NSError errorWithDomain:RepoCommitErrorDomain
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"CAR file does not contain root commit block"}];
        }
        return nil;
    }

    // Decode the CBOR data
    CBORValue *decoded = [CBORDecoder decode:commitBlock.data];
    if (!decoded || decoded.type != CBORTypeMap) {
        if (error) {
            *error = [NSError errorWithDomain:RepoCommitErrorDomain
                                         code:-4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid commit CBOR data"}];
        }
        return nil;
    }

    NSDictionary<CBORValue *, CBORValue *> *commitMap = decoded.map;
    if (!commitMap) {
        if (error) {
            *error = [NSError errorWithDomain:RepoCommitErrorDomain
                                         code:-4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid commit structure"}];
        }
        return nil;
    }

    // Extract fields
    RepoCommit *commit = [[self alloc] init];

    // did (required)
    CBORValue *didKey = [CBORValue textString:@"did"];
    CBORValue *didValue = commitMap[didKey];
    if (!didValue || didValue.type != CBORTypeTextString) {
        if (error) {
            *error = [NSError errorWithDomain:RepoCommitErrorDomain
                                         code:-4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing or invalid 'did' field"}];
        }
        return nil;
    }
    commit.did = didValue.textString;

    // version (required)
    CBORValue *versionKey = [CBORValue textString:@"version"];
    CBORValue *versionValue = commitMap[versionKey];
    if (!versionValue || versionValue.type != CBORTypeUnsignedInteger) {
        if (error) {
            *error = [NSError errorWithDomain:RepoCommitErrorDomain
                                         code:-4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing or invalid 'version' field"}];
        }
        return nil;
    }
    commit.version = versionValue.unsignedInteger.integerValue;

    // data (optional)
    CBORValue *dataKey = [CBORValue textString:@"data"];
    CBORValue *dataValue = commitMap[dataKey];
    if (dataValue && dataValue.type == CBORTypeTextString) {
        commit.dataCID = [CID cidFromString:dataValue.textString];
    }

    // rev (required)
    CBORValue *revKey = [CBORValue textString:@"rev"];
    CBORValue *revValue = commitMap[revKey];
    if (!revValue || revValue.type != CBORTypeTextString) {
        if (error) {
            *error = [NSError errorWithDomain:RepoCommitErrorDomain
                                         code:-4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing or invalid 'rev' field"}];
        }
        return nil;
    }
    commit.rev = revValue.textString;

    // prev (optional)
    CBORValue *prevKey = [CBORValue textString:@"prev"];
    CBORValue *prevValue = commitMap[prevKey];
    if (prevValue && prevValue.type == CBORTypeTextString) {
        commit.prevCID = [CID cidFromString:prevValue.textString];
    }

    // sig (optional, for signed commits)
    CBORValue *sigKey = [CBORValue textString:@"sig"];
    CBORValue *sigValue = commitMap[sigKey];
    if (sigValue && sigValue.type == CBORTypeByteString) {
        commit.signature = sigValue.byteString;
    }

    return commit;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.did forKey:@"did"];
    [coder encodeInteger:self.version forKey:@"version"];
    [coder encodeObject:self.dataCID forKey:@"dataCID"];
    [coder encodeObject:self.rev forKey:@"rev"];
    [coder encodeObject:self.prevCID forKey:@"prevCID"];
    [coder encodeObject:self.signature forKey:@"signature"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        self.did = [coder decodeObjectOfClass:[NSString class] forKey:@"did"];
        self.version = [coder decodeIntegerForKey:@"version"];
        self.dataCID = [coder decodeObjectOfClass:[CID class] forKey:@"dataCID"];
        self.rev = [coder decodeObjectOfClass:[NSString class] forKey:@"rev"];
        self.prevCID = [coder decodeObjectOfClass:[CID class] forKey:@"prevCID"];
        self.signature = [coder decodeObjectOfClass:[NSData class] forKey:@"signature"];
    }
    return self;
}

@end