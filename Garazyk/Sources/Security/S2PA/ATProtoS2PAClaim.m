// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Security/S2PA/ATProtoS2PAClaim.h"
#import "Core/CBOR.h"
#import <CommonCrypto/CommonDigest.h>
#include <string.h>

NSString * const ATProtoS2PAClaimErrorDomain = @"com.atproto.s2pa.claim";
NSString * const ATProtoS2PAClaimLabel = @"c2pa.claim.v2";
NSString * const ATProtoS2PAAssertionStoreLabel = @"c2pa.assertions";
NSString * const ATProtoS2PAClaimSignatureURI = @"self#jumbf=c2pa.signature";

// c2as
static const uint8_t kC2PAAssertionStoreType[16] = {
    0x63, 0x32, 0x61, 0x73, 0x00, 0x11, 0x00, 0x10,
    0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71
};
// c2cl
static const uint8_t kC2PAClaimType[16] = {
    0x63, 0x32, 0x63, 0x6C, 0x00, 0x11, 0x00, 0x10,
    0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71
};
// cbor content-type UUID
static const uint8_t kJUMBFCBORType[16] = {
    0x63, 0x62, 0x6F, 0x72, 0x00, 0x11, 0x00, 0x10,
    0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71
};

@interface ATProtoS2PAClaim (Private)
+ (nullable NSData *)assertionJUMBFWithLabel:(NSString *)label cbor:(NSData *)cbor error:(NSError **)error;
@end

static NSError *S2PAClaimErr(ATProtoS2PAClaimErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoS2PAClaimErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void S2PAClaimSetErr(NSError **error, ATProtoS2PAClaimErrorCode code, NSString *message) {
    if (error) *error = S2PAClaimErr(code, message);
}

static ATProtoCBORValue *S2PAText(NSString *s) {
    return [ATProtoCBORValue textString:s];
}

static void S2PAAppendUInt32BE(uint32_t value, NSMutableData *data) {
    uint8_t bytes[4] = {
        (uint8_t)(value >> 24), (uint8_t)(value >> 16),
        (uint8_t)(value >> 8), (uint8_t)value
    };
    [data appendBytes:bytes length:4];
}

static uint32_t S2PAReadUInt32BE(const uint8_t *bytes) {
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
           ((uint32_t)bytes[2] << 8) | bytes[3];
}

static NSData *S2PAWriteBox(const char *type, NSData *body) {
    NSMutableData *box = [NSMutableData dataWithCapacity:8 + body.length];
    S2PAAppendUInt32BE((uint32_t)(8 + body.length), box);
    [box appendBytes:type length:4];
    [box appendData:body];
    return box;
}

static NSData *S2PAWriteJUMD(const uint8_t type[16], NSString *label) {
    NSMutableData *body = [NSMutableData data];
    [body appendBytes:type length:16];
    uint8_t toggles = 0x03;
    [body appendBytes:&toggles length:1];
    [body appendData:[label dataUsingEncoding:NSUTF8StringEncoding]];
    uint8_t nul = 0;
    [body appendBytes:&nul length:1];
    return S2PAWriteBox("jumd", body);
}

static NSData *S2PAWriteJUMB(NSData *jumd, NSArray<NSData *> *children) {
    NSMutableData *body = [jumd mutableCopy];
    for (NSData *child in children) {
        [body appendData:child];
    }
    return S2PAWriteBox("jumb", body);
}

static NSString *S2PAAssertionURIPrefix(void) {
    return [NSString stringWithFormat:@"self#jumbf=%@/", ATProtoS2PAAssertionStoreLabel];
}

static ATProtoCBORValue *S2PAHashedURICBOR(ATProtoS2PAHashedURI *uri, NSError **error) {
    if (uri.url.length == 0 || uri.digest.length != CC_SHA256_DIGEST_LENGTH) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidArgument,
                        @"hashed_uri requires url and 32-byte sha256 hash");
        return nil;
    }
    NSMutableDictionary *map = [@{
        S2PAText(@"url"): S2PAText(uri.url),
        S2PAText(@"hash"): [ATProtoCBORValue byteString:uri.digest],
    } mutableCopy];
    if (uri.alg.length > 0) map[S2PAText(@"alg")] = S2PAText(uri.alg);
    return [ATProtoCBORValue map:map];
}

