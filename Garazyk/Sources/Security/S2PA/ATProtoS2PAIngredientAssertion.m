// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Security/S2PA/ATProtoS2PAIngredientAssertion.h"
#import "Core/CBOR.h"
#import <CommonCrypto/CommonDigest.h>
#include <string.h>

NSString * const ATProtoS2PAIngredientAssertionErrorDomain = @"com.atproto.s2pa.ingredient";
NSString * const ATProtoS2PAIngredientAssertionLabel = @"c2pa.ingredient.v3";
NSString * const ATProtoS2PAIngredientRelationshipParentOf = @"parentOf";
NSString * const ATProtoS2PAIngredientRelationshipComponentOf = @"componentOf";
NSString * const ATProtoS2PAIngredientRelationshipInputTo = @"inputTo";

static NSError *S2PAIngErr(ATProtoS2PAIngredientAssertionErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoS2PAIngredientAssertionErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void S2PAIngSetErr(NSError **error, ATProtoS2PAIngredientAssertionErrorCode code,
                          NSString *message) {
    if (error) *error = S2PAIngErr(code, message);
}

static ATProtoCBORValue *S2PAText(NSString *s) {
    return [ATProtoCBORValue textString:s];
}

static BOOL S2PAIsValidRelationship(NSString *r) {
    return [r isEqualToString:ATProtoS2PAIngredientRelationshipParentOf] ||
           [r isEqualToString:ATProtoS2PAIngredientRelationshipComponentOf] ||
           [r isEqualToString:ATProtoS2PAIngredientRelationshipInputTo];
}

static uint32_t S2PAReadU32(const uint8_t *b) {
    return ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | b[3];
}

static void S2PAAppendU32(uint32_t v, NSMutableData *data) {
    uint8_t b[4] = {(uint8_t)(v >> 24), (uint8_t)(v >> 16), (uint8_t)(v >> 8), (uint8_t)v};
    [data appendBytes:b length:4];
}

@implementation ATProtoS2PAIngredientValidationStatus
+ (instancetype)statusWithCode:(NSString *)code url:(NSString *)url {
    ATProtoS2PAIngredientValidationStatus *s = [[ATProtoS2PAIngredientValidationStatus alloc] init];
    s->_code = [code copy];
    s->_url = [url copy];
    return s;
}
@end

@implementation ATProtoS2PAIngredientValidationResults
+ (instancetype)resultsWithSuccess:(NSArray *)success
                    informational:(NSArray *)informational
                          failure:(NSArray *)failure {
    ATProtoS2PAIngredientValidationResults *r = [[ATProtoS2PAIngredientValidationResults alloc] init];
    r->_success = [success copy] ?: @[];
    r->_informational = [informational copy] ?: @[];
    r->_failure = [failure copy] ?: @[];
    return r;
}
+ (instancetype)resultsWithSingleSuccessCode:(NSString *)code url:(NSString *)url {
    return [self resultsWithSuccess:@[ [ATProtoS2PAIngredientValidationStatus statusWithCode:code url:url] ]
                     informational:@[]
                           failure:@[]];
}
@end

@interface ATProtoS2PAIngredientAssertion ()
@property (nonatomic, copy, readwrite) NSString *relationship;
@property (nonatomic, copy, readwrite, nullable) NSString *title;
@property (nonatomic, copy, readwrite, nullable) NSString *format;
@property (nonatomic, copy, readwrite, nullable) NSString *instanceID;
@property (nonatomic, copy, readwrite, nullable) NSString *descriptionText;
@property (nonatomic, copy, readwrite, nullable) NSString *digitalSourceType;
@property (nonatomic, strong, readwrite, nullable) ATProtoS2PAHashedURI *activeManifest;
@property (nonatomic, strong, readwrite, nullable) ATProtoS2PAHashedURI *claimSignature;
@property (nonatomic, strong, readwrite, nullable) ATProtoS2PAIngredientValidationResults *validationResults;
@end

@implementation ATProtoS2PAIngredientAssertion

- (instancetype)initWithRelationship:(NSString *)relationship
                               title:(NSString *)title
                              format:(NSString *)format
                          instanceID:(NSString *)instanceID
                     descriptionText:(NSString *)descriptionText
                   digitalSourceType:(NSString *)digitalSourceType
                      activeManifest:(ATProtoS2PAHashedURI *)activeManifest
                      claimSignature:(ATProtoS2PAHashedURI *)claimSignature
                  validationResults:(ATProtoS2PAIngredientValidationResults *)validationResults {
    self = [super init];
    if (self) {
        _relationship = [relationship copy];
        _title = [title copy];
        _format = [format copy];
        _instanceID = [instanceID copy];
        _descriptionText = [descriptionText copy];
        _digitalSourceType = [digitalSourceType copy];
        _activeManifest = activeManifest;
        _claimSignature = claimSignature;
        _validationResults = validationResults;
    }
    return self;
}

+ (nullable ATProtoCBORValue *)cborForHashedURI:(ATProtoS2PAHashedURI *)uri error:(NSError **)error {
    if (uri.url.length == 0 || uri.digest.length != CC_SHA256_DIGEST_LENGTH) {
        S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidArgument,
                      @"hashed_uri requires url and 32-byte digest");
        return nil;
    }
    NSMutableDictionary *m = [@{
        S2PAText(@"url"): S2PAText(uri.url),
        S2PAText(@"hash"): [ATProtoCBORValue byteString:uri.digest],
    } mutableCopy];
    if (uri.alg.length > 0) {
        m[S2PAText(@"alg")] = S2PAText(uri.alg);
    }
    return [ATProtoCBORValue map:m];
}

