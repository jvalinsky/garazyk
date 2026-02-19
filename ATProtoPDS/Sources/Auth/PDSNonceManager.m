#import "Auth/PDSNonceManager.h"
#import "Debug/PDSLogger.h"
#import <Security/Security.h>

@interface PDSNonceManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *issuedNonces;
#if defined(GNUSTEP) || defined(LINUX)
@property (nonatomic, assign) dispatch_queue_t lockQueue;
#else
@property (nonatomic, strong) dispatch_queue_t lockQueue;
#endif
@end

@implementation PDSNonceManager

+ (instancetype)sharedManager {
    static PDSNonceManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _issuedNonces = [NSMutableDictionary dictionary];
        _lockQueue = dispatch_queue_create("com.atproto.pds.noncemanager", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSString *)generateNonce {
    uint8_t randomBytes[24];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(randomBytes), randomBytes) != errSecSuccess) {
        PDS_LOG_AUTH_ERROR(@"Failed to generate random bytes for nonce");
        return nil;
    }
    NSData *data = [NSData dataWithBytes:randomBytes length:sizeof(randomBytes)];
    NSString *nonce = [data base64EncodedStringWithOptions:0];
    
    // Normalize for URL safety
    nonce = [nonce stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    nonce = [nonce stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    nonce = [nonce stringByReplacingOccurrencesOfString:@"=" withString:@""];

    NSDate *expiration = [NSDate dateWithTimeIntervalSinceNow:600]; // 10 minutes
    
    dispatch_async(self.lockQueue, ^{
        self.issuedNonces[nonce] = expiration;
        [self cleanupNonces];
    });
    
    return nonce;
}

- (BOOL)validateNonce:(NSString *)nonce {
    if (!nonce) return NO;
    
    __block BOOL isValid = NO;
    dispatch_sync(self.lockQueue, ^{
        NSDate *expiration = self.issuedNonces[nonce];
        if (expiration) {
            if ([expiration timeIntervalSinceNow] > 0) {
                isValid = YES;
            }
            // Nonces are one-time use
            [self.issuedNonces removeObjectForKey:nonce];
        }
    });
    
    return isValid;
}

- (void)cleanupNonces {
    NSDate *now = [NSDate date];
    NSMutableArray *toRemove = [NSMutableArray array];
    
    for (NSString *nonce in self.issuedNonces) {
        if ([self.issuedNonces[nonce] timeIntervalSinceDate:now] < 0) {
            [toRemove addObject:nonce];
        }
    }
    
    [self.issuedNonces removeObjectsForKeys:toRemove];
}

@end
