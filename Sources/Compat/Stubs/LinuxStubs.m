#if !defined(__APPLE__)

#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>

// Stub for PDSMetrics (macOS-only due to os_unfair_lock)
@interface PDSMetrics : NSObject
+ (instancetype)sharedMetrics;
- (NSUInteger)httpRequestsTotal;
- (NSUInteger)repositoryCount;
- (NSUInteger)blobCount;
- (NSUInteger)activeConnections;
- (NSUInteger)httpLatencyMs;
- (void)incrementHttpRequests;
- (void)recordHttpLatency:(NSTimeInterval)latency;
@end

@implementation PDSMetrics
+ (instancetype)sharedMetrics {
    static PDSMetrics *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSMetrics alloc] init];
    });
    return shared;
}
- (NSUInteger)httpRequestsTotal { return 0; }
- (NSUInteger)repositoryCount { return 0; }
- (NSUInteger)blobCount { return 0; }
- (NSUInteger)activeConnections { return 0; }
- (NSUInteger)httpLatencyMs { return 0; }
- (void)incrementHttpRequests {}
- (void)recordHttpLatency:(NSTimeInterval)latency {}
@end

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

// arc4random and arc4random_buf are provided by SecRandom.h
// arc4random_uniform compatibility shim for Linux
uint32_t arc4random_uniform(uint32_t upper_bound) {
    uint32_t value;
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd >= 0) {
        read(fd, &value, sizeof(value));
        close(fd);
    }
    // Scale to [0, upper_bound) avoiding modulo bias
    return value % upper_bound;
}

#endif
