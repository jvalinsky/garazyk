// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Security/S2PA/ATProtoS2PAIngredientAssertion.h"
#import "Core/CBOR.h"
#import <CommonCrypto/CommonDigest.h>

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

@interface ATProtoS2PAIngredientAssertion ()
@property (nonatomic, copy, readwrite) NSString *relationship;
@property (nonatomic, copy, readwrite, nullable) NSString *title;
@property (nonatomic, copy, readwrite, nullable) NSString *format;
@property (nonatomic, copy, readwrite, nullable) NSString *instanceID;
@property (nonatomic, copy, readwrite, nullable) NSString *descriptionText;
@property (nonatomic, copy, readwrite, nullable) NSString *digitalSourceType;
@property (nonatomic, strong, readwrite, nullable) ATProtoS2PAHashedURI *activeManifest;
@property (nonatomic, strong, readwrite, nullable) ATProtoS2PAHashedURI *claimSignature;
@end

@implementation ATProtoS2PAIngredientAssertion

- (instancetype)initWithRelationship:(NSString *)relationship
                               title:(NSString *)title
                              format:(NSString *)format
                          instanceID:(NSString *)instanceID
                     descriptionText:(NSString *)descriptionText
                   digitalSourceType:(NSString *)digitalSourceType
                      activeManifest:(ATProtoS2PAHashedURI *)activeManifest
                      claimSignature:(ATProtoS2PAHashedURI *)claimSignature {
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

+ (BOOL)validateFieldsRelationship:(NSString *)relationship
                 digitalSourceType:(NSString *)digitalSourceType
                    activeManifest:(ATProtoS2PAHashedURI *)activeManifest
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
    return YES;
}

+ (nullable instancetype)parentOfWithTitle:(NSString *)title
                                    format:(NSString *)format
                                instanceID:(NSString *)instanceID
                            activeManifest:(ATProtoS2PAHashedURI *)activeManifest
                            claimSignature:(ATProtoS2PAHashedURI *)claimSignature
                                     error:(NSError **)error {
    if (![self validateFieldsRelationship:ATProtoS2PAIngredientRelationshipParentOf
                        digitalSourceType:nil
                           activeManifest:activeManifest
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
                               claimSignature:claimSignature];
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
                               claimSignature:nil];
}

- (nullable NSData *)encodeCBOR:(NSError **)error {
    if (![[self class] validateFieldsRelationship:self.relationship
                                digitalSourceType:self.digitalSourceType
                                   activeManifest:self.activeManifest
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
        }
    }];
    if (![self validateFieldsRelationship:relationship
                        digitalSourceType:digitalSourceType
                           activeManifest:activeManifest
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
                               claimSignature:claimSignature];
}

@end
