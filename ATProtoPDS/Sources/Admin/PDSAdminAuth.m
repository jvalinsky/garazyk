#import "Admin/PDSAdminAuth.h"
#import <CommonCrypto/CommonHMAC.h>

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
        self.adminToken = [[NSUUID UUID] UUIDString];
        return YES;
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