+ (nullable ATProtoS2PAHashedURI *)hashedURIFromCBORMap:(ATProtoCBORValue *)val {
    if (val.type != CBORTypeMap) return nil;
    __block NSString *url = nil;
    __block NSData *digest = nil;
    __block NSString *alg = nil;
    [val.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *k, ATProtoCBORValue *v, BOOL *stop) {
        (void)stop;
        if (k.type != CBORTypeTextString) return;
        if ([k.textString isEqualToString:@"url"] && v.type == CBORTypeTextString) {
            url = v.textString;
        } else if ([k.textString isEqualToString:@"hash"] && v.type == CBORTypeByteString) {
            digest = v.byteString;
        } else if ([k.textString isEqualToString:@"alg"] && v.type == CBORTypeTextString) {
            alg = v.textString;
        }
    }];
    if (url.length == 0 || digest.length != CC_SHA256_DIGEST_LENGTH) return nil;
    return [ATProtoS2PAHashedURI hashedURIWithURL:url digest:digest alg:alg];
}

+ (nullable ATProtoCBORValue *)cborForStatusList:(NSArray<ATProtoS2PAIngredientValidationStatus *> *)list
                                          error:(NSError **)error {
    NSMutableArray *arr = [NSMutableArray array];
    for (ATProtoS2PAIngredientValidationStatus *st in list) {
        if (st.code.length == 0) {
            S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidArgument,
                          @"validation status code is required");
            return nil;
        }
        NSMutableDictionary *m = [@{ S2PAText(@"code"): S2PAText(st.code) } mutableCopy];
        if (st.url.length > 0) m[S2PAText(@"url")] = S2PAText(st.url);
        [arr addObject:[ATProtoCBORValue map:m]];
    }
    return [ATProtoCBORValue array:arr];
}

+ (NSArray<ATProtoS2PAIngredientValidationStatus *> *)statusListFromCBOR:(ATProtoCBORValue *)val {
    if (val.type != CBORTypeArray) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (ATProtoCBORValue *item in val.array) {
        if (item.type != CBORTypeMap) continue;
        __block NSString *code = nil;
        __block NSString *url = nil;
        [item.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *k, ATProtoCBORValue *v, BOOL *s) {
            (void)s;
            if (k.type != CBORTypeTextString) return;
            if ([k.textString isEqualToString:@"code"] && v.type == CBORTypeTextString) code = v.textString;
            else if ([k.textString isEqualToString:@"url"] && v.type == CBORTypeTextString) url = v.textString;
        }];
        if (code.length > 0) {
            [out addObject:[ATProtoS2PAIngredientValidationStatus statusWithCode:code url:url]];
        }
    }
    return out;
}

