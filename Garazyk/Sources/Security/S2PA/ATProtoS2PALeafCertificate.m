// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Security/S2PA/ATProtoS2PALeafCertificate.h"
#import <CommonCrypto/CommonDigest.h>
#include <string.h>

NSString * const ATProtoS2PALeafErrorDomain = @"com.atproto.s2pa.leaf";

static NSError *S2PALeafError(ATProtoS2PALeafErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoS2PALeafErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void S2PALeafSetError(NSError **error, ATProtoS2PALeafErrorCode code,
                             NSString *message) {
    if (error) *error = S2PALeafError(code, message);
}

static void S2PAAppend(NSMutableData *data, const void *bytes, NSUInteger length) {
    [data appendBytes:bytes length:length];
}

static void S2PAAppendTagLength(NSMutableData *data, uint8_t tag, NSUInteger length) {
    uint8_t header[6];
    NSUInteger headerLen = 1;
    header[0] = tag;
    if (length < 0x80) {
        header[1] = (uint8_t)length;
        headerLen = 2;
    } else if (length <= 0xFF) {
        header[1] = 0x81;
        header[2] = (uint8_t)length;
        headerLen = 3;
    } else if (length <= 0xFFFF) {
        header[1] = 0x82;
        header[2] = (uint8_t)(length >> 8);
        header[3] = (uint8_t)length;
        headerLen = 4;
    } else {
        header[1] = 0x83;
        header[2] = (uint8_t)(length >> 16);
        header[3] = (uint8_t)(length >> 8);
        header[4] = (uint8_t)length;
        headerLen = 5;
    }
    S2PAAppend(data, header, headerLen);
}

static NSData *S2PAWrap(uint8_t tag, NSData *content) {
    NSMutableData *out = [NSMutableData dataWithCapacity:8 + content.length];
    S2PAAppendTagLength(out, tag, content.length);
    [out appendData:content];
    return out;
}

static NSData *S2PAOID(const uint8_t *bytes, NSUInteger length) {
    return S2PAWrap(0x06, [NSData dataWithBytes:bytes length:length]);
}

static NSData *S2PAIntegerFromBytes(NSData *bytes, BOOL forcePositive) {
    NSMutableData *value = [bytes mutableCopy];
    if (forcePositive && value.length > 0 &&
        (((const uint8_t *)value.bytes)[0] & 0x80) != 0) {
        NSMutableData *prefixed = [NSMutableData dataWithCapacity:value.length + 1];
        uint8_t zero = 0;
        [prefixed appendBytes:&zero length:1];
        [prefixed appendData:value];
        value = prefixed;
    }
    // Strip redundant leading zeros while keeping at least one byte and sign bit.
    while (value.length > 1) {
        const uint8_t *b = value.bytes;
        if (b[0] == 0x00 && (b[1] & 0x80) == 0) {
            value = [[value subdataWithRange:NSMakeRange(1, value.length - 1)] mutableCopy];
        } else {
            break;
        }
    }
    return S2PAWrap(0x02, value);
}

static NSData *S2PAUTF8String(NSString *string) {
    NSData *utf8 = [string dataUsingEncoding:NSUTF8StringEncoding];
    return S2PAWrap(0x0C, utf8); // UTF8String
}

static NSData *S2PATime(NSDate *date) {
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSDateComponents *components = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth |
                                                         NSCalendarUnitDay | NSCalendarUnitHour |
                                                         NSCalendarUnitMinute | NSCalendarUnitSecond)
                                               fromDate:date];
    NSInteger year = components.year;
    char buf[32];
    if (year >= 1950 && year <= 2049) {
        snprintf(buf, sizeof(buf), "%02d%02d%02d%02d%02d%02dZ",
                 (int)(year % 100), (int)components.month, (int)components.day,
                 (int)components.hour, (int)components.minute, (int)components.second);
        return S2PAWrap(0x17, [NSData dataWithBytes:buf length:13]); // UTCTime
    }
    snprintf(buf, sizeof(buf), "%04d%02d%02d%02d%02d%02dZ",
             (int)year, (int)components.month, (int)components.day,
             (int)components.hour, (int)components.minute, (int)components.second);
    return S2PAWrap(0x18, [NSData dataWithBytes:buf length:15]); // GeneralizedTime
}

