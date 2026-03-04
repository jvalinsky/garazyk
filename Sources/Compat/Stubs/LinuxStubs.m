#if !defined(__APPLE__)

#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>


// Stub for KeyManager (macOS-only due to Security framework)
@interface KeyManager : NSObject
+ (instancetype)sharedManager;
- (NSData *)signData:(NSData *)data error:(NSError **)error;
- (NSData *)getPublicKeyData;
@end

@implementation KeyManager
+ (instancetype)sharedManager {
    static KeyManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[KeyManager alloc] init];
    });
    return shared;
}
- (NSData *)signData:(NSData *)data error:(NSError **)error {
    if (error) *error = [NSError errorWithDomain:@"KeyManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"KeyManager not available on Linux"}];
    return nil;
}
- (NSData *)getPublicKeyData { return nil; }
@end

// Stub for WebSocketServer (macOS-only due to Network.framework)
@interface WebSocketServer : NSObject
- (instancetype)initWithPort:(uint16_t)port;
- (BOOL)start:(NSError **)error;
- (void)stop;
@end

@implementation WebSocketServer
- (instancetype)initWithPort:(uint16_t)port {
    self = [super init];
    return self;
}
- (BOOL)start:(NSError **)error {
    if (error) *error = [NSError errorWithDomain:@"WebSocketServer" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"WebSocketServer not available on Linux"}];
    return NO;
}
- (void)stop {}
@end


#endif
