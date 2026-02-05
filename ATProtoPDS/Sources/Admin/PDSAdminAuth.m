#import "Admin/PDSAdminAuth.h"
#import "Auth/JWT.h"
#import "App/PDSController.h"

static NSString *const PDSAdminAuthErrorDomain = @"PDSAdminAuth";

static BOOL PDSConstantTimeEqualStrings(NSString *a, NSString *b) {
    if (a == nil || b == nil) {
        return NO;
    }

    NSData *aData = [a dataUsingEncoding:NSUTF8StringEncoding];
    NSData *bData = [b dataUsingEncoding:NSUTF8StringEncoding];
    if (aData == nil || bData == nil) {
        return NO;
    }

    if (aData.length != bData.length) {
        return NO;
    }

    const uint8_t *aBytes = aData.bytes;
    const uint8_t *bBytes = bData.bytes;
    uint8_t diff = 0;
    for (NSUInteger i = 0; i < aData.length; i++) {
        diff |= (uint8_t)(aBytes[i] ^ bBytes[i]);
    }
    return diff == 0;
}

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
    NSString *expectedPassword = [[NSProcessInfo processInfo] environment][@"PDS_ADMIN_PASSWORD"];
    if (expectedPassword.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain
                                         code:503
                                     userInfo:@{NSLocalizedDescriptionKey: @"Admin password not configured (set PDS_ADMIN_PASSWORD)"}];
        }
        return NO;
    }

    if (!PDSConstantTimeEqualStrings(password, expectedPassword)) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain
                                         code:401
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid admin password"}];
        }
        return NO;
    }

    PDSController *controller = [PDSController sharedController];
    if (!controller || !controller.jwtMinter) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain
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

    NSError *signError = nil;
    NSString *token = [controller.jwtMinter signPayload:claims error:&signError];
    if (token) {
        self.adminToken = token;
        return YES;
    }

    if (error) {
        *error = signError ?: [NSError errorWithDomain:PDSAdminAuthErrorDomain
                                                  code:500
                                              userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate admin token"}];
    }
    return NO;
}

- (void)logout {
    self.adminToken = nil;
}

@end
