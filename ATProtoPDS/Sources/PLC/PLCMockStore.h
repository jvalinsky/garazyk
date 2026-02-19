/*!
 @file PLCMockStore.h

 @abstract In-memory PLCStore implementation for tests and local development.
 */

#import <Foundation/Foundation.h>
#import "PLCStore.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PLCMockStore

 @abstract In-memory implementation of the PLCStore protocol.

 @discussion Stores operation history in process memory and is primarily
 intended for tests, smoke flows, and local tooling.
 */
@interface PLCMockStore : NSObject <PLCStore>

@end

NS_ASSUME_NONNULL_END