+ (BOOL)validateFieldsRelationship:(NSString *)relationship
                 digitalSourceType:(NSString *)digitalSourceType
                    activeManifest:(ATProtoS2PAHashedURI *)activeManifest
                validationResults:(ATProtoS2PAIngredientValidationResults *)validationResults
                             error:(NSError **)error {
    if (!S2PAIsValidRelationship(relationship)) {
        S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidArgument,
                      @"relationship must be parentOf, componentOf, or inputTo");
        return NO;
    }
    if (digitalSourceType.length > 0 && activeManifest != nil) {
        S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidArgument,
                      @"activeManifest and digitalSourceType are mutually exclusive");
        return NO;
    }
    if (activeManifest != nil && validationResults == nil) {
        S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidArgument,
                      @"validationResults required when activeManifest is present");
        return NO;
    }
    return YES;
}

+ (nullable instancetype)parentOfWithTitle:(NSString *)title
                                    format:(NSString *)format
                                instanceID:(NSString *)instanceID
                            activeManifest:(ATProtoS2PAHashedURI *)activeManifest
                            claimSignature:(ATProtoS2PAHashedURI *)claimSignature
                        validationResults:(ATProtoS2PAIngredientValidationResults *)validationResults
                                     error:(NSError **)error {
    if (![self validateFieldsRelationship:ATProtoS2PAIngredientRelationshipParentOf
                        digitalSourceType:nil
                           activeManifest:activeManifest
                       validationResults:validationResults
                                    error:error]) {
        return nil;
    }
    return [[self alloc] initWithRelationship:ATProtoS2PAIngredientRelationshipParentOf
                                        title:title
                                       format:format
                                   instanceID:instanceID
                              descriptionText:nil
                            digitalSourceType:nil
                               activeManifest:activeManifest
                               claimSignature:claimSignature
                           validationResults:validationResults];
}

+ (nullable instancetype)inputToWithDigitalSourceType:(NSString *)digitalSourceType
                                                title:(NSString *)title
                                               format:(NSString *)format
                                                error:(NSError **)error {
    if (digitalSourceType.length == 0) {
        S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidArgument,
                      @"digitalSourceType is required for inputTo helper");
        return nil;
    }
    if (![self validateFieldsRelationship:ATProtoS2PAIngredientRelationshipInputTo
                        digitalSourceType:digitalSourceType
                           activeManifest:nil
                       validationResults:nil
                                    error:error]) {
        return nil;
    }
    return [[self alloc] initWithRelationship:ATProtoS2PAIngredientRelationshipInputTo
                                        title:title
                                       format:format
                                   instanceID:nil
                              descriptionText:nil
                            digitalSourceType:digitalSourceType
                               activeManifest:nil
                               claimSignature:nil
                           validationResults:nil];
}

+ (nullable NSString *)labelFromJUMDBody:(const uint8_t *)body length:(NSUInteger)len {
    if (len < 18 || (body[16] & 0x02) == 0) return nil;
    NSUInteger start = 17, end = 17;
    while (end < len && body[end] != 0) end++;
    if (end >= len) return nil;
    return [[NSString alloc] initWithBytes:body + start length:end - start encoding:NSUTF8StringEncoding];
}

+ (nullable NSData *)sha256HashForJUMBF:(NSData *)jumb error:(NSError **)error {
    if (jumb.length < 8 || memcmp(jumb.bytes + 4, "jumb", 4) != 0) {
        S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidStructure,
                      @"expected jumb superbox");
        return nil;
    }
    if (S2PAReadU32(jumb.bytes) != jumb.length) {
        S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidStructure,
                      @"jumb size mismatch");
        return nil;
    }
    NSData *body = [jumb subdataWithRange:NSMakeRange(8, jumb.length - 8)];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(body.bytes, (CC_LONG)body.length, digest);
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