static ATProtoS2PAHashedURI *S2PAHashedURIFromCBOR(ATProtoCBORValue *value) {
    if (value.type != CBORTypeMap) return nil;
    __block NSString *url = nil;
    __block NSData *hash = nil;
    __block NSString *alg = nil;
    __block BOOL malformed = NO;
    [value.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *key, ATProtoCBORValue *val,
                                                    BOOL *stop) {
        (void)stop;
        if (key.type != CBORTypeTextString) {
            malformed = YES;
        } else if ([key.textString isEqualToString:@"url"]) {
            if (val.type != CBORTypeTextString) malformed = YES;
            else url = val.textString;
        } else if ([key.textString isEqualToString:@"hash"]) {
            if (val.type != CBORTypeByteString) malformed = YES;
            else hash = val.byteString;
        } else if ([key.textString isEqualToString:@"alg"]) {
            if (val.type != CBORTypeTextString) malformed = YES;
            else alg = val.textString;
        }
    }];
    if (malformed || url.length == 0 || hash.length != CC_SHA256_DIGEST_LENGTH) return nil;
    return [ATProtoS2PAHashedURI hashedURIWithURL:url digest:hash alg:alg];
}

static BOOL S2PAIsValidRedactedAssertionURI(NSString *uri) {
    if (![uri isKindOfClass:[NSString class]] || uri.length == 0 ||
        [uri rangeOfString:@"?"].location != NSNotFound ||
        [uri componentsSeparatedByString:@"#"].count != 2) {
        return NO;
    }
    NSString *prefix = @"self#jumbf=/c2pa/";
    if (![uri hasPrefix:prefix]) return NO;
    NSString *path = [uri substringFromIndex:prefix.length];
    if ([path rangeOfString:@".."].location != NSNotFound) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                              @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./:-"];
    if ([path rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) return NO;
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
    return parts.count == 3 && parts[0].length > 0 &&
           [parts[1] isEqualToString:ATProtoS2PAAssertionStoreLabel] && parts[2].length > 0;
}

static BOOL S2PAValidateLocalHashedURIReferences(NSArray<ATProtoS2PAHashedURI *> *created,
                                                 NSArray<ATProtoS2PAHashedURI *> *gathered,
                                                 NSError **error) {
    NSString *prefix = S2PAAssertionURIPrefix();
    NSMutableSet<NSString *> *labels = [NSMutableSet set];
    for (NSArray<ATProtoS2PAHashedURI *> *list in @[created, gathered]) {
        for (ATProtoS2PAHashedURI *uri in list) {
            if (![uri.url hasPrefix:prefix] || uri.digest.length != CC_SHA256_DIGEST_LENGTH) {
                S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidStructure,
                                @"hashed_uri must reference c2pa.assertions with a sha256 hash");
                return NO;
            }
            NSString *label = [uri.url substringFromIndex:prefix.length];
            if (label.length == 0 || [label containsString:@"/"] || [labels containsObject:label]) {
                S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidStructure,
                                @"created and gathered assertion references must be unique labels");
                return NO;
            }
            [labels addObject:label];
        }
    }
    return YES;
}

