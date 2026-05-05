#import "AdminUIServer/UIAuthManager.h"
#import "Network/HttpRequest.h"
#import "Compat/PDSTypes.h"

@interface UIAuthManager ()

@property(nonatomic, copy) NSString *password;
@property(nonatomic, strong) NSMutableSet<NSString *> *activeTokens;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t stateQueue;

@end

@implementation UIAuthManager

- (instancetype)initWithPassword:(NSString *)password {
    self = [super init];
    if (self) {
        _password = [password copy] ?: @"";
        _activeTokens = [NSMutableSet set];
        _stateQueue = dispatch_queue_create("com.garazyk.ui.auth", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)validatePassword:(NSString *)password {
    if (!password || password.length == 0) {
        return NO;
    }
    return [self.password isEqualToString:password];
}

- (NSString *)createSessionToken {
    NSString *token = [[NSUUID UUID] UUIDString];
    dispatch_sync(self.stateQueue, ^{
        [self.activeTokens addObject:token];
    });
    return token;
}

- (void)invalidateSessionToken:(NSString *)token {
    if (token.length == 0) {
        return;
    }
    dispatch_sync(self.stateQueue, ^{
        [self.activeTokens removeObject:token];
    });
}

- (BOOL)isAuthorizedRequest:(HttpRequest *)request {
    NSString *token = [self extractTokenFromRequest:request];
    if (token.length == 0) {
        return NO;
    }
    __block BOOL authorized = NO;
    dispatch_sync(self.stateQueue, ^{
        authorized = [self.activeTokens containsObject:token];
    });
    return authorized;
}

- (NSString *)extractTokenFromRequest:(HttpRequest *)request {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if ([authHeader.lowercaseString hasPrefix:@"bearer "]) {
        NSString *token = [authHeader substringFromIndex:7];
        token = [token stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (token.length > 0) {
            return token;
        }
    }

    NSString *cookieHeader = [request headerForKey:@"Cookie"];
    if (![cookieHeader isKindOfClass:[NSString class]] || cookieHeader.length == 0) {
        return nil;
    }

    for (NSString *cookie in [cookieHeader componentsSeparatedByString:@";"]) {
        NSString *trimmed = [cookie stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (![trimmed hasPrefix:@"ui_admin_token="]) {
            continue;
        }
        NSString *token = [trimmed substringFromIndex:@"ui_admin_token=".length];
        return token.length > 0 ? token : nil;
    }
    return nil;
}

@end

