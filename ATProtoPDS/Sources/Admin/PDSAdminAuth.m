#import "Admin/PDSAdminAuth.h"
#import <CommonCrypto/CommonHMAC.h>
#import "Auth/JWT.h"
#import "App/PDSController.h"

@implementation PDSAdminAuth

+ (instancetype)sharedAuth {
    static PDSAdminAuth *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSAdminAuth alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _adminToken = nil;
    }
    return self;
}

- (BOOL)isAuthenticatedWithRequest:(NSObject *)request {
    return self.adminToken != nil;
}

- (BOOL)authenticateWithPassword:(NSString *)password error:(NSError **)error {
    if ([password isEqualToString:@"admin123"]) {
        PDSController *controller = [PDSController sharedController];
        if (!controller || !controller.jwtMinter) {
            if (error) {
                *error = [NSError errorWithDomain:@"PDSAdminAuth"
                                             code:500
                                         userInfo:@{NSLocalizedDescriptionKey: @"Server not initialized"}];
            }
            return NO;
        }

        NSString *expectedIssuer = [[NSProcessInfo processInfo] environment][@"PDS_ISSUER"] ?: @"https://pds.local:8443";
        NSURLComponents *issuerComponents = [NSURLComponents componentsWithString:expectedIssuer];
        NSString *issuerHost = issuerComponents.host ?: expectedIssuer;
        NSString *adminDID = [NSString stringWithFormat:@"did:web:%@", issuerHost];

        NSMutableDictionary *claims = [NSMutableDictionary dictionary];
        claims[@"sub"] = adminDID;
        claims[@"scope"] = @"admin";
        claims[@"iss"] = expectedIssuer;
        claims[@"aud"] = expectedIssuer;
        claims[@"exp"] = @([[NSDate dateWithTimeIntervalSinceNow:3600] timeIntervalSince1970]);
        claims[@"iat"] = @([[NSDate date] timeIntervalSince1970]);

        NSString *token = [controller.jwtMinter signPayload:claims error:nil];
        if (token) {
            self.adminToken = token;
            return YES;
        }

        if (error) {
            *error = [NSError errorWithDomain:@"PDSAdminAuth"
                                         code:500
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate admin token"}];
        }
    }

    if (error) {
        *error = [NSError errorWithDomain:@"PDSAdminAuth"
                                     code:401
                                 userInfo:@{NSLocalizedDescriptionKey: @"Invalid admin password"}];
    }
    return NO;
}

- (void)logout {
    self.adminToken = nil;
}

@end