static NSArray<ATProtoS2PAHashedURI *> *S2PAHashedURIsForAssertions(
    NSArray<ATProtoS2PAStoredAssertion *> *assertions, NSMutableSet<NSString *> *labels,
    NSError **error) {
    NSMutableArray<ATProtoS2PAHashedURI *> *uris = [NSMutableArray array];
    for (ATProtoS2PAStoredAssertion *assertion in assertions) {
        if (assertion.label.length == 0 || [labels containsObject:assertion.label]) {
            S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidArgument,
                            @"created and gathered assertion labels must be unique");
            return nil;
        }
        [labels addObject:assertion.label];
        NSData *box = [ATProtoS2PAClaim assertionJUMBFWithLabel:assertion.label cbor:assertion.cbor
                                                          error:error];
        if (!box) return nil;
        NSData *hash = [ATProtoS2PAClaim sha256HashForAssertionJUMBF:box error:error];
        if (!hash) return nil;
        [uris addObject:[ATProtoS2PAHashedURI hashedURIWithURL:
                         [S2PAAssertionURIPrefix() stringByAppendingString:assertion.label]
                                                    digest:hash alg:nil]];
    }
    return uris;
}

@implementation ATProtoS2PAHashedURI
+ (instancetype)hashedURIWithURL:(NSString *)url digest:(NSData *)digest alg:(NSString *)alg {
    ATProtoS2PAHashedURI *u = [[ATProtoS2PAHashedURI alloc] init];
    u->_url = [url copy];
    u->_digest = [digest copy];
    u->_alg = [alg copy];
    return u;
}
@end

@implementation ATProtoS2PAStoredAssertion
+ (instancetype)assertionWithLabel:(NSString *)label cbor:(NSData *)cbor {
    ATProtoS2PAStoredAssertion *a = [[ATProtoS2PAStoredAssertion alloc] init];
    a->_label = [label copy];
    a->_cbor = [cbor copy];
    return a;
}
@end

@implementation ATProtoS2PAClaimGeneratorInfo
+ (instancetype)infoWithName:(NSString *)name
                     version:(NSString *)version
                 specVersion:(NSString *)specVersion {
    ATProtoS2PAClaimGeneratorInfo *i = [[ATProtoS2PAClaimGeneratorInfo alloc] init];
    i->_name = [name copy];
    i->_version = [version copy];
    i->_specVersion = [specVersion copy];
    return i;
}
@end

@interface ATProtoS2PAClaim ()
@property (nonatomic, copy, readwrite) NSString *instanceID;
@property (nonatomic, strong, readwrite) ATProtoS2PAClaimGeneratorInfo *generatorInfo;
@property (nonatomic, copy, readwrite) NSString *signatureURI;
@property (nonatomic, copy, readwrite) NSArray<ATProtoS2PAHashedURI *> *createdAssertions;
@property (nonatomic, copy, readwrite) NSArray<ATProtoS2PAHashedURI *> *gatheredAssertions;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *redactedAssertions;
@property (nonatomic, copy, readwrite) NSString *alg;
@property (nonatomic, copy, readwrite, nullable) NSString *title;
@end

@implementation ATProtoS2PAClaim

- (instancetype)initWithInstanceID:(NSString *)instanceID
                    generatorInfo:(ATProtoS2PAClaimGeneratorInfo *)generatorInfo
                     signatureURI:(NSString *)signatureURI
               createdAssertions:(NSArray<ATProtoS2PAHashedURI *> *)createdAssertions
                             alg:(NSString *)alg
                           title:(NSString *)title {
    return [self initWithInstanceID:instanceID
                      generatorInfo:generatorInfo
                       signatureURI:signatureURI
                 createdAssertions:createdAssertions
                gatheredAssertions:nil
                redactedAssertions:nil
                               alg:alg
                             title:title];
}