+ (nullable NSData *)relabelJUMB:(NSData *)jumb newLabel:(NSString *)label error:(NSError **)error {
    if (jumb.length < 16 || memcmp(jumb.bytes + 4, "jumb", 4) != 0) {
        S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidStructure,
                      @"relabel requires jumb");
        return nil;
    }
    const uint8_t *bytes = jumb.bytes;
    uint32_t jumdSize = S2PAReadU32(bytes + 8);
    if (jumdSize < 8 || 8 + jumdSize > jumb.length || memcmp(bytes + 12, "jumd", 4) != 0) {
        S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidStructure,
                      @"jumb missing jumd");
        return nil;
    }
    const uint8_t *oldJumdBody = bytes + 16;
    NSUInteger oldJumdBodyLen = jumdSize - 8;
    if (oldJumdBodyLen < 17) {
        S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidStructure,
                      @"jumd body truncated");
        return nil;
    }
    NSMutableData *newJumdBody = [NSMutableData data];
    [newJumdBody appendBytes:oldJumdBody length:16]; // type UUID
    uint8_t toggles = 0x03;
    [newJumdBody appendBytes:&toggles length:1];
    [newJumdBody appendData:[label dataUsingEncoding:NSUTF8StringEncoding]];
    uint8_t nul = 0;
    [newJumdBody appendBytes:&nul length:1];
    NSMutableData *newJumd = [NSMutableData data];
    S2PAAppendU32((uint32_t)(8 + newJumdBody.length), newJumd);
    [newJumd appendBytes:"jumd" length:4];
    [newJumd appendData:newJumdBody];
    NSData *rest = [jumb subdataWithRange:NSMakeRange(8 + jumdSize, jumb.length - 8 - jumdSize)];
    NSMutableData *out = [NSMutableData data];
    S2PAAppendU32((uint32_t)(8 + newJumd.length + rest.length), out);
    [out appendBytes:"jumb" length:4];
    [out appendData:newJumd];
    [out appendData:rest];
    return out;
}

+ (nullable NSData *)firstChildJUMBLabeled:(NSString *)want
                                   inStore:(NSData *)store
                                     error:(NSError **)error {
    if (store.length < 8 || memcmp(store.bytes + 4, "jumb", 4) != 0) {
        S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidStructure,
                      @"store must be jumb");
        return nil;
    }
    const uint8_t *bytes = store.bytes;
    uint32_t jumdSize = S2PAReadU32(bytes + 8);
    if (jumdSize < 8 || 8 + jumdSize > store.length) {
        S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidStructure,
                      @"store jumd invalid");
        return nil;
    }
    NSUInteger offset = 8 + jumdSize;
    while (offset + 8 <= store.length) {
        uint32_t size = S2PAReadU32(bytes + offset);
        if (size < 8 || offset + size > store.length) {
            S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidStructure,
                          @"store child invalid");
            return nil;
        }
        if (memcmp(bytes + offset + 4, "jumb", 4) == 0 && size >= 16) {
            uint32_t childJumd = S2PAReadU32(bytes + offset + 8);
            if (childJumd >= 8 && 8 + childJumd <= size &&
                memcmp(bytes + offset + 12, "jumd", 4) == 0) {
                NSString *label = [self labelFromJUMDBody:bytes + offset + 16 length:childJumd - 8];
                if ([label isEqualToString:want]) {
                    return [NSData dataWithBytes:bytes + offset length:size];
                }
            }
        }
        offset += size;
    }
    S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorMissingTarget,
                  @"labelled jumb not found");
    return nil;
}

