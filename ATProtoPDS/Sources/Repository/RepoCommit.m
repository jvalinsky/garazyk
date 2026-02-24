#import "Repository/RepoCommit.h"
#import "Repository/CBOR.h"
#import "Core/CID.h"
#import "Core/TID.h"
#import "Repository/CAR.h"
#import "Auth/Secp256k1.h"
#import "Core/ATProtoDagCBOR.h"

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
    return [self serializeWithSignature:NO];
}

- (NSData *)serializeSigned {
    return [self serializeWithSignature:YES];
}

- (NSData *)serializeWithSignature:(BOOL)includeSignature {
    NSMutableDictionary *commitDict = [NSMutableDictionary dictionary];

    commitDict[@"did"] = self.did;
    commitDict[@"version"] = @(self.version);

    if (self.dataCID) {
        commitDict[@"data"] = self.dataCID;
    }

    commitDict[@"rev"] = self.rev;

    if (self.prevCID) {
        commitDict[@"prev"] = self.prevCID;
    }

    if (includeSignature && self.signature) {
        commitDict[@"sig"] = self.signature;
    }

    NSError *error = nil;
    NSData *encoded = [ATProtoDagCBOR encodeObject:commitDict error:&error];
    if (!encoded) {
        NSLog(@"Failed to encode commit: %@", error);
        return nil;
    }
    return encoded;
}

- (nullable NSData *)computeHash {
    NSData *serialized = [self serialize];
    return [CID rawSha256:serialized];
}

- (CID *)computeCID {
    NSData *serialized = [self serializeSigned];
    NSData *hash = [CID rawSha256:serialized];
    CID *cid = [CID cidWithDigest:hash codec:0x71];
    return cid;
}

- (nullable NSData *)exportCAR {
    if (!self.signature) {
        return nil;
    }

    NSData *signedData = [self serializeSigned];
    CID *commitCID = [self computeCID];
    
    CARWriter *writer = [CARWriter writerWithRootCID:commitCID];
    [writer addBlock:[CARBlock blockWithCID:commitCID data:signedData]];
    
    return [writer serialize];
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

    // Decode using the spec-compliant DAG-CBOR parser
    id decoded = [ATProtoDagCBOR decodeData:commitBlock.data error:error];
    if (![decoded isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:RepoCommitErrorDomain
                                         code:-4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid commit CBOR data: not a map"}];
        }
        return nil;
    }

    NSDictionary *commitMap = (NSDictionary *)decoded;
    RepoCommit *commit = [[self alloc] init];

    // did (required)
    if (![commitMap[@"did"] isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [NSError errorWithDomain:RepoCommitErrorDomain
                                         code:-4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing or invalid 'did' field"}];
        }
        return nil;
    }
    commit.did = commitMap[@"did"];

    // version (required)
    if (!commitMap[@"version"]) {
        if (error) {
            *error = [NSError errorWithDomain:RepoCommitErrorDomain
                                         code:-4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing 'version' field"}];
        }
        return nil;
    }
    commit.version = [commitMap[@"version"] integerValue];

    // data (optional) - CID-link
    id dataValue = commitMap[@"data"];
    if ([dataValue isKindOfClass:[CID class]]) {
        commit.dataCID = (CID *)dataValue;
    } else if ([dataValue isKindOfClass:[NSString class]]) {
        commit.dataCID = [CID cidFromString:(NSString *)dataValue];
    }

    // rev (required)
    if (![commitMap[@"rev"] isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [NSError errorWithDomain:RepoCommitErrorDomain
                                         code:-4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing or invalid 'rev' field"}];
        }
        return nil;
    }
    commit.rev = commitMap[@"rev"];

    // prev (optional) - CID-link
    id prevValue = commitMap[@"prev"];
    if ([prevValue isKindOfClass:[CID class]]) {
        commit.prevCID = (CID *)prevValue;
    } else if ([prevValue isKindOfClass:[NSString class]]) {
        commit.prevCID = [CID cidFromString:(NSString *)prevValue];
    }

    // sig (optional, for signed commits)
    id sigValue = commitMap[@"sig"];
    if ([sigValue isKindOfClass:[NSData class]]) {
        commit.signature = (NSData *)sigValue;
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