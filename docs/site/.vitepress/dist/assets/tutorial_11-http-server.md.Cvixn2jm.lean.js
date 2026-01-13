import{C as h,c as p,o as k,ag as i,G as e}from"./chunks/framework.EuUYIJ38.js";const g=JSON.parse('{"title":"Chapter 11: HTTP Server with Grand Central Dispatch","description":"","frontmatter":{},"headers":[],"relativePath":"tutorial/11-http-server.md","filePath":"tutorial/11-http-server.md"}'),r={name:"tutorial/11-http-server.md"},c=Object.assign(r,{setup(E){const a=`#import <Foundation/Foundation.h>

// --- Mock Classes for Simulation ---

@interface HttpRequest : NSObject
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *remoteAddress;
@property (nonatomic, copy) NSDictionary *headers;
+ (instancetype)requestWithMethod:(NSString *)m path:(NSString *)p;
@end

@implementation HttpRequest
+ (instancetype)requestWithMethod:(NSString *)m path:(NSString *)p {
    HttpRequest *r = [HttpRequest new];
    r.method = m; r.path = p; r.remoteAddress = @"127.0.0.1";
    return r;
}
@end

@interface HttpResponse : NSObject
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, strong) NSMutableDictionary *headers;
@property (nonatomic, copy) NSDictionary *body;
@end

@implementation HttpResponse
- (instancetype)init { if(self=[super init]) _headers = [NSMutableDictionary dictionary]; return self; }
@end

typedef void (^RequestHandler)(HttpRequest *, HttpResponse *);
typedef BOOL (^MiddlewareHandler)(HttpRequest *, HttpResponse *);

@interface HttpServer : NSObject
@property (nonatomic, strong) NSMutableArray<MiddlewareHandler> *middlewares;
@property (nonatomic, strong) NSMutableDictionary *routes;
- (void)addRoute:(NSString *)method path:(NSString *)path handler:(RequestHandler)handler;
- (void)addMiddleware:(MiddlewareHandler)middleware;
- (HttpResponse *)dispatch:(HttpRequest *)req;
@end

@implementation HttpServer
- (instancetype)init {
    if(self=[super init]) {
        _middlewares = [NSMutableArray array];
        _routes = [NSMutableDictionary dictionary];
    }
    return self;
}
- (void)addRoute:(NSString *)method path:(NSString *)path handler:(RequestHandler)handler {
    NSString *key = [NSString stringWithFormat:@"%@ %@", method, path];
    self.routes[key] = [handler copy];
}
- (void)addMiddleware:(MiddlewareHandler)middleware {
    [self.middlewares addObject:[middleware copy]];
}
- (HttpResponse *)dispatch:(HttpRequest *)req {
    HttpResponse *resp = [HttpResponse new];
    
    // 1. Run Middleware
    for (MiddlewareHandler mw in self.middlewares) {
        if (!mw(req, resp)) return resp; // Middleware intercepted
    }
    
    // 2. Route Dispatch
    NSString *key = [NSString stringWithFormat:@"%@ %@", req.method, req.path];
    RequestHandler h = self.routes[key];
    if (h) {
        h(req, resp);
    } else {
        resp.statusCode = 404;
    }
    return resp;
}
@end
`,t=a+`
// --- EXERCISE 1: Logger Middleware ---

void runDemo() {
    HttpServer *server = [HttpServer new];
    
    // Setup a route
    [server addRoute:@"GET" path:@"/health" handler:^(HttpRequest *req, HttpResponse *resp) {
        resp.statusCode = 200;
        resp.body = @{@"status": @"ok"};
    }];
    
    // TODO: Add Logger Middleware
    // Should log: "METHOD PATH from IP"
    [server addMiddleware:^BOOL(HttpRequest *req, HttpResponse *resp) {
        // Implement logger here
        // Return YES to continue, NO to stop
        return YES;
    }];
    
    // Simulate Request
    printf("Simulating GET /health...\\n");
    [server dispatch:[HttpRequest requestWithMethod:@"GET" path:@"/health"]];
}

int main() {
    @autoreleasepool {
        runDemo();
    }
    return 0;
}`,l=a+`
// --- EXERCISE 3: CORS Middleware ---

void runDemo() {
    HttpServer *server = [HttpServer new];
    
    [server addRoute:@"GET" path:@"/api/data" handler:^(HttpRequest *req, HttpResponse *resp) {
        resp.statusCode = 200;
        resp.body = @{@"data": @123};
    }];
    
    // TODO: Add CORS Middleware
    // Set headers: Access-Control-Allow-Origin: *
    [server addMiddleware:^BOOL(HttpRequest *req, HttpResponse *resp) {
        // Implement CORS here
        return YES;
    }];
    
    // Simulate Request
    HttpResponse *resp = [server dispatch:[HttpRequest requestWithMethod:@"GET" path:@"/api/data"]];
    
    printf("Status: %ld\\n", resp.statusCode);
    printf("CORS Header: %s\\n", [resp.headers[@"Access-Control-Allow-Origin"] UTF8String]);
    
    if ([resp.headers[@"Access-Control-Allow-Origin"] isEqualToString:@"*"]) {
        printf("PASS: CORS header present.\\n");
    } else {
        printf("FAIL: Missing CORS header.\\n");
    }
}

int main() {
    @autoreleasepool {
        runDemo();
    }
    return 0;
}`;return(d,s)=>{const n=h("ObjcRunner");return k(),p("div",null,[s[0]||(s[0]=i("",166)),e(n,{initialCode:t}),s[1]||(s[1]=i("",7)),e(n,{initialCode:l}),s[2]||(s[2]=i("",15))])}}});export{g as __pageData,c as default};
