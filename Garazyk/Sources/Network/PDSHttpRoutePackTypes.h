/*!
 @file PDSHttpRoutePackTypes.h

 @abstract Shared type definitions for HTTP route pack registration helpers.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;

typedef void (^PDSHttpSetCorsHeadersBlock)(HttpResponse *response,
                                           HttpRequest *request);

NS_ASSUME_NONNULL_END

