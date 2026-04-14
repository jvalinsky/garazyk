/*!
 * @file PDSRelayService.h
 * @abstract Service for notifying external relays of repository updates.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PDSRelayService : NSObject

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
