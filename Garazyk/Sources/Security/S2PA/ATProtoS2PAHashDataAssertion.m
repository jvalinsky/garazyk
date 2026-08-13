// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Security/S2PA/ATProtoS2PAHashDataAssertion.h"
#import "Core/CBOR.h"
#import <CommonCrypto/CommonDigest.h>

NSString * const ATProtoS2PAHashDataAssertionErrorDomain = @"com.atproto.s2pa.hashdata";
NSString * const ATProtoS2PAHashDataAssertionLabel = @"c2pa.hash.data";

static NSError *S2PAHashErr(ATProtoS2PAHashDataAssertionErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoS2PAHashDataAssertionErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void S2PAHashSetErr(NSError **error, ATProtoS2PAHashDataAssertionErrorCode code,
                           NSString *message) {
    if (error) *error = S2PAHashErr(code, message);
}

static ATProtoCBORValue *S2PAText(NSString *s) {
    return [ATProtoCBORValue textString:s];
}

static ATProtoCBORValue *S2PAUInt(NSUInteger v) {
    return [ATProtoCBORValue unsignedInteger:v];
}

@implementation ATProtoS2PAHashDataExclusion
+ (instancetype)exclusionWithStart:(NSUInteger)start length:(NSUInteger)length {
    ATProtoS2PAHashDataExclusion *ex = [[ATProtoS2PAHashDataExclusion alloc] init];
    ex.start = start;
    ex.length = length;
    return ex;
}
@end

@interface ATProtoS2PAHashDataAssertion ()
@property (nonatomic, copy, readwrite) NSString *alg;
@property (nonatomic, copy, readwrite) NSData *digest;
@property (nonatomic, copy, readwrite) NSArray<ATProtoS2PAHashDataExclusion *> *exclusions;
@property (nonatomic, copy, readwrite, nullable) NSString *name;
@end

@implementation ATProtoS2PAHashDataAssertion

- (instancetype)initWithDigest:(NSData *)digest
                    exclusions:(NSArray<ATProtoS2PAHashDataExclusion *> *)exclusions
                          name:(NSString *)name {
    self = [super init];
    if (self) {
        _alg = @"sha256";
        _digest = [digest copy];
        _exclusions = [exclusions copy] ?: @[];
        _name = [name copy];
    }
    return self;
}

+ (BOOL)validateExclusions:(NSArray<ATProtoS2PAHashDataExclusion *> *)exclusions
                 dataLength:(NSUInteger)dataLength
                      error:(NSError **)error {
    NSUInteger cursor = 0;
    for (ATProtoS2PAHashDataExclusion *ex in exclusions) {
        if (ex.length == 0) {
            S2PAHashSetErr(error, ATProtoS2PAHashDataAssertionErrorInvalidArgument,
                           @"hash.data exclusion length must be > 0");
            return NO;
        }
        if (ex.start < cursor) {
            S2PAHashSetErr(error, ATProtoS2PAHashDataAssertionErrorInvalidArgument,
                           @"hash.data exclusions must be non-overlapping and ordered");
            return NO;
        }
        if (ex.start > dataLength || ex.length > dataLength - ex.start) {
            S2PAHashSetErr(error, ATProtoS2PAHashDataAssertionErrorInvalidArgument,
                           @"hash.data exclusion exceeds data length");
            return NO;
        }
        cursor = ex.start + ex.length;
    }
    return YES;
}

+ (nullable NSData *)sha256DigestForData:(NSData *)data
                              exclusions:(NSArray<ATProtoS2PAHashDataExclusion *> *)exclusions
                                   error:(NSError **)error {
    if (![data isKindOfClass:[NSData class]] || data.length == 0) {
        S2PAHashSetErr(error, ATProtoS2PAHashDataAssertionErrorInvalidArgument,
                       @"hash.data requires non-empty bytes");
        return nil;
    }
    NSArray *ex = exclusions ?: @[];
    if (![self validateExclusions:ex dataLength:data.length error:error]) {
        return nil;
    }
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    const uint8_t *bytes = data.bytes;
    NSUInteger offset = 0;
    for (ATProtoS2PAHashDataExclusion *range in ex) {
        if (range.start > offset) {
            CC_SHA256_Update(&ctx, bytes + offset, (CC_LONG)(range.start - offset));
        }
        offset = range.start + range.length;
    }
    if (offset < data.length) {
        CC_SHA256_Update(&ctx, bytes + offset, (CC_LONG)(data.length - offset));
    }
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &ctx);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

+ (nullable instancetype)assertionHardBindingMediaData:(NSData *)mediaData
                                                  name:(NSString *)name
                                                 error:(NSError **)error {
    NSData *digest = [self sha256DigestForData:mediaData exclusions:@[] error:error];
    if (!digest) return nil;
    return [[self alloc] initWithDigest:digest exclusions:@[] name:name];
}

+ (nullable instancetype)assertionForPresentation:(NSData *)presentation
                            excludedPrefixLength:(NSUInteger)excludedPrefixLength
                                            name:(NSString *)name
                                           error:(NSError **)error {
    if (excludedPrefixLength == 0 || excludedPrefixLength >= presentation.length) {
        S2PAHashSetErr(error, ATProtoS2PAHashDataAssertionErrorInvalidArgument,
                       @"excludedPrefixLength must leave a non-empty media suffix");
        return nil;
    }
    ATProtoS2PAHashDataExclusion *ex =
        [ATProtoS2PAHashDataExclusion exclusionWithStart:0 length:excludedPrefixLength];
    NSData *digest = [self sha256DigestForData:presentation exclusions:@[ex] error:error];
    if (!digest) return nil;
    return [[self alloc] initWithDigest:digest exclusions:@[ex] name:name];
}

- (nullable NSData *)encodeCBOR:(NSError **)error {
    if (self.digest.length != CC_SHA256_DIGEST_LENGTH || ![self.alg isEqualToString:@"sha256"]) {
        S2PAHashSetErr(error, ATProtoS2PAHashDataAssertionErrorInvalidArgument,
                       @"only sha256 32-byte hashes are supported");
        return nil;
    }
    NSMutableArray<ATProtoCBORValue *> *exArr = [NSMutableArray array];
    for (ATProtoS2PAHashDataExclusion *ex in self.exclusions) {
        ATProtoCBORValue *map = [ATProtoCBORValue map:@{
            S2PAText(@"start"): S2PAUInt(ex.start),
            S2PAText(@"length"): S2PAUInt(ex.length),
        }];
        [exArr addObject:map];
    }
    NSMutableDictionary *dict = [@{
        S2PAText(@"alg"): S2PAText(self.alg),
        S2PAText(@"hash"): [ATProtoCBORValue byteString:self.digest],
        S2PAText(@"exclusions"): [ATProtoCBORValue array:exArr],
    } mutableCopy];
    if (self.name.length > 0) {
        dict[S2PAText(@"name")] = S2PAText(self.name);
    }
    NSData *encoded = [[ATProtoCBORValue map:dict] encode];
    if (!encoded) {
        S2PAHashSetErr(error, ATProtoS2PAHashDataAssertionErrorInvalidStructure,
                       @"failed to encode hash.data CBOR");
    }
    return encoded;
}

+ (nullable instancetype)assertionFromCBOR:(NSData *)cbor error:(NSError **)error {
    if (![cbor isKindOfClass:[NSData class]] || cbor.length == 0) {
        S2PAHashSetErr(error, ATProtoS2PAHashDataAssertionErrorInvalidArgument,
                       @"hash.data CBOR is empty");
        return nil;
    }
    NSUInteger offset = 0;
    ATProtoCBORValue *root = [ATProtoCBORDecoder decode:cbor offset:&offset];
    if (!root || offset != cbor.length || root.type != CBORTypeMap) {
        S2PAHashSetErr(error, ATProtoS2PAHashDataAssertionErrorInvalidStructure,
                       @"hash.data must be a single CBOR map");
        return nil;
    }
    if (![root.encode isEqualToData:cbor]) {
        S2PAHashSetErr(error, ATProtoS2PAHashDataAssertionErrorInvalidStructure,
                       @"hash.data CBOR must be canonical");
        return nil;
    }
    __block NSString *alg = nil;
    __block NSData *digestBytes = nil;
    __block NSString *name = nil;
    NSMutableArray<ATProtoS2PAHashDataExclusion *> *exclusions = [NSMutableArray array];
    [root.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *key, ATProtoCBORValue *val,
                                                  BOOL *stop) {
        (void)stop;
        if (key.type != CBORTypeTextString) return;
        NSString *k = key.textString;
        if ([k isEqualToString:@"alg"] && val.type == CBORTypeTextString) {
            alg = val.textString;
        } else if ([k isEqualToString:@"hash"] && val.type == CBORTypeByteString) {
            digestBytes = val.byteString;
        } else if ([k isEqualToString:@"name"] && val.type == CBORTypeTextString) {
            name = val.textString;
        } else if ([k isEqualToString:@"exclusions"] && val.type == CBORTypeArray) {
            for (ATProtoCBORValue *item in val.array) {
                if (item.type != CBORTypeMap) continue;
                __block NSUInteger start = NSNotFound;
                __block NSUInteger length = NSNotFound;
                [item.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *ik, ATProtoCBORValue *iv,
                                                              BOOL *s2) {
                    (void)s2;
                    if (ik.type != CBORTypeTextString) return;
                    if ([ik.textString isEqualToString:@"start"] &&
                        iv.type == CBORTypeUnsignedInteger) {
                        start = iv.unsignedInteger.unsignedIntegerValue;
                    } else if ([ik.textString isEqualToString:@"length"] &&
                               iv.type == CBORTypeUnsignedInteger) {
                        length = iv.unsignedInteger.unsignedIntegerValue;
                    }
                }];
                if (start != NSNotFound && length != NSNotFound) {
                    [exclusions addObject:[ATProtoS2PAHashDataExclusion exclusionWithStart:start
                                                                                    length:length]];
                }
            }
        }
    }];
    if (![alg isEqualToString:@"sha256"] || digestBytes.length != CC_SHA256_DIGEST_LENGTH) {
        S2PAHashSetErr(error, ATProtoS2PAHashDataAssertionErrorInvalidStructure,
                       @"hash.data requires alg=sha256 and 32-byte hash");
        return nil;
    }
    return [[self alloc] initWithDigest:digestBytes exclusions:exclusions name:name];
}

- (BOOL)verifyAgainstData:(NSData *)data error:(NSError **)error {
    NSData *computed = [[self class] sha256DigestForData:data
                                              exclusions:self.exclusions
                                                   error:error];
    if (!computed) return NO;
    if (![computed isEqualToData:self.digest]) {
        S2PAHashSetErr(error, ATProtoS2PAHashDataAssertionErrorHashMismatch,
                       @"hash.data digest mismatch");
        return NO;
    }
    return YES;
}

@end