- (instancetype)initWithInstanceID:(NSString *)instanceID
                    generatorInfo:(ATProtoS2PAClaimGeneratorInfo *)generatorInfo
                     signatureURI:(NSString *)signatureURI
               createdAssertions:(NSArray<ATProtoS2PAHashedURI *> *)createdAssertions
              gatheredAssertions:(NSArray<ATProtoS2PAHashedURI *> *)gatheredAssertions
              redactedAssertions:(NSArray<NSString *> *)redactedAssertions
                             alg:(NSString *)alg
                           title:(NSString *)title {
    self = [super init];
    if (self) {
        _instanceID = [instanceID copy];
        _generatorInfo = generatorInfo;
        _signatureURI = [signatureURI copy];
        _createdAssertions = [createdAssertions copy] ?: @[];
        _gatheredAssertions = [gatheredAssertions copy] ?: @[];
        _redactedAssertions = [redactedAssertions copy] ?: @[];
        _alg = [alg copy] ?: @"sha256";
        _title = [title copy];
    }
    return self;
}

+ (nullable NSData *)assertionJUMBFWithLabel:(NSString *)label
                                       cbor:(NSData *)cbor
                                      error:(NSError **)error {
    if (label.length == 0 || cbor.length == 0) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidArgument,
                        @"assertion label and CBOR are required");
        return nil;
    }
    NSData *content = S2PAWriteBox("cbor", cbor);
    return S2PAWriteJUMB(S2PAWriteJUMD(kJUMBFCBORType, label), @[ content ]);
}

+ (nullable NSData *)sha256HashForAssertionJUMBF:(NSData *)assertionJUMB
                                          error:(NSError **)error {
    if (![assertionJUMB isKindOfClass:[NSData class]] || assertionJUMB.length < 8) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidArgument,
                        @"assertion JUMBF is required");
        return nil;
    }
    const uint8_t *b = assertionJUMB.bytes;
    if (memcmp(b + 4, "jumb", 4) != 0) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidStructure,
                        @"assertion must be a jumb superbox");
        return nil;
    }
    uint32_t size = S2PAReadUInt32BE(b);
    if (size != assertionJUMB.length) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidStructure,
                        @"assertion jumb size mismatch");
        return nil;
    }
    NSData *body = [assertionJUMB subdataWithRange:NSMakeRange(8, assertionJUMB.length - 8)];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(body.bytes, (CC_LONG)body.length, digest);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

+ (nullable NSData *)assertionStoreJUMBFWithAssertions:(NSArray<ATProtoS2PAStoredAssertion *> *)assertions
                                                 error:(NSError **)error {
    if (assertions.count == 0) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidArgument,
                        @"assertion store requires at least one assertion");
        return nil;
    }
    NSMutableArray<NSData *> *children = [NSMutableArray array];
    NSMutableSet<NSString *> *labels = [NSMutableSet set];
    for (ATProtoS2PAStoredAssertion *a in assertions) {
        if (a.label.length == 0 || [labels containsObject:a.label]) {
            S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidArgument,
                            @"assertion store labels must be unique");
            return nil;
        }
        [labels addObject:a.label];
        NSData *box = [self assertionJUMBFWithLabel:a.label cbor:a.cbor error:error];
        if (!box) return nil;
        [children addObject:box];
    }
    return S2PAWriteJUMB(S2PAWriteJUMD(kC2PAAssertionStoreType, ATProtoS2PAAssertionStoreLabel),
                         children);
}

+ (nullable NSData *)claimJUMBFWithCBOR:(NSData *)claimCBOR error:(NSError **)error {
    if (claimCBOR.length == 0) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidArgument, @"claim CBOR is required");
        return nil;
    }
    NSData *content = S2PAWriteBox("cbor", claimCBOR);
    return S2PAWriteJUMB(S2PAWriteJUMD(kC2PAClaimType, ATProtoS2PAClaimLabel), @[ content ]);
}

+ (nullable instancetype)claimWithAssertions:(NSArray<ATProtoS2PAStoredAssertion *> *)assertions
                                  instanceID:(NSString *)instanceID
                              generatorInfo:(ATProtoS2PAClaimGeneratorInfo *)generatorInfo
                                      title:(NSString *)title
                                      error:(NSError **)error {
    return [self claimWithCreatedAssertions:assertions
                         gatheredAssertions:nil
                         redactedAssertions:nil
                                instanceID:instanceID
                            generatorInfo:generatorInfo
                                    title:title
                                    error:error];
}

