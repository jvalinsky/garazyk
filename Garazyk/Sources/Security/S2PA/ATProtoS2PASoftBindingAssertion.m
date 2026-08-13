// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Security/S2PA/ATProtoS2PASoftBindingAssertion.h"
#import "Core/CBOR.h"
#import <CommonCrypto/CommonDigest.h>

NSString * const ATProtoS2PASoftBindingAssertionErrorDomain = @"com.atproto.s2pa.softbinding";
NSString * const ATProtoS2PASoftBindingAssertionLabel = @"c2pa.soft-binding";
NSString * const ATProtoS2PASoftBindingAlgorithmMonolithSHA256 = @"com.joinmonolith.sha256";

static NSError *S2PASoftErr(ATProtoS2PASoftBindingAssertionErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoS2PASoftBindingAssertionErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void S2PASoftSetErr(NSError **error, ATProtoS2PASoftBindingAssertionErrorCode code,
                           NSString *message) {
    if (error) *error = S2PASoftErr(code, message);
}

static ATProtoCBORValue *S2PAText(NSString *s) {
    return [ATProtoCBORValue textString:s];
}

static ATProtoCBORValue *S2PAUInt(NSUInteger v) {
    return [ATProtoCBORValue unsignedInteger:v];
}

@implementation ATProtoS2PASoftBindingTimespan
+ (instancetype)timespanWithStart:(NSUInteger)start end:(NSUInteger)end {
    ATProtoS2PASoftBindingTimespan *t = [[ATProtoS2PASoftBindingTimespan alloc] init];
    t.start = start;
    t.end = end;
    return t;
}
- (BOOL)isEqualToTimespan:(ATProtoS2PASoftBindingTimespan *)other {
    if (!other) return NO;
    return self.start == other.start && self.end == other.end;
}
@end

@implementation ATProtoS2PASoftBindingBlock
+ (instancetype)blockWithValue:(NSData *)value
                      timespan:(ATProtoS2PASoftBindingTimespan *)timespan {
    ATProtoS2PASoftBindingBlock *b = [[ATProtoS2PASoftBindingBlock alloc] init];
    b.value = [value copy];
    b.timespan = timespan;
    return b;
}
@end

@interface ATProtoS2PASoftBindingAssertion ()
@property (nonatomic, copy, readwrite) NSString *alg;
@property (nonatomic, copy, readwrite) NSArray<ATProtoS2PASoftBindingBlock *> *blocks;
@property (nonatomic, copy, readwrite, nullable) NSString *name;
@property (nonatomic, copy, readwrite, nullable) NSData *algParams;
@end

@implementation ATProtoS2PASoftBindingAssertion

- (instancetype)initWithAlg:(NSString *)alg
                     blocks:(NSArray<ATProtoS2PASoftBindingBlock *> *)blocks
                       name:(NSString *)name
                  algParams:(NSData *)algParams {
    self = [super init];
    if (self) {
        _alg = [alg copy];
        _blocks = [blocks copy] ?: @[];
        _name = [name copy];
        _algParams = [algParams copy];
    }
    return self;
}

+ (nullable NSData *)computeValueForData:(NSData *)data
                                     alg:(NSString *)alg
                               algParams:(NSData *)algParams
                                   error:(NSError **)error {
    (void)algParams;
    if (![data isKindOfClass:[NSData class]] || data.length == 0) {
        S2PASoftSetErr(error, ATProtoS2PASoftBindingAssertionErrorInvalidArgument,
                       @"soft-binding compute requires non-empty media bytes");
        return nil;
    }
    if (![alg isEqualToString:ATProtoS2PASoftBindingAlgorithmMonolithSHA256]) {
        S2PASoftSetErr(error, ATProtoS2PASoftBindingAssertionErrorUnsupportedAlgorithm,
                       @"only com.joinmonolith.sha256 soft-binding compute is supported");
        return nil;
    }
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

+ (nullable instancetype)assertionMonolithSHA256ForData:(NSData *)data
                                               timespan:(ATProtoS2PASoftBindingTimespan *)timespan
                                                   name:(NSString *)name
                                                  error:(NSError **)error {
    NSData *value = [self computeValueForData:data
                                          alg:ATProtoS2PASoftBindingAlgorithmMonolithSHA256
                                    algParams:nil
                                        error:error];
    if (!value) return nil;
    ATProtoS2PASoftBindingBlock *block =
        [ATProtoS2PASoftBindingBlock blockWithValue:value timespan:timespan];
    return [[self alloc] initWithAlg:ATProtoS2PASoftBindingAlgorithmMonolithSHA256
                              blocks:@[block]
                                name:name
                           algParams:nil];
}

- (BOOL)verifyAgainstData:(NSData *)data
                 timespan:(ATProtoS2PASoftBindingTimespan *)timespan
                    error:(NSError **)error {
    if (![self.alg isEqualToString:ATProtoS2PASoftBindingAlgorithmMonolithSHA256]) {
        S2PASoftSetErr(error, ATProtoS2PASoftBindingAssertionErrorUnsupportedAlgorithm,
                       @"verify only supports com.joinmonolith.sha256");
        return NO;
    }
    ATProtoS2PASoftBindingBlock *matched = nil;
    for (ATProtoS2PASoftBindingBlock *block in self.blocks) {
        if (timespan == nil && block.timespan == nil) {
            matched = block;
            break;
        }
        if (timespan && [block.timespan isEqualToTimespan:timespan]) {
            matched = block;
            break;
        }
    }
    if (!matched) {
        S2PASoftSetErr(error, ATProtoS2PASoftBindingAssertionErrorInvalidArgument,
                       @"no soft-binding block matches the requested timespan");
        return NO;
    }
    NSData *computed = [[self class] computeValueForData:data
                                                     alg:self.alg
                                               algParams:self.algParams
                                                   error:error];
    if (!computed) return NO;
    if (![computed isEqualToData:matched.value]) {
        S2PASoftSetErr(error, ATProtoS2PASoftBindingAssertionErrorMismatch,
                       @"soft-binding fingerprint mismatch");
        return NO;
    }
    return YES;
}

- (nullable NSData *)encodeCBOR:(NSError **)error {
    if (self.alg.length == 0 || self.blocks.count == 0) {
        S2PASoftSetErr(error, ATProtoS2PASoftBindingAssertionErrorInvalidArgument,
                       @"soft-binding requires alg and at least one block");
        return nil;
    }
    NSMutableArray<ATProtoCBORValue *> *blockArr = [NSMutableArray array];
    for (ATProtoS2PASoftBindingBlock *block in self.blocks) {
        if (block.value.length == 0) {
            S2PASoftSetErr(error, ATProtoS2PASoftBindingAssertionErrorInvalidArgument,
                           @"soft-binding block value must be non-empty");
            return nil;
        }
        NSMutableDictionary *scope = [NSMutableDictionary dictionary];
        if (block.timespan) {
            if (block.timespan.end < block.timespan.start) {
                S2PASoftSetErr(error, ATProtoS2PASoftBindingAssertionErrorInvalidArgument,
                               @"soft-binding timespan end must be >= start");
                return nil;
            }
            scope[S2PAText(@"timespan")] = [ATProtoCBORValue map:@{
                S2PAText(@"start"): S2PAUInt(block.timespan.start),
                S2PAText(@"end"): S2PAUInt(block.timespan.end),
            }];
        }
        [blockArr addObject:[ATProtoCBORValue map:@{
            S2PAText(@"scope"): [ATProtoCBORValue map:scope],
            S2PAText(@"value"): [ATProtoCBORValue byteString:block.value],
        }]];
    }
    NSMutableDictionary *dict = [@{
        S2PAText(@"alg"): S2PAText(self.alg),
        S2PAText(@"blocks"): [ATProtoCBORValue array:blockArr],
    } mutableCopy];
    if (self.name.length > 0) {
        dict[S2PAText(@"name")] = S2PAText(self.name);
    }
    if (self.algParams.length > 0) {
        dict[S2PAText(@"alg-params")] = [ATProtoCBORValue byteString:self.algParams];
    }
    NSData *encoded = [[ATProtoCBORValue map:dict] encode];
    if (!encoded) {
        S2PASoftSetErr(error, ATProtoS2PASoftBindingAssertionErrorInvalidStructure,
                       @"failed to encode soft-binding CBOR");
    }
    return encoded;
}

+ (nullable instancetype)assertionFromCBOR:(NSData *)cbor error:(NSError **)error {
    if (![cbor isKindOfClass:[NSData class]] || cbor.length == 0) {
        S2PASoftSetErr(error, ATProtoS2PASoftBindingAssertionErrorInvalidArgument,
                       @"soft-binding CBOR is empty");
        return nil;
    }
    NSUInteger offset = 0;
    ATProtoCBORValue *root = [ATProtoCBORDecoder decode:cbor offset:&offset];
    if (!root || offset != cbor.length || root.type != CBORTypeMap) {
        S2PASoftSetErr(error, ATProtoS2PASoftBindingAssertionErrorInvalidStructure,
                       @"soft-binding must be a single CBOR map");
        return nil;
    }
    if (![root.encode isEqualToData:cbor]) {
        S2PASoftSetErr(error, ATProtoS2PASoftBindingAssertionErrorInvalidStructure,
                       @"soft-binding CBOR must be canonical");
        return nil;
    }
    __block NSString *alg = nil;
    __block NSString *name = nil;
    __block NSData *algParams = nil;
    NSMutableArray<ATProtoS2PASoftBindingBlock *> *blocks = [NSMutableArray array];
    [root.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *key, ATProtoCBORValue *val,
                                                  BOOL *stop) {
        (void)stop;
        if (key.type != CBORTypeTextString) return;
        NSString *k = key.textString;
        if ([k isEqualToString:@"alg"] && val.type == CBORTypeTextString) {
            alg = val.textString;
        } else if ([k isEqualToString:@"name"] && val.type == CBORTypeTextString) {
            name = val.textString;
        } else if ([k isEqualToString:@"alg-params"] && val.type == CBORTypeByteString) {
            algParams = val.byteString;
        } else if ([k isEqualToString:@"blocks"] && val.type == CBORTypeArray) {
            for (ATProtoCBORValue *item in val.array) {
                if (item.type != CBORTypeMap) continue;
                __block NSData *valueBytes = nil;
                __block ATProtoS2PASoftBindingTimespan *timespan = nil;
                [item.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *ik,
                                                              ATProtoCBORValue *iv, BOOL *s2) {
                    (void)s2;
                    if (ik.type != CBORTypeTextString) return;
                    if ([ik.textString isEqualToString:@"value"] &&
                        iv.type == CBORTypeByteString) {
                        valueBytes = iv.byteString;
                    } else if ([ik.textString isEqualToString:@"scope"] &&
                               iv.type == CBORTypeMap) {
                        [iv.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *sk,
                                                                    ATProtoCBORValue *sv,
                                                                    BOOL *s3) {
                            (void)s3;
                            if (sk.type != CBORTypeTextString) return;
                            if (![sk.textString isEqualToString:@"timespan"] ||
                                sv.type != CBORTypeMap) {
                                return;
                            }
                            __block NSUInteger start = NSNotFound;
                            __block NSUInteger end = NSNotFound;
                            [sv.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *tk,
                                                                        ATProtoCBORValue *tv,
                                                                        BOOL *s4) {
                                (void)s4;
                                if (tk.type != CBORTypeTextString) return;
                                if ([tk.textString isEqualToString:@"start"] &&
                                    tv.type == CBORTypeUnsignedInteger) {
                                    start = tv.unsignedInteger.unsignedIntegerValue;
                                } else if ([tk.textString isEqualToString:@"end"] &&
                                           tv.type == CBORTypeUnsignedInteger) {
                                    end = tv.unsignedInteger.unsignedIntegerValue;
                                }
                            }];
                            if (start != NSNotFound && end != NSNotFound) {
                                timespan = [ATProtoS2PASoftBindingTimespan timespanWithStart:start
                                                                                         end:end];
                            }
                        }];
                    }
                }];
                if (valueBytes.length > 0) {
                    [blocks addObject:[ATProtoS2PASoftBindingBlock blockWithValue:valueBytes
                                                                         timespan:timespan]];
                }
            }
        }
    }];
    if (alg.length == 0 || blocks.count == 0) {
        S2PASoftSetErr(error, ATProtoS2PASoftBindingAssertionErrorInvalidStructure,
                       @"soft-binding requires alg and blocks");
        return nil;
    }
    return [[self alloc] initWithAlg:alg blocks:blocks name:name algParams:algParams];
}

@end