+ (nullable NSData *)findJUMBLabeled:(NSString *)want
                            inBytes:(const uint8_t *)root
                             length:(NSUInteger)length
                              error:(NSError **)error {
    NSMutableArray<NSValue *> *stack = [NSMutableArray array];
    [stack addObject:[NSValue valueWithRange:NSMakeRange(0, length)]];
    while (stack.count > 0) {
        NSRange range = stack.lastObject.rangeValue;
        [stack removeLastObject];
        const uint8_t *b = root + range.location;
        NSUInteger len = range.length;
        NSUInteger offset = 0;
        while (offset + 8 <= len) {
            uint32_t size = S2PAReadU32(b + offset);
            if (size < 8 || offset + size > len) {
                S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidStructure,
                              @"invalid box while locating labelled jumb");
                return nil;
            }
            if (memcmp(b + offset + 4, "jumb", 4) == 0) {
                if (size >= 16) {
                    uint32_t jumdSize = S2PAReadU32(b + offset + 8);
                    if (jumdSize >= 8 && 8 + jumdSize <= size &&
                        memcmp(b + offset + 12, "jumd", 4) == 0) {
                        NSString *label = [self labelFromJUMDBody:b + offset + 16 length:jumdSize - 8];
                        if ([label isEqualToString:want]) {
                            return [NSData dataWithBytes:b + offset length:size];
                        }
                    }
                }
                [stack addObject:[NSValue valueWithRange:NSMakeRange(range.location + offset + 8,
                                                                     size - 8)]];
            }
            offset += size;
        }
    }
    S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorMissingTarget,
                  @"labelled jumb not found in store");
    return nil;
}

+ (nullable instancetype)parentOfEmbeddingChildStore:(NSData *)childStore
                                          instanceID:(NSString *)instanceID
                                               title:(NSString *)title
                                              format:(NSString *)format
                               outEmbeddedManifestJUMBF:(NSData **)outEmbeddedManifestJUMBF
                                               error:(NSError **)error {
    if (instanceID.length == 0 || childStore.length < 8) {
        S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidArgument,
                      @"childStore and instanceID are required");
        return nil;
    }
    // Child store: outer c2pa → active c2pa manifest.
    NSData *active = [self firstChildJUMBLabeled:@"c2pa" inStore:childStore error:error];
    if (!active) return nil;
    NSData *embedded = [self relabelJUMB:active newLabel:instanceID error:error];
    if (!embedded) return nil;
    NSData *sigBox = [self findJUMBLabeled:@"c2pa.signature"
                                   inBytes:embedded.bytes
                                    length:embedded.length
                                     error:error];
    if (!sigBox) return nil;
    NSData *manifestDigest = [self sha256HashForJUMBF:embedded error:error];
    if (!manifestDigest) return nil;
    NSData *sigDigest = [self sha256HashForJUMBF:sigBox error:error];
    if (!sigDigest) return nil;
    NSString *manifestURL = [NSString stringWithFormat:@"self#jumbf=/c2pa/%@", instanceID];
    NSString *sigURL = [NSString stringWithFormat:@"self#jumbf=/c2pa/%@/c2pa.signature", instanceID];
    ATProtoS2PAHashedURI *manifestURI =
        [ATProtoS2PAHashedURI hashedURIWithURL:manifestURL digest:manifestDigest alg:nil];
    ATProtoS2PAHashedURI *sigURI =
        [ATProtoS2PAHashedURI hashedURIWithURL:sigURL digest:sigDigest alg:nil];
    ATProtoS2PAIngredientValidationResults *results =
        [ATProtoS2PAIngredientValidationResults resultsWithSingleSuccessCode:@"claimSignature.validated"
                                                                         url:sigURL];
    if (outEmbeddedManifestJUMBF) *outEmbeddedManifestJUMBF = embedded;
    return [self parentOfWithTitle:title
                            format:format
                        instanceID:instanceID
                    activeManifest:manifestURI
                    claimSignature:sigURI
                validationResults:results
                             error:error];
}

