/*!
 @file CappuccinoUIHandler.h

 @abstract HTTP handler for Objective-J/Cappuccino web UI assets.
 */

#import <Foundation/Foundation.h>
#import "Compat/PDSTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;
@class PDSController;

/*!
 @class CappuccinoUIHandler

 @abstract Serves static assets for the Objective-J/Cappuccino app under `/ui`.
 */
@interface CappuccinoUIHandler : NSObject

/*!
 @method sharedHandler

 @abstract Returns the process-wide Cappuccino UI handler instance.
 */
+ (instancetype)sharedHandler;

/*!
 @method setDataDirectory:

 @abstract Sets the data directory used when resolving asset paths.
 */
- (void)setDataDirectory:(NSString *)dataDirectory;

/*!
 @method setController:

 @abstract Legacy controller-based wiring for obtaining data directory context.
 */
- (void)setController:(PDSController *)controller
    DEPRECATED_MSG_ATTRIBUTE("Use setDataDirectory: instead");

/*!
 @method canHandleRequest:

 @abstract Returns YES for requests rooted at `/ui`.
 */
- (BOOL)canHandleRequest:(HttpRequest *)request;

/*!
 @method handleRequest:response:

 @abstract Serves the requested `/ui` asset or an error payload.
 */
- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END
