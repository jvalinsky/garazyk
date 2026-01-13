import{C as r,c as E,o as d,ag as h,G as t,j as i,a as p}from"./chunks/framework.EuUYIJ38.js";const F=JSON.parse('{"title":"Chapter 12: XRPC Endpoints","description":"","frontmatter":{},"headers":[],"relativePath":"tutorial/12-xrpc-endpoints.md","filePath":"tutorial/12-xrpc-endpoints.md"}'),o={name:"tutorial/12-xrpc-endpoints.md"},u=Object.assign(o,{setup(g){const a=`#import <Foundation/Foundation.h>

// --- Mock Classes (HTTP) ---

@interface HttpRequest : NSObject
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *remoteAddress;
@property (nonatomic, copy) NSDictionary *queryParams;
@property (nonatomic, copy) NSDictionary *jsonBody;
@property (nonatomic, copy) NSData *body;
@property (nonatomic, copy) NSString *contentType;
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
@property (nonatomic, copy) NSDictionary *jsonBody;
@end

@implementation HttpResponse
- (instancetype)init { if(self=[super init]) _headers = [NSMutableDictionary dictionary]; return self; }
- (void)setJsonBody:(NSDictionary *)jsonBody { _jsonBody = jsonBody; }
@end

typedef void (^RequestHandler)(HttpRequest *, HttpResponse *);

// --- Mock XRPC Dispatcher ---

@interface XrpcDispatcher : NSObject
@property (nonatomic, strong) NSMutableDictionary *handlers;
- (void)registerMethod:(NSString *)method handler:(RequestHandler)handler;
- (void)dispatch:(HttpRequest *)req response:(HttpResponse *)resp;
@end

@implementation XrpcDispatcher
- (instancetype)init { if(self=[super init]) _handlers = [NSMutableDictionary dictionary]; return self; }
- (void)registerMethod:(NSString *)method handler:(RequestHandler)handler {
    self.handlers[method] = [handler copy];
}
- (void)dispatch:(HttpRequest *)req response:(HttpResponse *)resp {
    if (![req.path hasPrefix:@"/xrpc/"]) {
        resp.statusCode = 404; resp.jsonBody = @{@"error": @"NotXRPC"}; return;
    }
    NSString *method = [req.path substringFromIndex:6];
    RequestHandler h = self.handlers[method];
    if (h) h(req, resp);
    else { resp.statusCode = 400; resp.jsonBody = @{@"error": @"MethodNotFound"}; }
}
@end
`,e=a+`
// --- EXERCISE 1: Implement describeServer ---

void runDemo() {
    XrpcDispatcher *dispatcher = [XrpcDispatcher new];
    
    // TODO: Implement describeServer handler
    // URL: /xrpc/com.atproto.server.describeServer
    // Response: { "availableUserDomains": [".bsky.social"], "did": "did:web:example.com" }
    [dispatcher registerMethod:@"com.atproto.server.describeServer" handler:^(HttpRequest *req, HttpResponse *resp) {
        // Your code here
        resp.statusCode = 501; // Not Implemented
    }];
    
    // Simulate Request
    HttpRequest *req = [HttpRequest requestWithMethod:@"GET" path:@"/xrpc/com.atproto.server.describeServer"];
    HttpResponse *resp = [HttpResponse new];
    [dispatcher dispatch:req response:resp];
    
    printf("Status: %ld\\n", resp.statusCode);
    printf("Response: %s\\n", resp.jsonBody.description.UTF8String);
    
    if (resp.statusCode == 200 && resp.jsonBody[@"did"]) {
        printf("PASS: Server described.\\n");
    } else {
        printf("FAIL: correct response not implemented.\\n");
    }
}

int main() {
    @autoreleasepool {
        runDemo();
    }
    return 0;
}`,l=a+`
// --- EXERCISE 2: Blob Upload ---

void runDemo() {
    XrpcDispatcher *dispatcher = [XrpcDispatcher new];
    
    // TODO: Implement uploadBlob
    // Expect: Content-Type header, Body data
    // Return: { "blob": { "ref": "...", "size": ... } }
    [dispatcher registerMethod:@"com.atproto.repo.uploadBlob" handler:^(HttpRequest *req, HttpResponse *resp) {
        if (![req.method isEqualToString:@"POST"]) {
            resp.statusCode = 400; return;
        }
        // Your code here: check content type, return blob metadata
        resp.statusCode = 501;
    }];
    
    // Simulate Upload
    HttpRequest *req = [HttpRequest requestWithMethod:@"POST" path:@"/xrpc/com.atproto.repo.uploadBlob"];
    req.contentType = @"image/png";
    req.body = [NSData dataWithBytes:"PNG..." length:6];
    
    HttpResponse *resp = [HttpResponse new];
    [dispatcher dispatch:req response:resp];
    
    printf("Status: %ld\\n", resp.statusCode);
    if (resp.statusCode == 200 && resp.jsonBody[@"blob"]) {
        printf("PASS: Blob uploaded.\\n");
    } else {
        printf("FAIL.\\n");
    }
}

int main() {
    @autoreleasepool {
        runDemo();
    }
    return 0;
}`,k=a+`
// --- EXERCISE 3: Rate Limiting ---

@interface RateLimiter : NSObject
- (BOOL)allowRequest:(HttpRequest *)req;
@end
@implementation RateLimiter
- (BOOL)allowRequest:(HttpRequest *)req {
    // TODO: Implement rate limiting logic
    // Allow max 2 requests
    static int count = 0;
    count++;
    return count <= 2;
}
@end

void runDemo() {
    XrpcDispatcher *dispatcher = [XrpcDispatcher new];
    RateLimiter *limiter = [RateLimiter new];
    
    RequestHandler realHandler = ^(HttpRequest *req, HttpResponse *resp) {
        resp.statusCode = 200; resp.jsonBody = @{@"ok": @YES};
    };
    
    [dispatcher registerMethod:@"com.test.method" handler:^(HttpRequest *req, HttpResponse *resp) {
        if (![limiter allowRequest:req]) {
            resp.statusCode = 429; 
            resp.jsonBody = @{@"error": @"RateLimitExceeded"};
            return;
        }
        realHandler(req, resp);
    }];
    
    // Simulate 3 requests
    for (int i=1; i<=3; i++) {
        HttpResponse *resp = [HttpResponse new];
        [dispatcher dispatch:[HttpRequest requestWithMethod:@"GET" path:@"/xrpc/com.test.method"] response:resp];
        printf("Req %d: Status %ld\\n", i, resp.statusCode);
    }
}

int main() {
    @autoreleasepool {
        runDemo();
    }
    return 0;
}`;return(y,s)=>{const n=r("ObjcRunner");return d(),E("div",null,[s[0]||(s[0]=h("",113)),t(n,{initialCode:e}),s[1]||(s[1]=i("p",null,[p("📝 "),i("strong",null,"Exercise 2: Add Blob Upload")],-1)),s[2]||(s[2]=i("p",null,"Implement the uploadBlob endpoint:",-1)),t(n,{initialCode:l}),s[3]||(s[3]=i("p",null,[p("📝 "),i("strong",null,"Exercise 3: Rate Limiting")],-1)),s[4]||(s[4]=i("p",null,"Add rate limiting to your XRPC dispatcher:",-1)),t(n,{initialCode:k}),s[5]||(s[5]=h("",15))])}}});export{F as __pageData,u as default};
