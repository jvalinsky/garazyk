#import "HttpRouter.h"
#import "HttpRequest.h"
#import "HttpResponse.h"

@interface HttpRoute ()

@property (nonatomic, readwrite, copy) NSString *method;
@property (nonatomic, readwrite, copy) NSString *pattern;
@property (nonatomic, readwrite, copy) HttpRouteHandler handler;
@property (nonatomic, readwrite) NSUInteger priority;

@end

@implementation HttpRoute

- (instancetype)initWithMethod:(NSString *)method
                       pattern:(NSString *)pattern
                       handler:(HttpRouteHandler)handler
                      priority:(NSUInteger)priority {
    self = [super init];
    if (self) {
        _method = [method copy];
        _pattern = [pattern copy];
        _handler = [handler copy];
        _priority = priority;
    }
    return self;
}

@end

@interface HttpRouter ()

@property (nonatomic, strong) NSMutableArray<HttpRoute *> *routes;
@property (nonatomic, strong) dispatch_queue_t routingQueue;

@end

@implementation HttpRouter

- (instancetype)init {
    self = [super init];
    if (self) {
        _routes = [NSMutableArray array];
        _routingQueue = dispatch_queue_create("com.atproto.pds.router", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)addRoute:(NSString *)method
         pattern:(NSString *)pattern
         handler:(HttpRouteHandler)handler {
    [self addRoute:method pattern:pattern handler:handler priority:100];
}

- (void)addRoute:(NSString *)method
         pattern:(NSString *)pattern
         handler:(HttpRouteHandler)handler
        priority:(NSUInteger)priority {

    // Validate inputs
    NSAssert(method != nil, @"Method cannot be nil");
    NSAssert(pattern != nil, @"Pattern cannot be nil");
    NSAssert(handler != nil, @"Handler cannot be nil");

    // Prevent path traversal in patterns
    if ([pattern containsString:@".."] || [pattern containsString:@"//"]) {
        NSAssert(NO, @"Invalid pattern: contains path traversal sequences");
        return;
    }

    HttpRoute *route = [[HttpRoute alloc] initWithMethod:method
                                                 pattern:pattern
                                                 handler:handler
                                                priority:priority];

    dispatch_barrier_async(self.routingQueue, ^{
        [self.routes addObject:route];

        // Sort routes by priority (higher priority first)
        [self.routes sortUsingComparator:^NSComparisonResult(HttpRoute *a, HttpRoute *b) {
            if (a.priority > b.priority) return NSOrderedAscending;
            if (a.priority < b.priority) return NSOrderedDescending;
            return NSOrderedSame;
        }];
    });
}

- (nullable HttpRouteHandler)handlerForRequest:(HttpRequest *)request {
    __block HttpRouteHandler foundHandler = nil;

    dispatch_sync(self.routingQueue, ^{
        NSString *requestMethod = request.methodString;
        NSString *requestPath = request.path;

        // Prevent path traversal attacks
        if ([requestPath containsString:@".."] || [requestPath hasPrefix:@"/"]) {
            // Normalize path to prevent traversal
            requestPath = [self normalizePath:requestPath];
        }

        for (HttpRoute *route in self.routes) {
            if ([self route:route matchesMethod:requestMethod path:requestPath]) {
                foundHandler = route.handler;
                break;
            }
        }
    });

    return foundHandler;
}

- (BOOL)route:(HttpRoute *)route matchesMethod:(NSString *)method path:(NSString *)path {
    // Check method match
    if (![route.method isEqualToString:@"*"] && ![route.method isEqualToString:method]) {
        return NO;
    }

    // Check path match
    return [self path:path matchesPattern:route.pattern];
}

- (BOOL)path:(NSString *)path matchesPattern:(NSString *)pattern {
    // Exact match
    if ([path isEqualToString:pattern]) {
        return YES;
    }

    // Parameter pattern matching (e.g., "/users/:id")
    return [self path:path matchesParameterizedPattern:pattern];
}

- (BOOL)path:(NSString *)path matchesParameterizedPattern:(NSString *)pattern {
    NSArray<NSString *> *pathComponents = [path componentsSeparatedByString:@"/"];
    NSArray<NSString *> *patternComponents = [pattern componentsSeparatedByString:@"/"];

    if (pathComponents.count != patternComponents.count) {
        return NO;
    }

    for (NSUInteger i = 0; i < pathComponents.count; i++) {
        NSString *pathComponent = pathComponents[i];
        NSString *patternComponent = patternComponents[i];

        // Parameter component (starts with ':')
        if ([patternComponent hasPrefix:@":"]) {
            continue; // Parameter matches anything
        }

        // Wildcard component
        if ([patternComponent isEqualToString:@"*"]) {
            continue; // Wildcard matches anything
        }

        // Exact match required
        if (![pathComponent isEqualToString:patternComponent]) {
            return NO;
        }
    }

    return YES;
}

- (nullable NSDictionary<NSString *, NSString *> *)extractParametersFromPath:(NSString *)path
                                                                     pattern:(NSString *)pattern {
    NSMutableDictionary<NSString *, NSString *> *parameters = [NSMutableDictionary dictionary];

    NSArray<NSString *> *pathComponents = [path componentsSeparatedByString:@"/"];
    NSArray<NSString *> *patternComponents = [pattern componentsSeparatedByString:@"/"];

    if (pathComponents.count != patternComponents.count) {
        return nil;
    }

    for (NSUInteger i = 0; i < pathComponents.count; i++) {
        NSString *pathComponent = pathComponents[i];
        NSString *patternComponent = patternComponents[i];

        if ([patternComponent hasPrefix:@":"]) {
            // Extract parameter
            NSString *paramName = [patternComponent substringFromIndex:1];
            parameters[paramName] = pathComponent;
        }
    }

    return [parameters copy];
}

- (NSString *)normalizePath:(NSString *)path {
    // Remove leading slashes and normalize
    while ([path hasPrefix:@"/"]) {
        path = [path substringFromIndex:1];
    }

    // Prevent directory traversal
    if ([path containsString:@".."]) {
        // In a secure implementation, this would return an error
        // For now, we'll sanitize by removing dangerous sequences
        path = [path stringByReplacingOccurrencesOfString:@".." withString:@""];
        path = [path stringByReplacingOccurrencesOfString:@"//" withString:@"/"];
    }

    return path;
}

@end</content>
<parameter name="filePath">/Users/jack/Software/objpds/ATProtoPDS/Sources/Network/HttpRouter.m