- (BOOL)verifyEmbeddedManifestsInStore:(NSData *)manifestStore error:(NSError **)error {
    if (!self.activeManifest && !self.claimSignature) return YES;
    if (manifestStore.length < 8) {
        S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidArgument,
                      @"manifest store required");
        return NO;
    }
    if (self.activeManifest) {
        NSString *prefix = @"self#jumbf=/c2pa/";
        if (![self.activeManifest.url hasPrefix:prefix]) {
            S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidStructure,
                          @"activeManifest url must be self#jumbf=/c2pa/<id>");
            return NO;
        }
        NSString *rest = [self.activeManifest.url substringFromIndex:prefix.length];
        NSString *label = [rest componentsSeparatedByString:@"/"].firstObject;
        NSData *box = [[self class] findJUMBLabeled:label
                                            inBytes:manifestStore.bytes
                                             length:manifestStore.length
                                              error:error];
        if (!box) return NO;
        NSData *digest = [[self class] sha256HashForJUMBF:box error:error];
        if (!digest) return NO;
        if (![digest isEqualToData:self.activeManifest.digest]) {
            S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorHashMismatch,
                          @"activeManifest digest mismatch");
            return NO;
        }
        if (self.claimSignature) {
            NSString *sigSuffix = @"/c2pa.signature";
            if (![self.claimSignature.url hasSuffix:sigSuffix]) {
                S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidStructure,
                              @"claimSignature url must end with /c2pa.signature");
                return NO;
            }
            NSData *sigBox = [[self class] findJUMBLabeled:@"c2pa.signature"
                                                   inBytes:box.bytes
                                                    length:box.length
                                                     error:error];
            if (!sigBox) return NO;
            NSData *sigDigest = [[self class] sha256HashForJUMBF:sigBox error:error];
            if (!sigDigest) return NO;
            if (![sigDigest isEqualToData:self.claimSignature.digest]) {
                S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorHashMismatch,
                              @"claimSignature digest mismatch");
                return NO;
            }
        }
    }
    return YES;
}

- (nullable NSData *)encodeCBOR:(NSError **)error {
    if (![[self class] validateFieldsRelationship:self.relationship
                                digitalSourceType:self.digitalSourceType
                                   activeManifest:self.activeManifest
                               validationResults:self.validationResults
                                            error:error]) {
        return nil;
    }
    NSMutableDictionary *dict = [@{
        S2PAText(@"relationship"): S2PAText(self.relationship),
    } mutableCopy];
    if (self.title.length > 0) dict[S2PAText(@"dc:title")] = S2PAText(self.title);
    if (self.format.length > 0) dict[S2PAText(@"dc:format")] = S2PAText(self.format);
    if (self.instanceID.length > 0) dict[S2PAText(@"instanceID")] = S2PAText(self.instanceID);
    if (self.descriptionText.length > 0) {
        dict[S2PAText(@"description")] = S2PAText(self.descriptionText);
    }
    if (self.digitalSourceType.length > 0) {
        dict[S2PAText(@"digitalSourceType")] = S2PAText(self.digitalSourceType);
    }
    if (self.activeManifest) {
        ATProtoCBORValue *m = [[self class] cborForHashedURI:self.activeManifest error:error];
        if (!m) return nil;
        dict[S2PAText(@"activeManifest")] = m;
    }
    if (self.claimSignature) {
        ATProtoCBORValue *m = [[self class] cborForHashedURI:self.claimSignature error:error];
        if (!m) return nil;
        dict[S2PAText(@"claimSignature")] = m;
    }
    if (self.validationResults) {
        ATProtoCBORValue *success =
            [[self class] cborForStatusList:self.validationResults.success error:error];
        if (!success) return nil;
        ATProtoCBORValue *info =
            [[self class] cborForStatusList:self.validationResults.informational error:error];
        if (!info) return nil;
        ATProtoCBORValue *failure =
            [[self class] cborForStatusList:self.validationResults.failure error:error];
        if (!failure) return nil;
        dict[S2PAText(@"validationResults")] = [ATProtoCBORValue map:@{
            S2PAText(@"activeManifest"): [ATProtoCBORValue map:@{
                S2PAText(@"success"): success,
                S2PAText(@"informational"): info,
                S2PAText(@"failure"): failure,
            }],
        }];
    }
    NSData *encoded = [[ATProtoCBORValue map:dict] encode];
    if (!encoded) {
        S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidStructure,
                      @"failed to encode ingredient CBOR");
    }
    return encoded;
}

