#import <Foundation/Foundation.h>

@class RelayClient;
@class FirehoseCommitEvent;
@class FirehoseIdentityEvent;
@class FirehoseErrorEvent;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const RelayClientErrorDomain;
extern NSInteger const RelayClientErrorCodeConnectionFailed;
extern NSInteger const RelayClientErrorCodeAuthenticationFailed;

@protocol RelayClientDelegate <NSObject>
@optional
- (void)relayClient:(RelayClient *)client didReceiveCommitEvent:(FirehoseCommitEvent *)event;
- (void)relayClient:(RelayClient *)client didReceiveIdentityEvent:(FirehoseIdentityEvent *)event;
- (void)relayClient:(RelayClient *)client didReceiveErrorEvent:(FirehoseErrorEvent *)event;
- (void)relayClientDidConnect:(RelayClient *)client;
- (void)relayClient:(RelayClient *)client didDisconnectWithError:(nullable NSError *)error;
- (void)relayClient:(RelayClient *)client didReceiveCursor:(NSString *)cursor;
@end

@interface RelayClient : NSObject

@property (nonatomic, weak, nullable, readonly) id<RelayClientDelegate> delegate;
@property (nonatomic, readonly) NSURL *serverURL;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, copy, nullable, readonly) NSString *currentCursor;
@property (nonatomic, assign, readonly) NSTimeInterval reconnectInterval;
@property (nonatomic, assign, readonly) NSInteger maxReconnectAttempts;

- (instancetype)initWithServerURL:(NSURL *)serverURL;
- (instancetype)initWithServerURL:(NSURL *)serverURL accessToken:(NSString *)accessToken;
- (void)connect;
- (void)disconnect;
- (void)setAccessToken:(NSString *)accessToken;
- (nullable NSString *)getStoredCursorForRepo:(NSString *)repo;
- (void)storeCursor:(NSString *)cursor forRepo:(NSString *)repo;

@end

NS_ASSUME_NONNULL_END
