#import <Foundation/Foundation.h>

@class OAuth2Server;
@class HttpServer;
@class PDSDatabase;
@class HttpRequest;
@class HttpResponse;

NS_ASSUME_NONNULL_BEGIN

/*!
 @class OAuth2Handler
 
 @abstract HTTP handler for OAuth 2.0 endpoints.
 
 @discussion This class provides HTTP request handlers for the standard
 OAuth 2.0 endpoints: authorize, token, and revoke. It integrates with
 the OAuth2Server class to process authorization requests and issue tokens.
 */
@interface OAuth2Handler : NSObject

/*! The underlying OAuth 2.0 server implementation. */
@property (nonatomic, strong) OAuth2Server *server;

/*!
 @method initWithDatabase:
 
 @abstract Initializes a new OAuth2 handler with a database.
 
 @param database The database to use for client storage.
 @return An initialized OAuth2Handler instance.
 */
- (instancetype)initWithDatabase:(PDSDatabase *)database;

/*!
 @method init
 
 @abstract Initializes a new OAuth2 handler.
 
 @return An initialized OAuth2Handler instance.
 */
- (instancetype)init;

/*!
 @method registerRoutesWithServer:
 
 @abstract Registers OAuth 2.0 routes with the HTTP server.
 
 @param httpServer The HTTP server to register routes with.
 */
- (void)registerRoutesWithServer:(HttpServer *)httpServer;

- (void)handleTokenRequest:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleAuthorizeRequest:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleRevokeRequest:(HttpRequest *)request response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END