+ (nullable instancetype)claimWithCreatedAssertions:(NSArray<ATProtoS2PAStoredAssertion *> *)createdAssertions
                                  gatheredAssertions:(NSArray<ATProtoS2PAStoredAssertion *> *)gatheredAssertions
                                   redactedAssertions:(NSArray<NSString *> *)redactedAssertions
                                          instanceID:(NSString *)instanceID
                                      generatorInfo:(ATProtoS2PAClaimGeneratorInfo *)generatorInfo
                                              title:(NSString *)title
                                              error:(NSError **)error {
    if (instanceID.length == 0 || !generatorInfo || generatorInfo.name.length == 0) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidArgument,
                        @"instanceID and generator name are required");
        return nil;
    }
    if (createdAssertions.count == 0) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidArgument,
                        @"claim requires at least one assertion");
        return nil;
    }
    NSMutableSet<NSString *> *labels = [NSMutableSet set];
    NSArray<ATProtoS2PAHashedURI *> *created =
        S2PAHashedURIsForAssertions(createdAssertions, labels, error);
    if (!created) return nil;
    NSArray<ATProtoS2PAHashedURI *> *gathered =
        S2PAHashedURIsForAssertions(gatheredAssertions ?: @[], labels, error);
    if (!gathered) return nil;
    for (NSString *uri in redactedAssertions ?: @[]) {
        if (!S2PAIsValidRedactedAssertionURI(uri)) {
            S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidArgument,
                            @"redacted assertion must be an ingredient-manifest JUMBF URI");
            return nil;
        }
    }
    return [[self alloc] initWithInstanceID:instanceID
                             generatorInfo:generatorInfo
                              signatureURI:ATProtoS2PAClaimSignatureURI
                        createdAssertions:created
                       gatheredAssertions:gathered
                       redactedAssertions:redactedAssertions
                                      alg:@"sha256"
                                    title:title];
}

- (nullable NSData *)encodeCBOR:(NSError **)error {
    if (self.instanceID.length == 0 || self.generatorInfo.name.length == 0 ||
        self.signatureURI.length == 0 || self.createdAssertions.count == 0 ||
        ![self.alg isEqualToString:@"sha256"]) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidArgument,
                        @"claim fields incomplete or unsupported alg");
        return nil;
    }
    if (!S2PAValidateLocalHashedURIReferences(self.createdAssertions, self.gatheredAssertions,
                                              error)) return nil;
    NSMutableDictionary *gen = [@{
        S2PAText(@"name"): S2PAText(self.generatorInfo.name),
    } mutableCopy];
    if (self.generatorInfo.version.length > 0) {
        gen[S2PAText(@"version")] = S2PAText(self.generatorInfo.version);
    }
    if (self.generatorInfo.specVersion.length > 0) {
        gen[S2PAText(@"specVersion")] = S2PAText(self.generatorInfo.specVersion);
    }
    NSMutableArray *created = [NSMutableArray array];
    NSMutableArray *gathered = [NSMutableArray array];
    for (ATProtoS2PAHashedURI *uri in self.createdAssertions) {
        ATProtoCBORValue *value = S2PAHashedURICBOR(uri, error);
        if (!value) return nil;
        [created addObject:value];
    }
    for (ATProtoS2PAHashedURI *uri in self.gatheredAssertions) {
        ATProtoCBORValue *value = S2PAHashedURICBOR(uri, error);
        if (!value) return nil;
        [gathered addObject:value];
    }
    NSMutableArray *redacted = [NSMutableArray array];
    for (NSString *uri in self.redactedAssertions) {
        if (!S2PAIsValidRedactedAssertionURI(uri)) {
            S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidArgument,
                            @"redacted assertion must be an ingredient-manifest JUMBF URI");
            return nil;
        }
        [redacted addObject:S2PAText(uri)];
    }
    NSMutableDictionary *dict = [@{
        S2PAText(@"instanceID"): S2PAText(self.instanceID),
        S2PAText(@"claim_generator_info"): [ATProtoCBORValue map:gen],
        S2PAText(@"signature"): S2PAText(self.signatureURI),
        S2PAText(@"created_assertions"): [ATProtoCBORValue array:created],
        S2PAText(@"alg"): S2PAText(self.alg),
    } mutableCopy];
    if (self.title.length > 0) {
        dict[S2PAText(@"dc:title")] = S2PAText(self.title);
    }
    if (gathered.count > 0) dict[S2PAText(@"gathered_assertions")] = [ATProtoCBORValue array:gathered];
    if (redacted.count > 0) dict[S2PAText(@"redacted_assertions")] = [ATProtoCBORValue array:redacted];
    NSData *encoded = [[ATProtoCBORValue map:dict] encode];
    if (!encoded) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidStructure, @"failed to encode claim CBOR");
    }
    return encoded;
}

