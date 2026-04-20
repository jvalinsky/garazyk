#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;

typedef void (^HttpServerRequestHandler)(HttpRequest *request, HttpResponse *response);
typedef HttpServerRequestHandler _Nullable (^HttpRouteLookupHandler)(
    NSString *path,
    NSString *method,
    NSDictionary<NSString *, NSString *> *_Nullable *_Nullable parameters);

@interface HttpRequestDispatcher : NSObject

@property(nonatomic, copy, nullable) HttpServerRequestHandler requestHandler;
@property(nonatomic, copy) HttpRouteLookupHandler routeLookupHandler;

- (instancetype)initWithRouteLookupHandler:(HttpRouteLookupHandler)routeLookupHandler;
- (HttpResponse *)dispatchRequest:(HttpRequest *)request;

@end

NS_ASSUME_NONNULL_END
