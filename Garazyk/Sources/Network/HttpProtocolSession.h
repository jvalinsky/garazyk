#import <Foundation/Foundation.h>
#import "Network/Http1Parser.h"
#import "Network/Http1PipelinePolicy.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @typedef HttpSessionEvent
 * @abstract Events returned by the HttpProtocolSession state machine.
 */
typedef NS_ENUM(NSInteger, HttpSessionEvent) {
  /** A full HTTP request has been parsed and is ready for dispatch. */
  HttpSessionEventRequestReady,
  /** A protocol error occurred (e.g., malformed request). */
  HttpSessionEventError,
  /** A protocol upgrade was detected (e.g., WebSocket). */
  HttpSessionEventUpgrade,
  /** The connection should be closed (e.g., after a non-keep-alive response). */
  HttpSessionEventClose
};

/**
 * @class HttpProtocolSession
 * @abstract A pure Sans-I/O state machine for HTTP/1.1 session management.
 * @discussion This class coordinates the parser and pipeline policy, returning
 * events for the driver to act upon. It does not perform any I/O.
 */
@interface HttpProtocolSession : NSObject

@property(nonatomic, readonly) Http1Parser *parser;
@property(nonatomic, readonly) Http1PipelinePolicy *pipelinePolicy;
@property(nonatomic, assign) BOOL upgradedToWebSocket;

/**
 * @method feedData:
 * @abstract Feeds raw bytes from the wire into the session state machine.
 * @param data The bytes received from the network.
 * @return An array of events for the driver to process.
 */
- (NSArray<NSNumber *> *)feedData:(NSData *)data;

/**
 * @method nextRequestToDispatch
 * @abstract Returns the next pending request that is allowed by the pipeline
 * policy.
 * @return The request to dispatch, or nil if none are ready or allowed.
 */
- (nullable HttpRequest *)nextRequestToDispatch;

/**
 * @method queueResponse:
 * @abstract Queues a response to be sent for the oldest in-flight request.
 * @param response The HTTP response to send.
 */
- (void)queueResponse:(HttpResponse *)response;

/**
 * @method resetForNextRequest
 * @abstract Resets the parser for the next request on the same connection.
 */
- (void)resetForNextRequest;

@end

NS_ASSUME_NONNULL_END
