#import "OAuth2Handler.h"
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>

@interface OAuth2Handler ()
@property (nonatomic, strong) NSMutableDictionary *authorizationCodes;
@end

@implementation OAuth2Handler

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    
    self.authorizationCodes = [NSMutableDictionary dictionary];
    
    return self;
}

- (void)handleAuthorize:(NSDictionary *)params completion:(void (^)(NSString *redirectURL, NSError *error))completion {
    NSString *clientId = params[@"client_id"];
    NSString *redirectUri = params[@"redirect_uri"];
    NSString *scope = params[@"scope"];
    NSString *state = params[@"state"];
    
    if (!clientId || !redirectUri || !scope) {
        NSError *error = [NSError errorWithDomain:@"OAuth2" code:400 
            userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameters"}];
        completion(nil, error);
        return;
    }
    
    // Generate authorization code
    NSString *code = [[NSUUID UUID] UUIDString];
    self.authorizationCodes[code] = @{
        @"client_id": clientId,
        @"redirect_uri": redirectUri,
        @"scope": scope,
        @"did": @"did:plc:tutorial123",
        @"handle": @"tutorialuser",
        @"created_at": @([[NSDate date] timeIntervalSince1970])
    };
    
    NSString *redirectURL = [NSString stringWithFormat:@"%@?code=%@&state=%@", 
                            redirectUri, code, state ?: @""];
    
    completion(redirectURL, nil);
}

- (void)handleToken:(NSDictionary *)params completion:(void (^)(NSDictionary *result, NSError *error))completion {
    NSString *grantType = params[@"grant_type"];
    NSString *code = params[@"code"];
    NSString *clientId = params[@"client_id"];
    
    if (![grantType isEqualToString:@"authorization_code"]) {
        NSError *error = [NSError errorWithDomain:@"OAuth2" code:400 
            userInfo:@{NSLocalizedDescriptionKey: @"Unsupported grant type"}];
        completion(nil, error);
        return;
    }
    
    NSDictionary *authCode = self.authorizationCodes[code];
    if (!authCode) {
        NSError *error = [NSError errorWithDomain:@"OAuth2" code:400 
            userInfo:@{NSLocalizedDescriptionKey: @"Invalid authorization code"}];
        completion(nil, error);
        return;
    }
    
    if (![authCode[@"client_id"] isEqualToString:clientId]) {
        NSError *error = [NSError errorWithDomain:@"OAuth2" code:400 
            userInfo:@{NSLocalizedDescriptionKey: @"Client ID mismatch"}];
        completion(nil, error);
        return;
    }
    
    // Generate tokens (simplified)
    NSString *accessToken = [self generateToken:@"access" did:authCode[@"did"]];
    NSString *refreshToken = [self generateToken:@"refresh" did:authCode[@"did"]];
    
    [self.authorizationCodes removeObjectForKey:code];
    
    NSDictionary *result = @{
        @"access_token": accessToken,
        @"refresh_token": refreshToken,
        @"token_type": @"Bearer",
        @"expires_in": @3600,
        @"scope": authCode[@"scope"]
    };
    
    completion(result, nil);
}

- (void)handleRefresh:(NSDictionary *)params completion:(void (^)(NSDictionary *result, NSError *error))completion {
    NSString *grantType = params[@"grant_type"];
    NSString *refreshToken = params[@"refresh_token"];
    
    if (![grantType isEqualToString:@"refresh_token"]) {
        NSError *error = [NSError errorWithDomain:@"OAuth2" code:400 
            userInfo:@{NSLocalizedDescriptionKey: @"Unsupported grant type"}];
        completion(nil, error);
        return;
    }
    
    // Simplified: just generate new access token
    NSString *accessToken = [self generateToken:@"access" did:@"did:plc:tutorial123"];
    
    NSDictionary *result = @{
        @"access_token": accessToken,
        @"token_type": @"Bearer",
        @"expires_in": @3600
    };
    
    completion(result, nil);
}

- (NSString *)generateToken:(NSString *)type did:(NSString *)did {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval exp = [type isEqualToString:@"access"] ? now + 3600 : now + (86400 * 30);
    
    NSDictionary *payload = @{
        @"iss": @"did:web:localhost:2583",
        @"sub": did,
        @"iat": @(now),
        @"exp": @(exp),
        @"scope": [type isEqualToString:@"access"] ? @"atproto_repo" : @"atproto_refresh"
    };
    
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadB64 = [self base64URLEncode:payloadData];
    
    NSDictionary *header = @{@"alg": @"HS256", @"typ": @"JWT"};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerB64 = [self base64URLEncode:headerData];
    
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    
    NSString *secret = @"tutorial-secret-key";
    NSData *secretData = [secret dataUsingEncoding:NSUTF8StringEncoding];
    
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, secretData.bytes, secretData.length, 
           signingData.bytes, signingData.length, digest);
    NSData *signature = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    NSString *signatureB64 = [self base64URLEncode:signature];
    
    return [NSString stringWithFormat:@"%@.%@.%@", headerB64, payloadB64, signatureB64];
}

- (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

@end