+ (nullable instancetype)claimFromCBOR:(NSData *)cbor error:(NSError **)error {
    if (![cbor isKindOfClass:[NSData class]] || cbor.length == 0) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidArgument, @"claim CBOR is empty");
        return nil;
    }
    NSUInteger offset = 0;
    ATProtoCBORValue *root = [ATProtoCBORDecoder decode:cbor offset:&offset];
    if (!root || offset != cbor.length || root.type != CBORTypeMap) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidStructure,
                        @"claim must be a single CBOR map");
        return nil;
    }
    if (![root.encode isEqualToData:cbor]) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidStructure,
                        @"claim CBOR must be canonical");
        return nil;
    }
    __block NSString *instanceID = nil;
    __block NSString *signatureURI = nil;
    __block NSString *alg = @"sha256";
    __block NSString *title = nil;
    __block ATProtoS2PAClaimGeneratorInfo *genInfo = nil;
    NSMutableArray<ATProtoS2PAHashedURI *> *created = [NSMutableArray array];
    NSMutableArray<ATProtoS2PAHashedURI *> *gathered = [NSMutableArray array];
    NSMutableArray<NSString *> *redacted = [NSMutableArray array];
    __block BOOL malformedReferences = NO;
    [root.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *key, ATProtoCBORValue *val,
                                                  BOOL *stop) {
        (void)stop;
        if (key.type != CBORTypeTextString) return;
        NSString *k = key.textString;
        if ([k isEqualToString:@"instanceID"] && val.type == CBORTypeTextString) {
            instanceID = val.textString;
        } else if ([k isEqualToString:@"signature"] && val.type == CBORTypeTextString) {
            signatureURI = val.textString;
        } else if ([k isEqualToString:@"alg"] && val.type == CBORTypeTextString) {
            alg = val.textString;
        } else if ([k isEqualToString:@"dc:title"] && val.type == CBORTypeTextString) {
            title = val.textString;
        } else if ([k isEqualToString:@"claim_generator_info"] && val.type == CBORTypeMap) {
            __block NSString *name = nil;
            __block NSString *version = nil;
            __block NSString *specVersion = nil;
            [val.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *gk, ATProtoCBORValue *gv,
                                                         BOOL *s2) {
                (void)s2;
                if (gk.type != CBORTypeTextString || gv.type != CBORTypeTextString) return;
                if ([gk.textString isEqualToString:@"name"]) name = gv.textString;
                else if ([gk.textString isEqualToString:@"version"]) version = gv.textString;
                else if ([gk.textString isEqualToString:@"specVersion"]) specVersion = gv.textString;
            }];
            if (name.length > 0) {
                genInfo = [ATProtoS2PAClaimGeneratorInfo infoWithName:name
                                                              version:version
                                                          specVersion:specVersion];
            }
        } else if (([k isEqualToString:@"created_assertions"] ||
                    [k isEqualToString:@"gathered_assertions"]) && val.type == CBORTypeArray) {
            NSMutableArray<ATProtoS2PAHashedURI *> *out =
                [k isEqualToString:@"created_assertions"] ? created : gathered;
            if (val.array.count == 0) malformedReferences = YES;
            for (ATProtoCBORValue *item in val.array) {
                ATProtoS2PAHashedURI *uri = S2PAHashedURIFromCBOR(item);
                if (!uri) malformedReferences = YES;
                else [out addObject:uri];
            }
        } else if ([k isEqualToString:@"redacted_assertions"] && val.type == CBORTypeArray) {
            if (val.array.count == 0) malformedReferences = YES;
            for (ATProtoCBORValue *item in val.array) {
                if (item.type != CBORTypeTextString || !S2PAIsValidRedactedAssertionURI(item.textString)) {
                    malformedReferences = YES;
                } else {
                    [redacted addObject:item.textString];
                }
            }
        } else if ([k isEqualToString:@"created_assertions"] ||
                   [k isEqualToString:@"gathered_assertions"] ||
                   [k isEqualToString:@"redacted_assertions"]) {
            malformedReferences = YES;
        }
    }];
    if (malformedReferences || instanceID.length == 0 || !genInfo || signatureURI.length == 0 ||
        created.count == 0) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidStructure,
                        @"claim missing required fields");
        return nil;
    }
    if (!S2PAValidateLocalHashedURIReferences(created, gathered, error)) return nil;
    return [[self alloc] initWithInstanceID:instanceID
                             generatorInfo:genInfo
                              signatureURI:signatureURI
                        createdAssertions:created
                       gatheredAssertions:gathered
                       redactedAssertions:redacted
                                      alg:alg
                                    title:title];
}

