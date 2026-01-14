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
                                      error:(NSError **)error {
    DPoPToken *token = [[DPoPToken alloc] init];
    token.htm = htm;
    token.htu = htu;
    token.iat = [NSDate date];
    token.exp = [NSDate dateWithTimeIntervalSinceNow:300];
    token.jti = [[NSUUID UUID] UUIDString];
    token.nonce = nonce;

    NSError *signError = nil;
    NSString *jwt = [self signDPoPToken:token error:&signError];
    if (!jwt) {
        if (error) *error = signError;
        return nil;
    }

    token.jwt = jwt;
    return token;
}

+ (NSString *)signDPoPToken:(DPoPToken *)token error:(NSError **)error {
    NSDictionary *headerDict = [token header];
    NSMutableDictionary *header = [headerDict mutableCopy];
    // Ensure typ and alg are set if not present (though [token header] sets them)
    if (!header[@"typ"]) header[@"typ"] = @"dpop+jwt";
    if (!header[@"alg"]) header[@"alg"] = @"ES256";

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
    NSMutableData *signature = [NSMutableData dataWithLength:64];

    OSStatus status = SecRandomCopyBytes(kSecRandomDefault, 32, signature.mutableBytes);
    if (status != errSecSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:DPoPErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate signature"}];
        }
        return nil;
    }

    NSString *signatureB64 = [self base64URLEncode:signature];

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

    return YES;
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

@end