+ (nullable instancetype)assertionFromCBOR:(NSData *)cbor error:(NSError **)error {
    if (![cbor isKindOfClass:[NSData class]] || cbor.length == 0) {
        S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidArgument,
                      @"ingredient CBOR is empty");
        return nil;
    }
    NSUInteger offset = 0;
    ATProtoCBORValue *root = [ATProtoCBORDecoder decode:cbor offset:&offset];
    if (!root || offset != cbor.length || root.type != CBORTypeMap) {
        S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidStructure,
                      @"ingredient must be a single CBOR map");
        return nil;
    }
    if (![root.encode isEqualToData:cbor]) {
        S2PAIngSetErr(error, ATProtoS2PAIngredientAssertionErrorInvalidStructure,
                      @"ingredient CBOR must be canonical");
        return nil;
    }
    __block NSString *relationship = nil;
    __block NSString *title = nil;
    __block NSString *format = nil;
    __block NSString *instanceID = nil;
    __block NSString *descriptionText = nil;
    __block NSString *digitalSourceType = nil;
    __block ATProtoS2PAHashedURI *activeManifest = nil;
    __block ATProtoS2PAHashedURI *claimSignature = nil;
    __block ATProtoS2PAIngredientValidationResults *validationResults = nil;
    [root.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *key, ATProtoCBORValue *val,
                                                  BOOL *stop) {
        (void)stop;
        if (key.type != CBORTypeTextString) return;
        NSString *k = key.textString;
        if ([k isEqualToString:@"relationship"] && val.type == CBORTypeTextString) {
            relationship = val.textString;
        } else if ([k isEqualToString:@"dc:title"] && val.type == CBORTypeTextString) {
            title = val.textString;
        } else if ([k isEqualToString:@"dc:format"] && val.type == CBORTypeTextString) {
            format = val.textString;
        } else if ([k isEqualToString:@"instanceID"] && val.type == CBORTypeTextString) {
            instanceID = val.textString;
        } else if ([k isEqualToString:@"description"] && val.type == CBORTypeTextString) {
            descriptionText = val.textString;
        } else if ([k isEqualToString:@"digitalSourceType"] && val.type == CBORTypeTextString) {
            digitalSourceType = val.textString;
        } else if ([k isEqualToString:@"activeManifest"]) {
            activeManifest = [self hashedURIFromCBORMap:val];
        } else if ([k isEqualToString:@"claimSignature"]) {
            claimSignature = [self hashedURIFromCBORMap:val];
        } else if ([k isEqualToString:@"validationResults"] && val.type == CBORTypeMap) {
            __block ATProtoCBORValue *activeMap = nil;
            [val.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *vk, ATProtoCBORValue *vv,
                                                         BOOL *s2) {
                (void)s2;
                if (vk.type == CBORTypeTextString &&
                    [vk.textString isEqualToString:@"activeManifest"] &&
                    vv.type == CBORTypeMap) {
                    activeMap = vv;
                }
            }];
            if (activeMap) {
                __block NSArray *success = @[];
                __block NSArray *info = @[];
                __block NSArray *failure = @[];
                [activeMap.map enumerateKeysAndObjectsUsingBlock:^(ATProtoCBORValue *ak,
                                                                   ATProtoCBORValue *av, BOOL *s3) {
                    (void)s3;
                    if (ak.type != CBORTypeTextString) return;
                    if ([ak.textString isEqualToString:@"success"]) {
                        success = [self statusListFromCBOR:av];
                    } else if ([ak.textString isEqualToString:@"informational"]) {
                        info = [self statusListFromCBOR:av];
                    } else if ([ak.textString isEqualToString:@"failure"]) {
                        failure = [self statusListFromCBOR:av];
                    }
                }];
                validationResults = [ATProtoS2PAIngredientValidationResults resultsWithSuccess:success
                                                                                informational:info
                                                                                      failure:failure];
            }
        }
    }];
    if (![self validateFieldsRelationship:relationship
                        digitalSourceType:digitalSourceType
                           activeManifest:activeManifest
                       validationResults:validationResults
                                    error:error]) {
        return nil;
    }
    return [[self alloc] initWithRelationship:relationship
                                        title:title
                                       format:format
                                   instanceID:instanceID
                              descriptionText:descriptionText
                            digitalSourceType:digitalSourceType
                               activeManifest:activeManifest
                               claimSignature:claimSignature
                           validationResults:validationResults];
}

@end
