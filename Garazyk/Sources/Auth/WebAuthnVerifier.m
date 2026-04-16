#import "Auth/WebAuthnVerifier.h"
#import "Auth/CryptoUtils.h"
#import "Auth/Base32Utils.h"
#import "Auth/PDSKeyProtocol.h"
#import "Auth/Crypto/AuthCryptoJWK.h"
#import "Auth/Crypto/AuthCryptoBase64URL.h"
#import "Repository/CBOR.h"

#if defined(__APPLE__) && !defined(GNUSTEP)
#import <Security/Security.h>
#endif

@implementation WebAuthnVerifier

+ (nullable NSDictionary *)verifyRegistrationResponse:(NSDictionary *)response
                                            challenge:(NSData *)expectedChallenge
                                               origin:(NSString *)expectedOrigin
                                                error:(NSError **)error {
    // 1. Parse clientDataJSON
    NSString *clientDataJSONB64 = response[@"response"][@"clientDataJSON"];
    NSData *clientDataJSON = [[NSData alloc] initWithBase64EncodedString:clientDataJSONB64 options:0];
    if (!clientDataJSON) {
        if (error) *error = [self errorWithCode:1001 message:@"Invalid clientDataJSON"];
        return nil;
    }
    
    NSDictionary *clientData = [NSJSONSerialization JSONObjectWithData:clientDataJSON options:0 error:nil];
    if (![clientData[@"type"] isEqualToString:@"webauthn.create"]) {
        if (error) *error = [self errorWithCode:1002 message:@"Invalid operation type"];
        return nil;
    }
    
    // Check Challenge
    NSString *challengeB64 = clientData[@"challenge"];
    // WebAuthn uses Base64URL, need to handle padding
    NSString *challengeBase64 = [challengeB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    challengeBase64 = [challengeBase64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"]; 
    while (challengeBase64.length % 4 != 0) {
        challengeBase64 = [challengeBase64 stringByAppendingString:@"="];
    }
    
    NSData *challengeData = [[NSData alloc] initWithBase64EncodedString:challengeBase64 options:0];
    
    // Simple byte comparison for challenge
    if (![challengeData isEqualToData:expectedChallenge]) {
        // Fallback: compare base32 strings if binary fails (sometimes encoding varies)
        NSString *chl1 = [Base32Utils base32StringFromData:challengeData];
        NSString *chl2 = [Base32Utils base32StringFromData:expectedChallenge];
        if (![chl1 isEqualToString:chl2]) {
             if (error) *error = [self errorWithCode:1003 message:@"Challenge mismatch"];
             return nil;
        }
    }
    
    if (![clientData[@"origin"] isEqualToString:expectedOrigin]) {
        if (error) *error = [self errorWithCode:1004 message:[NSString stringWithFormat:@"Origin mismatch: %@ vs %@", clientData[@"origin"], expectedOrigin]];
        return nil;
    }
    
    // 2. Parse attestationObject (CBOR)
    NSString *attestationObjectB64 = response[@"response"][@"attestationObject"];
    NSData *attestationObject = [[NSData alloc] initWithBase64EncodedString:attestationObjectB64 options:0];
    CBORValue *attestationParams = [CBORValue decode:attestationObject];
    
    if (attestationParams.type != CBORTypeMap) {
        if (error) *error = [self errorWithCode:1005 message:@"Invalid attestation object"];
        return nil;
    }
    
    NSDictionary *map = attestationParams.map;
    // Find "authData" key
    NSData *authData = nil;
    for (CBORValue *key in map) {
         if (key.type == CBORTypeTextString && [key.textString isEqualToString:@"authData"]) {
             CBORValue *val = map[key];
             if (val.type == CBORTypeByteString) {
                 authData = val.byteString;
             }
             break;
         }
    }
    
    if (!authData) {
        if (error) *error = [self errorWithCode:1006 message:@"Missing authData"];
        return nil;
    }
    
    // Parse authData (binary structure)
    // 32 bytes rpIdHash
    // 1 byte flags
    // 4 bytes signCount
    // ... attestedCredentialData ...
    
    if (authData.length < 37) {
        if (error) *error = [self errorWithCode:1007 message:@"authData too short"];
        return nil;
    }
    
    uint8_t flags = ((const uint8_t *)authData.bytes)[32];
    BOOL hasAttestedCredentialData = (flags & 0x40) != 0;
    
    if (!hasAttestedCredentialData) {
        if (error) *error = [self errorWithCode:1008 message:@"No attested credential data"];
        return nil;
    }

    if (authData.length < 37 + 16 + 2) {
        if (error) *error = [self errorWithCode:1009 message:@"Attested credential data too short"];
        return nil;
    }

    // Parse Attested Credential Data
    // 16 bytes AAGUID
    // 2 bytes credentialIdLength
    // L bytes credentialId
    // ... credentialPublicKey (COSE)
    
    const uint8_t *ptr = (const uint8_t *)authData.bytes + 37;
    NSData *aaguid = [NSData dataWithBytes:ptr length:16];
    ptr += 16;
    
    uint16_t credIdLenNet;
    memcpy(&credIdLenNet, ptr, 2);
    uint16_t credIdLen = CFSwapInt16BigToHost(credIdLenNet);
    ptr += 2;

    NSUInteger remaining = authData.length - (ptr - (const uint8_t *)authData.bytes);
    if (credIdLen > remaining) {
        if (error) *error = [self errorWithCode:1010 message:@"Credential ID length exceeds available data"];
        return nil;
    }

    NSData *credentialId = [NSData dataWithBytes:ptr length:credIdLen];
    ptr += credIdLen;

    // Remaining is Public Key (COSE format, CBOR)
    remaining = authData.length - (ptr - (const uint8_t *)authData.bytes);
    if (remaining == 0) {
        if (error) *error = [self errorWithCode:1011 message:@"Missing credential public key data"];
        return nil;
    }
    NSData *publicKeyCOSE = [NSData dataWithBytes:ptr length:remaining];
    
    return @{
        @"credentialId": credentialId,
        @"publicKey": publicKeyCOSE,
        @"aaguid": aaguid,
        @"signCount": @(0) // Start at 0
    };
}

+ (BOOL)verifyAssertionResponse:(NSDictionary *)response
                      challenge:(NSData *)expectedChallenge
                         origin:(NSString *)expectedOrigin
                      publicKey:(NSData *)publicKey
                      signCount:(uint32_t)storedSignCount
                   newSignCount:(uint32_t *)outSignCount
                          error:(NSError **)error {
    
    NSString *clientDataJSONB64 = response[@"response"][@"clientDataJSON"];
    NSString *authenticatorDataB64 = response[@"response"][@"authenticatorData"];
    NSString *signatureB64 = response[@"response"][@"signature"];
    
    NSData *clientDataJSON = [[NSData alloc] initWithBase64EncodedString:clientDataJSONB64 options:0];
    NSData *authenticatorData = [[NSData alloc] initWithBase64EncodedString:authenticatorDataB64 options:0];
    NSData *signature = [[NSData alloc] initWithBase64EncodedString:signatureB64 options:0];
    
    // 1. Validate Client Data
    NSDictionary *clientData = [NSJSONSerialization JSONObjectWithData:clientDataJSON options:0 error:nil];
    if (![clientData[@"type"] isEqualToString:@"webauthn.get"]) {
         if (error) *error = [self errorWithCode:2001 message:@"Invalid operation type"];
         return NO;
    }
    
    // Challenge check (same fallback logic as logic above)
    NSString *challengeB64 = clientData[@"challenge"];
    NSString *challengeBase64 = [challengeB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    challengeBase64 = [challengeBase64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (challengeBase64.length % 4 != 0) {
        challengeBase64 = [challengeBase64 stringByAppendingString:@"="];
    }
    NSData *challengeData = [[NSData alloc] initWithBase64EncodedString:challengeBase64 options:0];
    if (![challengeData isEqualToData:expectedChallenge]) {
        NSString *chl1 = [Base32Utils base32StringFromData:challengeData];
        NSString *chl2 = [Base32Utils base32StringFromData:expectedChallenge];
        if (![chl1 isEqualToString:chl2]) {
             if (error) *error = [self errorWithCode:2002 message:@"Challenge mismatch"];
             return NO;
        }
    }
    
    if (![clientData[@"origin"] isEqualToString:expectedOrigin]) {
        if (error) *error = [self errorWithCode:2003 message:@"Origin mismatch"];
        return NO;
    }
    
    // 2. Parsed Authenticator Data
    if (authenticatorData.length < 37) {
        if (error) *error = [self errorWithCode:2004 message:@"authData too short"];
        return NO;
    }
    
    uint8_t flags = ((const uint8_t *)authenticatorData.bytes)[32];
    BOOL userPresent = (flags & 0x01) != 0;
    // BOOL userVerified = (flags & 0x04) != 0; 
    
    if (!userPresent) {
        if (error) *error = [self errorWithCode:2005 message:@"User not present"];
        return NO;
    }
    
    uint32_t signCountNet;
    memcpy(&signCountNet, (const uint8_t *)authenticatorData.bytes + 33, 4);
    uint32_t currentSignCount = CFSwapInt32BigToHost(signCountNet);
    
    if (currentSignCount <= storedSignCount && currentSignCount != 0) {
        if (error) *error = [self errorWithCode:2006 message:@"Sign count error (cloned authenticator?)"];
        return NO;
    }
    if (outSignCount) *outSignCount = currentSignCount;
    
    // 3. Verify Signature
    // signedData = authenticatorData || SHA256(clientDataJSON)
    NSMutableData *signedData = [authenticatorData mutableCopy];
    NSData *clientDataHash = [CryptoUtils sha256:clientDataJSON];
    [signedData appendData:clientDataHash];
    
    // Import Public Key - convert to JWK format
    // WebAuthn public key is typically in uncompressed point format (0x04 || x || y)
    NSData *pubKeyData = publicKey;
    if (pubKeyData.length == 65 && ((const uint8_t *)pubKeyData.bytes)[0] == 0x04) {
        // Uncompressed format - extract x and y
        NSData *xData = [pubKeyData subdataWithRange:NSMakeRange(1, 32)];
        NSData *yData = [pubKeyData subdataWithRange:NSMakeRange(33, 32)];
        
        NSDictionary *jwk = @{
            @"kty": @"EC",
            @"crv": @"P-256",
            @"x": [AuthCryptoBase64URL encode:xData],
            @"y": [AuthCryptoBase64URL encode:yData]
        };
        
        NSError *keyError = nil;
        id<PDSPublicKeyProtocol> pubKey = [AuthCryptoJWK publicKeyFromJWK:jwk error:&keyError];
        if (!pubKey) {
            if (error) *error = [self errorWithCode:2007 message:@"Invalid public key format"];
            return NO;
        }
        
        // WebAuthn signature is DER format, need to convert to raw r||s for our protocol
        // Parse DER signature
        NSData *rawSig = nil;
        if (signature.length > 8) {
            const uint8_t *der = signature.bytes;
            if (der[0] == 0x30) {
                int totalLen = der[1];
                if (der[2] == 0x02) {
                    int rLen = der[3];
                    const uint8_t *rStart = &der[4];
                    // Skip leading zeros and check for padding byte
                    while (rLen > 32 && rStart[0] == 0) { rLen--; rStart++; }
                    
                    if (der[4 + rLen] == 0x02) {
                        int sLen = der[5 + rLen];
                        const uint8_t *sStart = &der[6 + rLen];
                        while (sLen > 32 && sStart[0] == 0) { sLen--; sStart++; }
                        
                        NSMutableData *raw = [NSMutableData dataWithLength:64];
                        memset(raw.mutableBytes, 0, 64);
                        
                        // Copy r (right-aligned in first 32 bytes)
                        int rOffset = 32 - rLen;
                        if (rOffset < 0) rOffset = 0;
                        memcpy((uint8_t *)raw.mutableBytes + rOffset, rStart, MIN(rLen, 32));
                        
                        // Copy s (right-aligned in second 32 bytes)
                        int sOffset = 32 - sLen;
                        if (sOffset < 0) sOffset = 0;
                        memcpy((uint8_t *)raw.mutableBytes + 32 + sOffset, sStart, MIN(sLen, 32));
                        
                        rawSig = raw;
                    }
                }
            }
        }
        
        if (!rawSig) {
            if (error) *error = [self errorWithCode:2007 message:@"Invalid signature format"];
            return NO;
        }
        
        // Hash the signed data and verify
        NSData *hash = [CryptoUtils sha256:signedData];
        NSError *verifyError = nil;
        BOOL verified = [pubKey verifyDigestSignature:rawSig forHash:hash error:&verifyError];
        
        if (!verified) {
            if (error) *error = [self errorWithCode:2008 message:@"Signature verification failed"];
            return NO;
        }
    } else {
        // Unsupported key format
        if (error) *error = [self errorWithCode:2007 message:@"Unsupported public key format (expected uncompressed P-256)"];
        return NO;
    }
    
    return YES;
}

+ (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message {
    return [NSError errorWithDomain:@"com.atproto.webauthn" code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

@end
