/*!
 @file HttpRouteTrie.m

 @abstract Implements trie-based route matching structures for HTTP path resolution.

 @discussion Provides prefix/path-segment indexing used by router logic to locate matching handlers efficiently. Owns route-structure mechanics without executing endpoint domain behavior.
 */

#import "HttpRouteTrie.h"
#import "Compat/PDSTypes.h"
#import "HttpRouter.h"

@interface HttpRouteNode : NSObject

@property (nonatomic, strong) NSMutableDictionary<NSString *, HttpRouteNode *> *children;
@property (nonatomic, strong, nullable) NSMutableDictionary<NSString *, HttpRoute *> *methodRoutes;
@property (nonatomic, strong, nullable) HttpRoute *wildcardRoute;
@property (nonatomic, copy, nullable) NSString *paramName;

@end

@implementation HttpRouteNode

- (instancetype)init {
    self = [super init];
    if (self) {
        _children = [NSMutableDictionary dictionary];
        _methodRoutes = nil;
        _wildcardRoute = nil;
        _paramName = nil;
    }
    return self;
}

@end

@interface HttpRouteTrie ()

@property (nonatomic, strong) HttpRouteNode *root;
@property (nonatomic, strong) NSMutableArray<HttpRoute *> *allRoutes;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t trieQueue;

@end

@implementation HttpRouteTrie

- (instancetype)init {
    self = [super init];
    if (self) {
        _root = [[HttpRouteNode alloc] init];
        _allRoutes = [NSMutableArray array];
        _trieQueue = dispatch_queue_create("com.atproto.pds.trie", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)insertRoute:(NSString *)method
            pattern:(NSString *)pattern
            handler:(HttpRouteHandler)handler
           priority:(NSUInteger)priority {
    HttpRoute *route = [[HttpRoute alloc] initWithMethod:method
                                                pattern:pattern
                                                handler:handler
                                               priority:priority];

    dispatch_barrier_async(self.trieQueue, ^{
        [self insertRouteIntoTrie:route atNode:self.root];
        [self.allRoutes addObject:route];
    });
}

- (void)insertRouteIntoTrie:(HttpRoute *)route atNode:(HttpRouteNode *)node {
    NSArray<NSString *> *components = [self splitPattern:route.pattern];

    HttpRouteNode *current = node;
    for (NSUInteger i = 0; i < components.count; i++) {
        NSString *component = components[i];

        if ([component hasPrefix:@":"]) {
            NSString *paramName = [component substringFromIndex:1];

            HttpRouteNode *paramNode = nil;
            for (HttpRouteNode *child in current.children.allValues) {
                if (child.paramName) {
                    paramNode = child;
                    break;
                }
            }

            if (!paramNode) {
                paramNode = [[HttpRouteNode alloc] init];
                paramNode.paramName = paramName;
                current.children[@"*"] = paramNode;
            }

            current = paramNode;
        } else if ([component isEqualToString:@"*"]) {
            if (!current.wildcardRoute) {
                current.wildcardRoute = route;
            }
            return;
        } else {
            HttpRouteNode *child = current.children[component];
            if (!child) {
                child = [[HttpRouteNode alloc] init];
                current.children[component] = child;
            }
            current = child;
        }
    }

    if (!current.methodRoutes) {
        current.methodRoutes = [NSMutableDictionary dictionary];
    }
    current.methodRoutes[route.method] = route;
}

- (nullable HttpRouteHandler)handlerForMethod:(NSString *)method
                                         path:(NSString *)path
                                  outParameters:(NSDictionary<NSString *, NSString *> * _Nullable * _Nullable)outParams {
    __block HttpRouteHandler foundHandler = nil;
    __block NSDictionary<NSString *, NSString *> *foundParams = nil;

    dispatch_sync(self.trieQueue, ^{
        NSArray<NSString *> *components = [self splitPath:path];
        HttpRouteNode *current = self.root;

        NSMutableDictionary<NSString *, NSString *> *params = [NSMutableDictionary dictionary];

        for (NSUInteger i = 0; i < components.count; i++) {
            NSString *component = components[i];
            
            
            HttpRouteNode *child = current.children[component];
            if (child) {
                current = child;
            } else if (current.children[@"*"] && current.children[@"*"].paramName) {
                NSString *paramName = current.children[@"*"].paramName;
                if (paramName) {
                    params[paramName] = component;
                }
                current = current.children[@"*"];
            } else if (current.wildcardRoute) {
                // Wildcard match!
                foundHandler = current.wildcardRoute.handler;
                foundParams = [params copy];
                return;
            } else {
                return;
            }
        }

        if (current.methodRoutes) {
            HttpRoute *route = current.methodRoutes[method];
            if (route) {
                foundHandler = route.handler;
                foundParams = [params copy];
                return;
            }

            route = current.methodRoutes[@"*"];
            if (route && [route.method isEqualToString:@"*"]) {
                foundHandler = route.handler;
                foundParams = [params copy];
                return;
            }
        }

        if (current.wildcardRoute) {
            foundHandler = current.wildcardRoute.handler;
            foundParams = [params copy];
        }
    });

    if (outParams && foundParams) {
        *outParams = foundParams;
    }

    return foundHandler;
}

- (NSArray<NSString *> *)splitPattern:(NSString *)pattern {
    NSMutableArray<NSString *> *components = [NSMutableArray array];
    NSArray<NSString *> *parts = [pattern componentsSeparatedByString:@"/"];

    for (NSString *part in parts) {
        if (part.length > 0) {
            [components addObject:part];
        }
    }

    return [components copy];
}

- (NSArray<NSString *> *)splitPath:(NSString *)path {
    return [self splitPattern:path];
}

- (NSUInteger)count {
    __block NSUInteger count = 0;
    dispatch_sync(self.trieQueue, ^{
        count = self.allRoutes.count;
    });
    return count;
}

@end
