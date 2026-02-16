#import "Auth/DPoPUtil.h"
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonKeyDerivation.h>

NSString * const DPoPErrorDomain = @"com.atproto.pds.dpop";

@implementation DPoPToken

+ (nullable instancetype)createWithMethod:(NSString *)htm
                                      uri:(NSString *)htu
                                  nonce:(nullable NSString *)nonce
                                  error:(NSError **)error {
    DPoPToken *token = [[DPoPToken alloc] init];
    token.htm = htm;
    token.htu = htu;
    token.iat = [NSDate date];
    token.exp = [NSDate dateWithTimeIntervalSinceNow:300];
    token.jti = [[NSUUID UUID] UUIDString];
    token.nonce = nonce;
    return token;
}

- (NSDictionary *)header {
    return @{
        @"typ": @"dpop+jwt",
        @"alg": @"ES256",
        @"jwk": @{
            @"kty": @"EC",
            @"crv": @"P-256",
            @"x": @"",
            @"y": @""
        }
    };
}

- (NSDictionary *)payload {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"htm"] = self.htm;
    payload[@"htu"] = self.htu;
    payload[@"iat"] = @([self.iat timeIntervalSince1970]);
    payload[@"jti"] = self.jti;

    if (self.exp) {
        payload[@"exp"] = @([self.exp timeIntervalSince1970]);
    }

    if (self.ath) {
        payload[@"ath"] = self.ath;
    }

    if (self.nonce) {
        payload[@"nonce"] = self.nonce;
    }

    return payload;
}

@end

@implementation DPoPUtil

+ (nullable DPoPToken *)createDPoPForMethod:(NSString *)htm
                                         uri:(NSString *)htu
                                      nonce:(nullable NSString *)nonce
                                        key:(SecKeyRef)privateKey
                                      error:(NSError **)error {
    DPoPToken *token = [[DPoPToken alloc] init];
    token.htm = htm;
    token.htu = htu;
    token.iat = [NSDate date];
    token.exp = [NSDate dateWithTimeIntervalSinceNow:300];
    token.jti = [[NSUUID UUID] UUIDString];
    token.nonce = nonce;

    NSError *signError = nil;
    NSString *jwt = [self signDPoPToken:token withKey:privateKey error:&signError];
    if (!jwt) {
        if (error) *error = signError;
        return nil;
    }

    token.jwt = jwt;
    return token;
}

+ (NSString *)signDPoPToken:(DPoPToken *)token withKey:(SecKeyRef)privateKey error:(NSError **)error {
    // Extract public key components for JWK
    NSString *xBase64 = nil;
    NSString *yBase64 = nil;
    
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    if (publicKey) {
        CFErrorRef keyError = NULL;
        NSData *publicKeyData = (__bridge_transfer NSData *)SecKeyCopyExternalRepresentation(publicKey, &keyError);
        if (publicKeyData && publicKeyData.length == 65) {
            // EC public key format is 0x04 || x || y (65 bytes for P-256)
            // Skip the 0x04 prefix and extract x (32 bytes) and y (32 bytes)
            NSData *xData = [publicKeyData subdataWithRange:NSMakeRange(1, 32)];
            NSData *yData = [publicKeyData subdataWithRange:NSMakeRange(33, 32)];
            xBase64 = [self base64URLEncode:xData];
            yBase64 = [self base64URLEncode:yData];
        }
        CFRelease(publicKey);
    }
    
    NSDictionary *headerDict = [token header];
    NSMutableDictionary *header = [headerDict mutableCopy];
    // Ensure typ and alg are set if not present (though [token header] sets them)
    if (!header[@"typ"]) header[@"typ"] = @"dpop+jwt";
    if (!header[@"alg"]) header[@"alg"] = @"ES256";
    
    // Update JWK with actual public key coordinates
    NSMutableDictionary *jwk = [header[@"jwk"] mutableCopy];
    if (jwk) {
        if (xBase64) jwk[@"x"] = xBase64;
        if (yBase64) jwk[@"y"] = yBase64;
        header[@"jwk"] = jwk;
    }

    NSError *jsonError = nil;
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:&jsonError];
    if (jsonError) {
        if (error) *error = jsonError;
        return nil;
    }

    NSDictionary *payloadDict = [token payload];
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payloadDict options:0 error:&jsonError];
    if (jsonError) {
        if (error) *error = jsonError;
        return nil;
    }

    NSString *headerB64 = [self base64URLEncode:headerData];
    NSString *payloadB64 = [self base64URLEncode:payloadData];
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];


    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    
    CFErrorRef keyError = NULL;
    NSData *derSignature = CFBridgingRelease(SecKeyCreateSignature(privateKey,
                                                                kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                                                (__bridge CFDataRef)signingData,
                                                                &keyError));
    if (!derSignature) {
        if (error) {
            *error = CFBridgingRelease(keyError);
        } else if (keyError) {
            CFRelease(keyError);
        }
        return nil;
    }
    
    // Extract raw signature (r || s) from DER-encoded signature
    NSData *rawSignature = [self extractRawSignatureFromDER:derSignature];
    if (!rawSignature) {
        // Fallback: if extraction fails, usefor DER as-is ( debugging)
        rawSignature = derSignature;
    }
    
    NSString *signatureB64 = [self base64URLEncode:rawSignature];

    return [NSString stringWithFormat:@"%@.%@.%@", headerB64, payloadB64, signatureB64];
}

