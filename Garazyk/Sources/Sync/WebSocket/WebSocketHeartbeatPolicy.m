#import "Sync/WebSocketHeartbeatPolicy.h"

@interface WebSocketHeartbeatPolicy ()
@property (nonatomic, assign) NSTimeInterval lastPingSentTime;
@property (nonatomic, assign) NSTimeInterval lastPongReceivedTime;
@property (nonatomic, assign) BOOL waitingForPong;
@end

@implementation WebSocketHeartbeatPolicy

- (instancetype)init {
    self = [super init];
    if (self) {
        _heartbeatInterval = 30.0;
        _heartbeatTimeout = 10.0;
        _lastPingSentTime = 0.0;
        _lastPongReceivedTime = 0.0;
        _waitingForPong = NO;
    }
    return self;
}

- (WSHeartbeatAction)tick:(NSTimeInterval)now {
    if (self.waitingForPong) {
        // Check if timeout has elapsed
        if (now - self.lastPingSentTime >= self.heartbeatTimeout) {
            return WSHeartbeatActionTimeout;
        }
        return WSHeartbeatActionNone;
    }
    
    // Not waiting for pong. Check if interval has elapsed since last ping
    if (self.lastPingSentTime == 0.0 || (now - self.lastPingSentTime >= self.heartbeatInterval)) {
        return WSHeartbeatActionSendPing;
    }
    
    return WSHeartbeatActionNone;
}

- (void)pongReceived:(NSTimeInterval)now {
    self.lastPongReceivedTime = now;
    self.waitingForPong = NO;
}

- (void)pingSent:(NSTimeInterval)now {
    self.lastPingSentTime = now;
    self.waitingForPong = YES;
}

@end