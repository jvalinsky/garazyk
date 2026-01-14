#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;

typedef void (^HttpRouteHandler)(HttpRequest *request, HttpResponse *response);

/*!
 @class HttpRouteTrie

 @abstract Trie-based router for O(k) route lookup performance.

 @discussion HttpRouteTrie organizes routes in a tree structure where each
 node represents a path segment. This enables efficient route matching
 with support for parameters and wildcards.
 */
@interface HttpRouteTrie : NSObject

/*!
 @method insertRoute:pattern:handler:priority:

 @abstract Inserts a route into the trie.

 @param method The HTTP method (GET, POST, etc.) or "*" for all methods.
 @param pattern The URL pattern with optional parameters (e.g., "/users/:id").
 @param handler The handler block to execute for matching requests.
 @param priority Route priority for resolution ordering.
 */
- (void)insertRoute:(NSString *)method
            pattern:(NSString *)pattern
            handler:(HttpRouteHandler)handler
           priority:(NSUInteger)priority;

/*!
 @method handlerForMethod:path:

 @abstract Finds the handler for a given method and path.

 @param method The HTTP method.
 @param path The request path.

 @return The matching handler and extracted parameters, or nil if no match.
 */
- (nullable HttpRouteHandler)handlerForMethod:(NSString *)method
                                         path:(NSString *)path
                                  outParameters:(NSDictionary<NSString *, NSString *> * _Nullable * _Nullable)parameters;

/*!
 @method count

 @abstract Returns the number of routes in the trie.

 @return The route count.
 */
- (NSUInteger)count;

@end

NS_ASSUME_NONNULL_END
