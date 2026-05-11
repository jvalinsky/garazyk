/*!
 @file GermRuntime.h

 @brief Standalone runtime for the Germ E2EE mailbox service.

 @discussion The Germ mailbox service runs as a separate process from
 the PDS, matching Germ's architecture. It manages ephemeral and
 rendezvous mailbox addresses for E2EE message transport.

 Models after Germ's current shipping 1:1 E2EE DM product.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GermRuntime : NSObject

@property (nonatomic, readonly) BOOL isRunning;

+ (instancetype)sharedRuntime;

- (BOOL)startWithDataDirectory:(NSString *)dataDirectory
                      port:(uint16_t)port
                     error:(NSError **)error;

- (void)stop;

@end

NS_ASSUME_NONNULL_END
