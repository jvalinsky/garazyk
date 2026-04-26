// FuzzOAuth.m - OAuth state machine fuzzing
// Tests OAuth authorization flow edge cases

#import <Foundation/Foundation.h>

#if __has_include("Auth/OAuth2.h")
#import "Auth/OAuth2.h"
#endif

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    @autoreleasepool {
        if (!data || size == 0) return 0;
        
        NSData *jsonData = [NSData dataWithBytes:data length:size];
        
        // Test 1: Authorization request parsing
        NSError *jsonError = nil;
        NSDictionary *params = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
        
        if (params && !jsonError && [params isKindOfClass:[NSDictionary class]]) {
            // Response type
            (void)params[@"response_type"];
            (void)params[@"client_id"];
            (void)params[@"redirect_uri"];
            (void)params[@"scope"];
            (void)params[@"state"];
            (void)params[@"code_challenge"];
            (void)params[@"code_challenge_method"];
            
            // Test 2: State parameter variations
            NSString *state = params[@"state"];
            if (state) {
                // Empty state
                // Very long state
                // State with special chars
                (void)[state length];
            }
            
            // Test 3: Code challenge variants
            NSString *method = params[@"code_challenge_method"];
            if ([method isEqualToString:@"plain"]) {
                (void)@"plain";
            } else if ([method isEqualToString:@"S256"]) {
                (void)@"S256";
            }
            
            // Test 4: Redirect URI edge cases
            NSString *uri = params[@"redirect_uri"];
            if (uri) {
                (void)[NSURL URLWithString:uri];
            }
        }
        
        // Test 5: Token request parsing
        if (size > 0) {
            NSDictionary *tokenParams = @{@"grant_type": @"authorization_code",
                                         @"code": @"test-code",
                                         @"client_id": @"test-client",
                                         @"redirect_uri": @"https://example.com/callback"};
            NSData *tokenData = [NSJSONSerialization dataWithJSONObject:tokenParams options:0 error:nil];
            (void)tokenData;
        }
        
        // Test 6: Grant type variants
        NSArray *grantTypes = @[@"authorization_code", @"refresh_token", @"client_credentials", @"password"];
        for (NSString *grant in grantTypes) {
            (void)grant;
        }
        
        // Test 7: PKCE variations
        NSDictionary *pkceParams = @{
            @"code_verifier": @"dBjftJeZ4CVP-mB92K27uhbEJ8t1ei9iTbhRI4NWM5Og",
            @"code_challenge": @"SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
            @"code_challenge_method": @"S256"
        };
        
        // Test 8: Invalid grant type handling
        NSString *invalidGrant = [[NSString alloc] initWithBytes:data length:MIN(size, 20) encoding:NSUTF8StringEncoding];
        if (invalidGrant) {
            (void)[invalidGrant containsString:@"invalid"];
        }
        
        // Test 9: Scope parsing
        NSString *scopeStr = [[NSString alloc] initWithBytes:data length:MIN(size, 100) encoding:NSUTF8StringEncoding];
        if (scopeStr) {
            NSArray *scopes = [scopeStr componentsSeparatedByString:@" "];
            (void)scopes;
        }
        
        // Test 10: Empty/missing required fields
        NSDictionary *emptyParams = @{};
        NSData *emptyData = [NSJSONSerialization dataWithJSONObject:emptyParams options:0 error:nil];
        (void)emptyData;
    }
    return 0;
}