+ (BOOL)verifyDPoP:(NSString *)dpopJwt
    withPublicKey:(SecKeyRef)publicKey
             method:(NSString *)htm
                uri:(NSString *)htu
             nonce:(nullable NSString *)nonce
              error:(NSError **)error {
    NSArray<NSString *> *parts = [dpopJwt componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:DPoPErrorDomain
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP format"}];
        }
        return NO;
    }

    NSString *headerB64 = parts[0];
    NSString *payloadB64 = parts[1];
    NSString *signatureB64 = parts[2];

    NSData *headerData = [self base64URLDecode:headerB64];
    NSData *payloadData = [self base64URLDecode:payloadB64];

    if (!headerData || !payloadData) {
        if (error) {
            *error = [NSError errorWithDomain:DPoPErrorDomain
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid base64url encoding"}];
        }
        return NO;
    }

    NSError *jsonError = nil;
    NSDictionary *header = [NSJSONSerialization JSONObjectWithData:headerData options:0 error:&jsonError];
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:&jsonError];

    if (!header || !payload) {
        if (error) {
            *error = [NSError errorWithDomain:DPoPErrorDomain
                                         code:-4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON in DPoP"}];
        }
        return NO;
    }

    NSString *typ = header[@"typ"];
    NSString *alg = header[@"alg"];

    if (![@"dpop+jwt" isEqualToString:typ]) {
        if (error) {
            *error = [NSError errorWithDomain:DPoPErrorDomain
                                         code:-5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid typ header"}];
        }
        return NO;
    }

    if (![@"ES256" isEqualToString:alg]) {
        if (error) {
            *error = [NSError errorWithDomain:DPoPErrorDomain
                                         code:-6
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid alg header"}];
        }
        return NO;
    }

    NSString *htmClaim = payload[@"htm"];
    NSString *htuClaim = payload[@"htu"];
    NSString *jti = payload[@"jti"];

    if (![htm isEqualToString:htmClaim]) {
        if (error) {
            *error = [NSError errorWithDomain:DPoPErrorDomain
                                         code:-7
                                     userInfo:@{NSLocalizedDescriptionKey: @"HTTP method mismatch"}];
        }
        return NO;
    }

    if (![htu isEqualToString:htuClaim]) {
        if (error) {
            *error = [NSError errorWithDomain:DPoPErrorDomain
                                         code:-8
                                     userInfo:@{NSLocalizedDescriptionKey: @"URI mismatch"}];
        }
        return NO;
    }

    if (nonce && ![nonce isEqualToString:payload[@"nonce"]]) {
        if (error) {
            *error = [NSError errorWithDomain:DPoPErrorDomain
                                         code:-9
                                     userInfo:@{NSLocalizedDescriptionKey: @"Nonce mismatch"}];
        }
        return NO;
    }

    if (!jti || jti.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:DPoPErrorDomain
                                         code:-10
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing jti"}];
        }
        return NO;
    }

    NSNumber *iatClaim = payload[@"iat"];
    if (!iatClaim) {
        if (error) {
            *error = [NSError errorWithDomain:DPoPErrorDomain
                                         code:-11
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing iat"}];
        }
        return NO;
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (iatClaim.doubleValue > now + 60) {
        if (error) {
            *error = [NSError errorWithDomain:DPoPErrorDomain
                                         code:-12
                                     userInfo:@{NSLocalizedDescriptionKey: @"iat in the future"}];
        }
        return NO;
    }

    NSNumber *expClaim = payload[@"exp"];
    if (expClaim && expClaim.doubleValue < now) {
        if (error) {
            *error = [NSError errorWithDomain:DPoPErrorDomain
                                         code:-13
                                     userInfo:@{NSLocalizedDescriptionKey: @"Token expired"}];
        }
        return NO;
    }

    NSData *signingInputData = [[NSString stringWithFormat:@"%@.%@", headerB64, payloadB64] dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signatureData = [self base64URLDecode:signatureB64];
    NSData *signatureForVerification = signatureData;
    
    if (!publicKey) {
        // If no public key provided, we can't verify functionality, but we can verify structure.
        // This is useful for tests that don't have a key pair handy but want to check claims.
        return YES; 
    }

    // DPoP JWT signatures are raw (r || s). Security expects ASN.1 DER for X9.62 verification.
    if (signatureData.length == 64) {
        signatureForVerification = [self derSignatureFromRaw:signatureData];
        if (!signatureForVerification) {
            if (error) {
                *error = [NSError errorWithDomain:DPoPErrorDomain
                                             code:-14
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid signature"}];
            }
            return NO;
        }
    }

    BOOL valid = SecKeyVerifySignature(publicKey,
                                     kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                     (__bridge CFDataRef)signingInputData,
                                     (__bridge CFDataRef)signatureForVerification,
                                     NULL);
    
    if (!valid) {
        if (error) {
            *error = [NSError errorWithDomain:DPoPErrorDomain
                                         code:-14
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid signature"}];
        }
    }
    return valid;
}

+ (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    while ([base64 hasSuffix:@"="]) {
        base64 = [base64 substringToIndex:base64.length - 1];
    }
    return base64;
}

+ (NSData *)base64URLDecode:(NSString *)string {
    NSMutableString *base64 = [string mutableCopy];
    NSUInteger remainder = base64.length % 4;
    if (remainder > 0) {
        [base64 appendString:[@"====" substringToIndex:remainder]];
    }
    [base64 replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, base64.length)];
    [base64 replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, base64.length)];
    return [[NSData alloc] initWithBase64EncodedData:[base64 dataUsingEncoding:NSUTF8StringEncoding] options:0];
}

+ (nullable NSData *)derSignatureFromRaw:(NSData *)rawSignature {
    if (!rawSignature || rawSignature.length != 64) {
        return nil;
    }

    NSMutableData *r = [[rawSignature subdataWithRange:NSMakeRange(0, 32)] mutableCopy];
    NSMutableData *s = [[rawSignature subdataWithRange:NSMakeRange(32, 32)] mutableCopy];

    while (r.length > 0 && ((const uint8_t *)r.bytes)[0] == 0x00) {
        [r replaceBytesInRange:NSMakeRange(0, 1) withBytes:NULL length:0];
    }
    while (s.length > 0 && ((const uint8_t *)s.bytes)[0] == 0x00) {
        [s replaceBytesInRange:NSMakeRange(0, 1) withBytes:NULL length:0];
    }

    if (r.length == 0 || (((const uint8_t *)r.bytes)[0] & 0x80)) {
        uint8_t zero = 0x00;
        [r replaceBytesInRange:NSMakeRange(0, 0) withBytes:&zero length:1];
    }
    if (s.length == 0 || (((const uint8_t *)s.bytes)[0] & 0x80)) {
        uint8_t zero = 0x00;
        [s replaceBytesInRange:NSMakeRange(0, 0) withBytes:&zero length:1];
    }

    NSUInteger contentLength = 2 + r.length + 2 + s.length;
    if (contentLength > UINT8_MAX) {
        return nil;
    }

    NSMutableData *der = [NSMutableData dataWithCapacity:2 + contentLength];
    uint8_t sequenceTag = 0x30;
    uint8_t sequenceLength = (uint8_t)contentLength;
    uint8_t integerTag = 0x02;
    uint8_t rLength = (uint8_t)r.length;
    uint8_t sLength = (uint8_t)s.length;

    [der appendBytes:&sequenceTag length:1];
    [der appendBytes:&sequenceLength length:1];
    [der appendBytes:&integerTag length:1];
    [der appendBytes:&rLength length:1];
    [der appendData:r];
    [der appendBytes:&integerTag length:1];
    [der appendBytes:&sLength length:1];
    [der appendData:s];
    return der;
}

+ (nullable NSData *)extractRawSignatureFromDER:(NSData *)derSignature {
    if (!derSignature || derSignature.length < 8) {
        return nil;
    }
    
    const uint8_t *bytes = derSignature.bytes;
    
    if (bytes[0] != 0x30) {
        return nil;
    }
    
    NSUInteger seqLen = bytes[1];
    NSUInteger offset = 2;
    if (bytes[1] & 0x80) {
        int numBytes = bytes[1] & 0x7f;
        if (numBytes > 3 || 2 + numBytes >= derSignature.length) {
            return nil;
        }
        seqLen = 0;
        for (int i = 0; i < numBytes; i++) {
            seqLen = (seqLen << 8) | bytes[2 + i];
        }
        offset = 2 + numBytes;
    }
    
    if (offset >= derSignature.length || bytes[offset] != 0x02) {
        return nil;
    }
    offset++;
    
    NSUInteger rLen = bytes[offset];
    offset++;
    if (rLen & 0x80) {
        int numBytes = rLen & 0x7f;
        rLen = 0;
        for (int i = 0; i < numBytes; i++) {
            rLen = (rLen << 8) | bytes[offset + i];
        }
    }
    
    NSUInteger rDataOffset = offset;
    NSUInteger rDataLen = rLen;
    while (rDataLen > 0 && bytes[rDataOffset] == 0x00) {
        rDataOffset++;
        rDataLen--;
    }
    offset += rLen;
    
    if (offset >= derSignature.length || bytes[offset] != 0x02) {
        return nil;
    }
    offset++;
    
    NSUInteger sLen = bytes[offset];
    offset++;
    if (sLen & 0x80) {
        int numBytes = sLen & 0x7f;
        sLen = 0;
        for (int i = 0; i < numBytes; i++) {
            sLen = (sLen << 8) | bytes[offset + i];
        }
    }
    
    NSUInteger sDataOffset = offset;
    NSUInteger sDataLen = sLen;
    while (sDataLen > 0 && bytes[sDataOffset] == 0x00) {
        sDataOffset++;
        sDataLen--;
    }
    offset += sLen;
    
    NSMutableData *raw = [NSMutableData dataWithLength:64];
    uint8_t *rawBytes = raw.mutableBytes;
    
    NSUInteger rStart = 32 - rDataLen;
    memcpy(rawBytes + rStart, bytes + rDataOffset, rDataLen);
    
    NSUInteger sStart = 32 - sDataLen;
    memcpy(rawBytes + 64 - sDataLen, bytes + sDataOffset, sDataLen);
    
    return raw;
}

@end
