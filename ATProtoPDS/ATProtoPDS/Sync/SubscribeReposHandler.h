#import <Foundation/Foundation.h>

@class WebSocketServer;
@class WebSocketConnection;
@class PDSController;
@class EventFormatter;
@class RepoCommit;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SubscribeReposHandlerErrorDomain;
extern NSInteger const SubscribeReposHandlerErrorCodeConnectionFailed;

@protocol SubscribeReposHandlerDelegate <NSObject>
@optional
- (void)subscribeReposHandlerDidStart:(id)handler;
- (void)subscribeReposHandlerDidStop:(id)handler;
- (void)subscribeReposHandler:(id)handler didAcceptConnection:(WebSocketConnection *)connection;
- (void)subscribeReposHandler:(id)handler didCloseConnection:(WebSocketConnection *)connection;
@end

@interface SubscribeReposHandler : NSObject

@property (nonatomic, weak, nullable) id<SubscribeReposHandlerDelegate> delegate;
@property (nonatomic, readonly) WebSocketServer *webSocketServer;
@property (nonatomic, readonly) EventFormatter *eventFormatter;
@property (nonatomic, readonly) PDSController *controller;

- (instancetype)initWithController:(PDSController *)controller;
- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error;
- (void)stop;
- (void)broadcastRepositoryCommit:(RepoCommit *)commit forRepo:(NSString *)repoDid;
- (void)broadcastIdentityChange:(NSString *)did handle:(nullable NSString *)handle;

@end

NS_ASSUME_NONNULL_END