static NSData *S2PABitString(NSData *bytes, uint8_t unusedBits) {
    NSMutableData *content = [NSMutableData dataWithCapacity:1 + bytes.length];
    [content appendBytes:&unusedBits length:1];
    [content appendData:bytes];
    return S2PAWrap(0x03, content);
}

static NSData *S2PABool(BOOL value) {
    uint8_t b = value ? 0xFF : 0x00;
    return S2PAWrap(0x01, [NSData dataWithBytes:&b length:1]);
}

static BOOL S2PAReadTLV(const uint8_t *bytes, NSUInteger length, NSUInteger *offset,
                        uint8_t *outTag, NSData **outContent) {
    if (*offset >= length) return NO;
    uint8_t tag = bytes[*offset];
    NSUInteger i = *offset + 1;
    if (i >= length) return NO;
    NSUInteger len = bytes[i++];
    if (len & 0x80) {
        NSUInteger nbytes = len & 0x7F;
        if (nbytes == 0 || nbytes > 3 || i + nbytes > length) return NO;
        len = 0;
        for (NSUInteger n = 0; n < nbytes; n++) {
            len = (len << 8) | bytes[i++];
        }
    }
    if (i + len > length) return NO;
    if (outTag) *outTag = tag;
    if (outContent) *outContent = [NSData dataWithBytes:bytes + i length:len];
    *offset = i + len;
    return YES;
}

static BOOL S2PAExpectTag(NSData *data, uint8_t tag, NSData **outContent) {
    NSUInteger offset = 0;
    uint8_t actual = 0;
    NSData *content = nil;
    if (!S2PAReadTLV(data.bytes, data.length, &offset, &actual, &content) ||
        actual != tag || offset != data.length) {
        return NO;
    }
    if (outContent) *outContent = content;
    return YES;
}

@implementation ATProtoS2PALeafCertificate