+ (nullable NSString *)labelFromJUMDBody:(NSData *)jumdBody {
    // TYPE(16) + TOGGLES(1) + LABEL\0
    if (jumdBody.length < 18) return nil;
    const uint8_t *b = jumdBody.bytes;
    uint8_t toggles = b[16];
    if ((toggles & 0x02) == 0) return nil; // label present bit
    NSUInteger start = 17;
    NSUInteger end = start;
    while (end < jumdBody.length && b[end] != 0) end++;
    if (end >= jumdBody.length) return nil;
    return [[NSString alloc] initWithBytes:b + start length:end - start encoding:NSUTF8StringEncoding];
}

+ (nullable NSData *)assertionCBORWithLabel:(NSString *)label
                          inAssertionStore:(NSData *)assertionStoreJUMBF
                                     error:(NSError **)error {
    if (label.length == 0 || assertionStoreJUMBF.length < 8) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidArgument,
                        @"label and assertion store are required");
        return nil;
    }
    const uint8_t *bytes = assertionStoreJUMBF.bytes;
    uint32_t outer = S2PAReadUInt32BE(bytes);
    if (outer != assertionStoreJUMBF.length || memcmp(bytes + 4, "jumb", 4) != 0) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidStructure,
                        @"assertion store must be a jumb superbox");
        return nil;
    }
    NSUInteger offset = 8;
    // Skip store jumd
    if (offset + 8 > assertionStoreJUMBF.length) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidStructure, @"truncated store truncated");
        return nil;
    }
    uint32_t jumdSize = S2PAReadUInt32BE(bytes + offset);
    if (jumdSize < 8 || offset + jumdSize > assertionStoreJUMBF.length ||
        memcmp(bytes + offset + 4, "jumd", 4) != 0) {
        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidStructure, @"assertion store jumd missing");
        return nil;
    }
    offset += jumdSize;
    NSData *matchedCBOR = nil;
    while (offset + 8 <= assertionStoreJUMBF.length) {
        uint32_t size = S2PAReadUInt32BE(bytes + offset);
        if (size < 8 || offset + size > assertionStoreJUMBF.length) {
            S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidStructure,
                            @"assertion child box invalid");
            return nil;
        }
        if (memcmp(bytes + offset + 4, "jumb", 4) != 0) {
            offset += size;
            continue;
        }
        NSData *child = [assertionStoreJUMBF subdataWithRange:NSMakeRange(offset, size)];
        // child body starts at +8; first box is jumd
        if (size < 16) {
            offset += size;
            continue;
        }
        uint32_t childJumdSize = S2PAReadUInt32BE(bytes + offset + 8);
        if (childJumdSize < 8 || 8 + childJumdSize > size ||
            memcmp(bytes + offset + 12, "jumd", 4) != 0) {
            offset += size;
            continue;
        }
        NSData *jumdBody = [NSData dataWithBytes:bytes + offset + 16 length:childJumdSize - 8];
        NSString *childLabel = [self labelFromJUMDBody:jumdBody];
        if ([childLabel isEqualToString:label]) {
            if (matchedCBOR) {
                S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidStructure,
                                @"assertion store contains a duplicate label");
                return nil;
            }
            // Find first cbor content box after jumd
            NSUInteger cOff = 8 + childJumdSize;
            NSData *content = nil;
            while (cOff + 8 <= size) {
                uint32_t cSize = S2PAReadUInt32BE(bytes + offset + cOff);
                if (cSize < 8 || cOff + cSize > size) break;
                if (memcmp(bytes + offset + cOff + 4, "cbor", 4) == 0) {
                    if (content) {
                        S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidStructure,
                                        @"assertion contains duplicate cbor content");
                        return nil;
                    }
                    content = [NSData dataWithBytes:bytes + offset + cOff + 8 length:cSize - 8];
                }
                cOff += cSize;
            }
            if (!content) {
                S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidStructure,
                                @"assertion missing cbor content");
                return nil;
            }
            matchedCBOR = content;
        }
        (void)child;
        offset += size;
    }
    if (matchedCBOR) return matchedCBOR;
    S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidStructure, @"assertion label not found");
    return nil;
}

