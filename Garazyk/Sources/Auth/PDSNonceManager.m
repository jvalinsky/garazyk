#import "Auth/PDSNonceManager.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"
#import <Security/Security.h>

static const NSTimeInterval kDPoPNonceTTLSeconds = 300.0; // 5 minutes per AT Protocol spec

@interface PDSNonceManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *issuedNonces;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t lockQueue;
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

    NSDate *expiration = [NSDate dateWithTimeIntervalSinceNow:kDPoPNonceTTLSeconds];
    
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
        if (expiration && [expiration timeIntervalSinceNow] > 0) {
            isValid = YES;
        }
        // Nonces are reusable until they expire — do not remove on use.
        // AT Protocol spec: "Servers may use the same nonce across all client
        // sessions and across multiple requests at any point in time."
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