+ (NSData *)subjectKeyIdentifierForPublicKey:(NSData *)uncompressedPublicKey {
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(uncompressedPublicKey.bytes, (CC_LONG)uncompressedPublicKey.length, digest);
    return [NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
}

+ (nullable NSData *)certificateWithKeyPair:(ATProtoSecp256k1KeyPair *)keyPair
                                        did:(nullable NSString *)did
                                  notBefore:(NSDate *)notBefore
                                   notAfter:(NSDate *)notAfter
                                      error:(NSError **)error {
    if (![keyPair isKindOfClass:[ATProtoSecp256k1KeyPair class]] ||
        keyPair.publicKey.length != 65 ||
        ((const uint8_t *)keyPair.publicKey.bytes)[0] != 0x04 ||
        ![notBefore isKindOfClass:[NSDate class]] ||
        ![notAfter isKindOfClass:[NSDate class]] ||
        [notAfter compare:notBefore] != NSOrderedDescending) {
        S2PALeafSetError(error, ATProtoS2PALeafErrorInvalidArgument,
                         @"S2PA leaf requires secp256k1 key pair and notAfter > notBefore");
        return nil;
    }
    NSString *boundDID = did.length > 0 ? did : [keyPair didKeyString];
    if (boundDID.length == 0 || ![boundDID hasPrefix:@"did:"]) {
        S2PALeafSetError(error, ATProtoS2PALeafErrorInvalidArgument,
                         @"S2PA leaf DID must be a did: URI");
        return nil;
    }

    NSData *keyID = [self subjectKeyIdentifierForPublicKey:keyPair.publicKey];
    NSData *serial = S2PAIntegerFromBytes(keyID, YES);

    // AlgorithmIdentifier: ecdsa-with-SHA256
    static const uint8_t kECDSAWithSHA256[] = {
        0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02
    };
    NSData *sigAlg = S2PAWrap(0x30, ({
        NSMutableData *seq = [NSMutableData data];
        [seq appendData:S2PAOID(kECDSAWithSHA256, sizeof(kECDSAWithSHA256))];
        seq;
    }));

    // Name: SEQUENCE of SET of SEQUENCE { OID commonName, UTF8String did }
    static const uint8_t kCommonNameOID[] = {0x55, 0x04, 0x03}; // 2.5.4.3
    NSData *cnAttr = S2PAWrap(0x30, ({
        NSMutableData *attr = [NSMutableData data];
        [attr appendData:S2PAOID(kCommonNameOID, sizeof(kCommonNameOID))];
        [attr appendData:S2PAUTF8String(boundDID)];
        attr;
    }));
    NSData *name = S2PAWrap(0x30, S2PAWrap(0x31, cnAttr)); // RDNSequence / SET

    NSData *validity = S2PAWrap(0x30, ({
        NSMutableData *v = [NSMutableData data];
        [v appendData:S2PATime(notBefore)];
        [v appendData:S2PATime(notAfter)];
        v;
    }));

    // subjectPublicKeyInfo
    static const uint8_t kIDECPublicKey[] = {0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01};
    static const uint8_t kSecp256k1[] = {0x2B, 0x81, 0x04, 0x00, 0x0A};
    NSData *algID = S2PAWrap(0x30, ({
        NSMutableData *a = [NSMutableData data];
        [a appendData:S2PAOID(kIDECPublicKey, sizeof(kIDECPublicKey))];
        [a appendData:S2PAOID(kSecp256k1, sizeof(kSecp256k1))];
        a;
    }));
    NSData *spki = S2PAWrap(0x30, ({
        NSMutableData *s = [NSMutableData data];
        [s appendData:algID];
        [s appendData:S2PABitString(keyPair.publicKey, 0)];
        s;
    }));

    // Extensions
    static const uint8_t kBasicConstraintsOID[] = {0x55, 0x1D, 0x13};
    static const uint8_t kKeyUsageOID[] = {0x55, 0x1D, 0x0F};
    static const uint8_t kExtKeyUsageOID[] = {0x55, 0x1D, 0x25};
    static const uint8_t kSKIOID[] = {0x55, 0x1D, 0x0E};
    static const uint8_t kAKIOID[] = {0x55, 0x1D, 0x23};
    static const uint8_t kEmailProtectionOID[] = {
        0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x04
    };

    NSData *basicConstraintsValue = S2PAWrap(0x30, S2PABool(NO)); // cA=FALSE
    NSData *basicConstraints = S2PAWrap(0x30, ({
        NSMutableData *e = [NSMutableData data];
        [e appendData:S2PAOID(kBasicConstraintsOID, sizeof(kBasicConstraintsOID))];
        [e appendData:S2PABool(YES)]; // critical
        [e appendData:S2PAWrap(0x04, basicConstraintsValue)];
        e;
    }));

    // digitalSignature bit 0 → bits 80 with unusedBits=7
    NSData *keyUsageBits = S2PABitString([NSData dataWithBytes:(const uint8_t[]){0x80} length:1], 7);
    NSData *keyUsage = S2PAWrap(0x30, ({
        NSMutableData *e = [NSMutableData data];
        [e appendData:S2PAOID(kKeyUsageOID, sizeof(kKeyUsageOID))];
        [e appendData:S2PABool(YES)];
        [e appendData:S2PAWrap(0x04, keyUsageBits)];
        e;
    }));

    NSData *ekuValue = S2PAWrap(0x30, S2PAOID(kEmailProtectionOID, sizeof(kEmailProtectionOID)));
    NSData *extKeyUsage = S2PAWrap(0x30, ({
        NSMutableData *e = [NSMutableData data];
        [e appendData:S2PAOID(kExtKeyUsageOID, sizeof(kExtKeyUsageOID))];
        [e appendData:S2PAWrap(0x04, ekuValue)];
        e;
    }));

    NSData *skiValue = S2PAWrap(0x04, keyID);
    NSData *subjectKeyIdentifier = S2PAWrap(0x30, ({
        NSMutableData *e = [NSMutableData data];
        [e appendData:S2PAOID(kSKIOID, sizeof(kSKIOID))];
        [e appendData:S2PAWrap(0x04, skiValue)];
        e;
    }));

    // authorityKeyIdentifier: [0] KeyIdentifier
    NSData *akiInner = S2PAWrap(0x80, keyID);
    NSData *akiValue = S2PAWrap(0x30, akiInner);
    NSData *authorityKeyIdentifier = S2PAWrap(0x30, ({
        NSMutableData *e = [NSMutableData data];
        [e appendData:S2PAOID(kAKIOID, sizeof(kAKIOID))];
        [e appendData:S2PAWrap(0x04, akiValue)];
        e;
    }));

    NSData *extensions = S2PAWrap(0xA3, S2PAWrap(0x30, ({
        NSMutableData *all = [NSMutableData data];
        [all appendData:basicConstraints];
        [all appendData:keyUsage];
        [all appendData:extKeyUsage];
        [all appendData:subjectKeyIdentifier];
        [all appendData:authorityKeyIdentifier];
        all;
    })));

    NSData *tbs = S2PAWrap(0x30, ({
        NSMutableData *body = [NSMutableData data];
        // version v3 = [0] EXPLICIT INTEGER 2
        [body appendData:S2PAWrap(0xA0, S2PAIntegerFromBytes([NSData dataWithBytes:(const uint8_t[]){0x02} length:1], NO))];
        [body appendData:serial];
        [body appendData:sigAlg];
        [body appendData:name]; // issuer
        [body appendData:validity];
        [body appendData:name]; // subject
        [body appendData:spki];
        [body appendData:extensions];
        body;
    }));

    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(tbs.bytes, (CC_LONG)tbs.length, digest);
    NSData *hash = [NSData dataWithBytes:digest length:sizeof(digest)];
    NSError *signError = nil;
    NSData *derSig = [keyPair signHash:hash error:&signError];
    if (!derSig) {
        if (error) *error = signError ?: S2PALeafError(ATProtoS2PALeafErrorEncodingFailed,
                                                       @"S2PA leaf signing failed");
        return nil;
    }

    NSData *cert = S2PAWrap(0x30, ({
        NSMutableData *c = [NSMutableData data];
        [c appendData:tbs];
        [c appendData:sigAlg];
        [c appendData:S2PABitString(derSig, 0)];
        c;
    }));
    return cert;
}

+ (BOOL)verifyCertificate:(NSData *)derCertificate
              expectedDID:(nullable NSString *)expectedDID
                    error:(NSError **)error {
    if (![derCertificate isKindOfClass:[NSData class]] || derCertificate.length < 64) {
        S2PALeafSetError(error, ATProtoS2PALeafErrorInvalidCertificate,
                         @"S2PA leaf certificate is truncated");
        return NO;
    }
    NSData *certSeq = nil;
    if (!S2PAExpectTag(derCertificate, 0x30, &certSeq)) {
        S2PALeafSetError(error, ATProtoS2PALeafErrorInvalidCertificate,
                         @"S2PA leaf must be a DER SEQUENCE");
        return NO;
    }

    NSUInteger offset = 0;
    const uint8_t *bytes = certSeq.bytes;
    NSUInteger length = certSeq.length;
    uint8_t tag = 0;
    NSData *tbsContent = nil;
    NSUInteger tbsStart = offset;
    if (!S2PAReadTLV(bytes, length, &offset, &tag, &tbsContent) || tag != 0x30) {
        S2PALeafSetError(error, ATProtoS2PALeafErrorInvalidCertificate,
                         @"S2PA leaf missing TBSCertificate");
        return NO;
    }
    // Reconstruct TBS TLV bytes for hashing.
    NSData *tbs = [certSeq subdataWithRange:NSMakeRange(tbsStart, offset - tbsStart)];

    NSData *alg = nil;
    if (!S2PAReadTLV(bytes, length, &offset, &tag, &alg) || tag != 0x30) {
        S2PALeafSetError(error, ATProtoS2PALeafErrorInvalidCertificate,
                         @"S2PA leaf missing signatureAlgorithm");
        return NO;
    }
    NSData *sigBits = nil;
    if (!S2PAReadTLV(bytes, length, &offset, &tag, &sigBits) || tag != 0x03 ||
        offset != length || sigBits.length < 2) {
        S2PALeafSetError(error, ATProtoS2PALeafErrorInvalidCertificate,
                         @"S2PA leaf missing signatureValue");
        return NO;
    }
    // BIT STRING: unused bits byte then DER ECDSA signature.
    if (((const uint8_t *)sigBits.bytes)[0] != 0) {
        S2PALeafSetError(error, ATProtoS2PALeafErrorInvalidCertificate,
                         @"S2PA leaf signature BIT STRING must be byte-aligned");
        return NO;
    }
    NSData *derSig = [sigBits subdataWithRange:NSMakeRange(1, sigBits.length - 1)];

    // Walk TBS for subject CN and SPKI public key.
    NSUInteger t = 0;
    const uint8_t *tb = tbsContent.bytes;
    NSUInteger tl = tbsContent.length;
    NSData *field = nil;

    // optional version
    if (t < tl && tb[t] == 0xA0) {
        if (!S2PAReadTLV(tb, tl, &t, &tag, &field)) {
            S2PALeafSetError(error, ATProtoS2PALeafErrorInvalidCertificate,
                             @"S2PA leaf version is malformed");
            return NO;
        }
    }
    // serial, signature, issuer, validity, subject, spki, extensions
    for (NSUInteger i = 0; i < 4; i++) {
        if (!S2PAReadTLV(tb, tl, &t, &tag, &field)) {
            S2PALeafSetError(error, ATProtoS2PALeafErrorInvalidCertificate,
                             @"S2PA leaf TBSCertificate is truncated");
            return NO;
        }
    }
    // subject (5th after optional version skip of serial/sig/issuer/validity — wait)
    // After version: serial, sigAlg, issuer, validity, subject, spki
    // Loop above consumed 4: serial, sigAlg, issuer, validity. Next is subject.
    NSData *subject = nil;
    if (!S2PAReadTLV(tb, tl, &t, &tag, &subject) || tag != 0x30) {
        S2PALeafSetError(error, ATProtoS2PALeafErrorInvalidCertificate,
                         @"S2PA leaf subject is missing");
        return NO;
    }
    NSData *spki = nil;
    if (!S2PAReadTLV(tb, tl, &t, &tag, &spki) || tag != 0x30) {
        S2PALeafSetError(error, ATProtoS2PALeafErrorInvalidCertificate,
                         @"S2PA leaf SPKI is missing");
        return NO;
    }

    // Extract CN from subject RDNSequence.
    NSString *cn = nil;
    NSUInteger s = 0;
    while (s < subject.length) {
        NSData *rdn = nil;
        if (!S2PAReadTLV(subject.bytes, subject.length, &s, &tag, &rdn) || tag != 0x31) break;
        NSUInteger r = 0;
        NSData *attr = nil;
        if (!S2PAReadTLV(rdn.bytes, rdn.length, &r, &tag, &attr) || tag != 0x30) continue;
        NSUInteger a = 0;
        NSData *oid = nil;
        NSData *value = nil;
        uint8_t vtag = 0;
        if (!S2PAReadTLV(attr.bytes, attr.length, &a, &tag, &oid) || tag != 0x06) continue;
        if (!S2PAReadTLV(attr.bytes, attr.length, &a, &vtag, &value)) continue;
        static const uint8_t kCNOID[] = {0x55, 0x04, 0x03};
        if (oid.length == sizeof(kCNOID) && memcmp(oid.bytes, kCNOID, sizeof(kCNOID)) == 0 &&
            (vtag == 0x0C || vtag == 0x13)) {
            cn = [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
        }
    }
    if (cn.length == 0 || ![cn hasPrefix:@"did:"]) {
        S2PALeafSetError(error, ATProtoS2PALeafErrorVerificationFailed,
                         @"S2PA leaf commonName must be a DID");
        return NO;
    }
    if (expectedDID.length > 0 && ![expectedDID isEqualToString:cn]) {
        S2PALeafSetError(error, ATProtoS2PALeafErrorVerificationFailed,
                         @"S2PA leaf DID does not match expectedDID");
        return NO;
    }

    // SPKI → BIT STRING public key
    NSUInteger p = 0;
    NSData *spkiAlg = nil;
    NSData *pubBits = nil;
    if (!S2PAReadTLV(spki.bytes, spki.length, &p, &tag, &spkiAlg) || tag != 0x30 ||
        !S2PAReadTLV(spki.bytes, spki.length, &p, &tag, &pubBits) || tag != 0x03 ||
        pubBits.length < 2 || ((const uint8_t *)pubBits.bytes)[0] != 0) {
        S2PALeafSetError(error, ATProtoS2PALeafErrorInvalidCertificate,
                         @"S2PA leaf SPKI public key is malformed");
        return NO;
    }
    NSData *publicKey = [pubBits subdataWithRange:NSMakeRange(1, pubBits.length - 1)];
    if (publicKey.length != 65 || ((const uint8_t *)publicKey.bytes)[0] != 0x04) {
        S2PALeafSetError(error, ATProtoS2PALeafErrorInvalidCertificate,
                         @"S2PA leaf requires uncompressed secp256k1 public key");
        return NO;
    }

    // Confirm secp256k1 named curve in algorithm parameters.
    NSUInteger aa = 0;
    NSData *ecOID = nil;
    NSData *curveOID = nil;
    if (!S2PAReadTLV(spkiAlg.bytes, spkiAlg.length, &aa, &tag, &ecOID) || tag != 0x06 ||
        !S2PAReadTLV(spkiAlg.bytes, spkiAlg.length, &aa, &tag, &curveOID) || tag != 0x06) {
        S2PALeafSetError(error, ATProtoS2PALeafErrorInvalidCertificate,
                         @"S2PA leaf SPKI algorithm is malformed");
        return NO;
    }
    static const uint8_t kSecp256k1[] = {0x2B, 0x81, 0x04, 0x00, 0x0A};
    if (curveOID.length != sizeof(kSecp256k1) ||
        memcmp(curveOID.bytes, kSecp256k1, sizeof(kSecp256k1)) != 0) {
        S2PALeafSetError(error, ATProtoS2PALeafErrorVerificationFailed,
                         @"S2PA leaf curve must be secp256k1");
        return NO;
    }

    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(tbs.bytes, (CC_LONG)tbs.length, digest);
    NSData *hash = [NSData dataWithBytes:digest length:sizeof(digest)];
    NSError *verifyError = nil;
    BOOL ok = [[ATProtoSecp256k1 shared] verifySignature:derSig
                                                 forHash:hash
                                           withPublicKey:publicKey
                                                   error:&verifyError];
    if (!ok) {
        S2PALeafSetError(error, ATProtoS2PALeafErrorVerificationFailed,
                         verifyError.localizedDescription ?: @"S2PA leaf self-signature failed");
        return NO;
    }

    NSData *expectedSKI = [self subjectKeyIdentifierForPublicKey:publicKey];
    // Scan remaining TBS extensions for SKI/AKI equality (best-effort contains).
    if (t < tl) {
        NSData *extsExplicit = nil;
        if (S2PAReadTLV(tb, tl, &t, &tag, &extsExplicit) && tag == 0xA3) {
            NSData *exts = nil;
            if (S2PAExpectTag(extsExplicit, 0x30, &exts)) {
                NSRange skiRange = [exts rangeOfData:expectedSKI
                                             options:0
                                               range:NSMakeRange(0, exts.length)];
                if (skiRange.location == NSNotFound) {
                    S2PALeafSetError(error, ATProtoS2PALeafErrorVerificationFailed,
                                     @"S2PA leaf subjectKeyIdentifier mismatch");
                    return NO;
                }
            }
        }
    }
    return YES;
}

@end