+ (nullable NSData *)assertionJUMBFWithLabel:(NSString *)label
                          inAssertionStore:(NSData *)assertionStoreJUMBF
                                     error:(NSError **)error {
    // Rebuild by extracting CBOR and re-encoding — ensures hash matches builder.
    NSData *cbor = [self assertionCBORWithLabel:label inAssertionStore:assertionStoreJUMBF error:error];
    if (!cbor) return nil;
    return [self assertionJUMBFWithLabel:label cbor:cbor error:error];
}

- (BOOL)verifyHashedURIsAgainstAssertionStore:(NSData *)assertionStoreJUMBF
                                        error:(NSError **)error {
    NSString *prefix = S2PAAssertionURIPrefix();
    if (!S2PAValidateLocalHashedURIReferences(self.createdAssertions, self.gatheredAssertions,
                                              error)) return NO;
    for (NSArray<ATProtoS2PAHashedURI *> *list in @[self.createdAssertions, self.gatheredAssertions]) {
        for (ATProtoS2PAHashedURI *uri in list) {
            NSString *label = [uri.url substringFromIndex:prefix.length];
            NSData *box = [[self class] assertionJUMBFWithLabel:label
                                              inAssertionStore:assertionStoreJUMBF
                                                         error:error];
            if (!box) return NO;
            NSData *hash = [[self class] sha256HashForAssertionJUMBF:box error:error];
            if (!hash) return NO;
            if (![hash isEqualToData:uri.digest]) {
                S2PAClaimSetErr(error, ATProtoS2PAClaimErrorHashMismatch,
                                @"hashed_uri digest mismatch");
                return NO;
            }
        }
    }
    for (NSString *uri in self.redactedAssertions) {
        if (!S2PAIsValidRedactedAssertionURI(uri)) {
            S2PAClaimSetErr(error, ATProtoS2PAClaimErrorInvalidStructure,
                            @"redacted assertion must be an ingredient-manifest JUMBF URI");
            return NO;
        }
    }
    return YES;
}

@end
