// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 * @file PDSRelayService.h
 * @abstract Service for notifying external relays of repository updates.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 * @protocol PDSRelayTransport
 * @abstract Transport abstraction for relay HTTP requests.
 *
 * @discussion Allows injection of mock transports for testing.
 * The default implementation uses NSURLSession.
 */
@protocol PDSRelayTransport <NSObject>

/*!
 * @method sendRequest:completionHandler:
 * @abstract Sends an HTTP request and calls the handler with the response.
 * @param request The URL request to send.
 * @param handler Called with (data, response, error) on completion.
 */
- (void)sendRequest:(NSURLRequest *)request
   completionHandler:(void (^)(NSData * _Nullable data,
                               NSURLResponse * _Nullable response,
                               NSError * _Nullable error))handler;

@end

@interface PDSRelayService : NSObject

/*! Transport for sending relay notifications. Defaults to NSURLSession. */
@property (nonatomic, strong) id<PDSRelayTransport> transport;

/*!
 * Initializes the service.
 * @param relays The list of relay hosts to notify (e.g.,
 * @[@"https://bsky.network"]).
 * @param hostname The public hostname of this PDS.
 */
- (instancetype)initWithRelays:(NSArray<NSString *> *)relays
                      hostname:(NSString *)hostname;

/*! Starts listening for repository change notifications and notifying relays.
 */
- (void)start;

/*! Stops listening for notifications. */
- (void)stop;

/*!
 * Manually notifies a specific relay host to crawl this PDS.
 * @param relayHost The relay hostname (e.g., "https://bsky.network").
 */
- (void)notifyRelay:(NSString *)relayHost;

@end

NS_ASSUME_NONNULL_END
