#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;
@class HttpServer;

typedef void (^RequestHandler)(HttpRequest *request, HttpResponse *response);

@interface HttpServer : NSObject

@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, copy, nullable) void (^didReceiveRequest)(HttpRequest *request, HttpResponse *response);

+ (instancetype)serverWithPort:(uint16_t)port;

- (BOOL)startWithError:(NSError * _Nullable *)error;
- (void)stop;

- (void)addRoute:(NSString *)method path:(NSString *)path handler:(RequestHandler)handler;
- (void)addHandlerForPath:(NSString *)path handler:(RequestHandler)handler;

@end

NS_ASSUME_NONNULL_END
